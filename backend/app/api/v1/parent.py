"""
Parent / guardianship endpoints.

Linking is consent-based via a short-lived code, so a parent can't attach to an
arbitrary child by guessing a phone number:

  POST /v1/parent/link-code   -> a 6-char code, valid ~10 min, single-use
  POST /v1/parent/link        -> {code} establishes guardianship
  GET  /v1/parent/children    -> linked children + their progress
  GET  /v1/parent/children/{id} -> one child's progress (must be linked)

AUTHZ NOTE (2026-08-06). These endpoints used to require `role == "parent"`, which
made the whole feature unreachable in practice: a role is fixed at signup, phone
login is disabled (SMS_PROVIDER=disabled), and a family testing on one device has
exactly one account. A tester who entered a valid code got 403 and read it as
"the code doesn't work".

The role was never the security boundary anyway — the **guardianship row** is, and
it can only be created by someone holding a code the child themselves generated
and handed over. So authz here is now: any authenticated user may hold a code, and
every read is gated on an existing guardianship link. Self-linking stays blocked.

Parent dashboards are strictly read-only: there is no endpoint here that mutates a
child's data.
"""
from __future__ import annotations

import secrets
import uuid

from fastapi import APIRouter, Depends, Header, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.ratelimit import client_ip, hit as ratelimit_hit
from app.core.redis import get_redis
from app.models import Guardianship, User
from app.schemas.leaderboard import ProgressOut
from app.schemas.parent import (
    ChildrenOut, ChildSummary, LinkCodeOut, LinkIn,
)
from app.services import analysis as analysis_service
from app.services import progress as progress_service

router = APIRouter(prefix="/v1/parent", tags=["parent"])
_settings = get_settings()

_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no ambiguous 0/O/1/I

def _gen_link_code() -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(6))

def _link_key(code: str) -> str:
    return f"link:{code.upper()}"

@router.post("/link-code", response_model=LinkCodeOut)
async def create_link_code(student: User = Depends(get_current_user)):
    code = _gen_link_code()
    await get_redis().set(
        _link_key(code), str(student.id), ex=_settings.link_code_ttl_seconds
    )
    return LinkCodeOut(code=code, expires_in_seconds=_settings.link_code_ttl_seconds)

@router.post("/link")
async def link_child(
    body: LinkIn,
    request: Request,
    parent: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    allowed, _ = await ratelimit_hit("parent_link", client_ip(request),
                                     20, 3600, fail_closed=True)
    if not allowed:
        raise AppError(429, "Too many attempts",
                       "juda ko'p urinish — bir oz kutib qayta urining")

    redis = get_redis()
    student_id = await redis.get(_link_key(body.code))
    if student_id is None:
        raise AppError(404, "Invalid or expired code")

    if student_id == str(parent.id):
        raise AppError(400, "Cannot link to yourself")

    await redis.delete(_link_key(body.code))  # single-use

    existing = (await db.execute(
        select(Guardianship).where(
            Guardianship.parent_id == parent.id,
            Guardianship.student_id == uuid.UUID(student_id),
        )
    )).scalar_one_or_none()
    if existing is None:
        db.add(Guardianship(parent_id=parent.id,
                            student_id=uuid.UUID(student_id)))
        await db.commit()
    return {"status": "ok", "student_id": student_id}

def signals_for_summary(signals: dict) -> dict:
    """`parent_signals` chiqishidan `ChildSummary` kutadigan maydonlarni
    ajratadi. `correct_7d` sxemada yo'q (aniqlik allaqachon hisoblangan),
    shuning uchun u tashlab yuboriladi — aks holda pydantic xato beradi."""
    return {
        "answered_7d": signals["answered_7d"],
        "accuracy_7d": signals["accuracy_7d"],
        "active_days_7d": signals["active_days_7d"],
        "last_practiced_at": signals["last_practiced_at"],
    }

async def _linked_student(
    db: AsyncSession, parent: User, student_id: uuid.UUID
) -> User:
    link = (await db.execute(
        select(Guardianship).where(
            Guardianship.parent_id == parent.id,
            Guardianship.student_id == student_id,
        )
    )).scalar_one_or_none()
    if link is None:
        raise AppError(403, "Not your child", "no guardianship link for this student")
    student = (await db.execute(
        select(User).where(User.id == student_id)
    )).scalar_one_or_none()
    if student is None:
        raise AppError(404, "Student not found")
    return student

@router.get("/children", response_model=ChildrenOut)
async def list_children(
    parent: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    links = (await db.execute(
        select(Guardianship.student_id).where(Guardianship.parent_id == parent.id)
    )).scalars().all()
    children = []
    for sid in links:
        student = (await db.execute(
            select(User).where(User.id == sid)
        )).scalar_one_or_none()
        if student is None:
            continue
        prog = await progress_service.get_progress(db, sid)
        signals = await progress_service.parent_signals(db, sid)
        children.append(ChildSummary(
            student_id=str(sid), display_name=student.display_name,
            grade=student.grade, region_code=student.region_code,
            avatar_color=student.avatar_color,
            progress=ProgressOut(**prog),
            **signals_for_summary(signals),
        ))
    return ChildrenOut(children=children)

@router.get("/children/{student_id}", response_model=ChildSummary)
async def child_detail(
    student_id: uuid.UUID,
    parent: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    student = await _linked_student(db, parent, student_id)
    prog = await progress_service.get_progress(db, student_id)
    signals = await progress_service.parent_signals(db, student_id)
    return ChildSummary(
        student_id=str(student_id), display_name=student.display_name,
        grade=student.grade, region_code=student.region_code,
        avatar_color=student.avatar_color,
        progress=ProgressOut(**prog),
        **signals_for_summary(signals),
    )

@router.get("/children/{student_id}/analysis")
async def child_analysis(
    student_id: uuid.UUID,
    accept_language: str | None = Header(None),
    parent: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Authz: must be the parent's own linked child. Aggregates + recent quiz list
    # (no individual wrong-answer detail) — the deliberate privacy posture.
    await _linked_student(db, parent, student_id)
    lang = (accept_language or "uz-Latn").split(",")[0].strip()
    return await analysis_service.full_analysis(
        db, student_id, lang, include_recent=True)
