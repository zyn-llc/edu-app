"""
/v1/feedback — in-app support/feedback channel.

Submitting works for guests too (a user whose LOGIN is broken is exactly who
must be able to reach you), so this endpoint is abuse-hardened instead of
auth-gated: per-IP Redis caps + message length limit. Messages land in the
feedback table; read them via GET /v1/admin/feedback (X-Admin-Key) or straight
in psql. Contact field is whatever the user typed (phone/telegram) — never
auto-filled, their choice to share.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user_optional, get_db, require_admin
from app.core.config import get_settings
from app.core.errors import AppError
from app.core.ratelimit import client_ip
from app.core.redis import get_redis
from app.models import Feedback, User
from app.services import telegram

router = APIRouter(prefix="/v1", tags=["feedback"])
_settings = get_settings()

_MAX_LEN = 2000
_PER_IP_PER_DAY = 10

class FeedbackIn(BaseModel):
    message: str = Field(min_length=3, max_length=_MAX_LEN)
    contact: str | None = Field(None, max_length=128)
    app_version: str | None = Field(None, max_length=32)

@router.post("/feedback", status_code=201)
async def submit_feedback(
    body: FeedbackIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: User | None = Depends(get_current_user_optional),
):
    redis = get_redis()
    # uning qo'lda yozilgan nusxasi turardi: `TRUST_PROXY_HEADERS` mantig'i
    ip = client_ip(request)
    key = f"fb:{ip}"
    n = await redis.incr(key)
    if n == 1:
        await redis.expire(key, 24 * 3600)
    if n > _PER_IP_PER_DAY:
        raise AppError(429, "Too many messages", "try again tomorrow")

    db.add(Feedback(
        user_id=user.id if user else None,
        message=body.message.strip(),
        contact=(body.contact or "").strip() or None,
        app_version=body.app_version,
    ))
    await db.commit()

    await telegram.notify_admin(
        "Ilovadan murojaat\n"
        f"Foydalanuvchi: {user.display_name or user.id if user else 'mehmon'}\n"
        f"Aloqa: {(body.contact or '').strip() or 'ko`rsatilmagan'}\n"
        f"Versiya: {body.app_version or '?'}\n\n"
        f"{body.message.strip()[:1500]}"
    )
    return {"ok": True}

@router.get("/admin/feedback", dependencies=[Depends(require_admin)])
async def list_feedback(
    status: str = "new",
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
):
    stmt = select(Feedback).order_by(Feedback.created_at.desc()).limit(min(limit, 200))
    if status in ("new", "seen"):
        stmt = stmt.where(Feedback.status == status)
    rows = (await db.execute(stmt)).scalars().all()
    return {"items": [{
        "id": str(f.id),
        "user_id": str(f.user_id) if f.user_id else None,
        "message": f.message,
        "contact": f.contact,
        "app_version": f.app_version,
        "status": f.status,
        "created_at": f.created_at.isoformat(),
    } for f in rows]}

@router.post("/admin/feedback/{feedback_id}/seen",
             dependencies=[Depends(require_admin)])
async def mark_seen(feedback_id: str, db: AsyncSession = Depends(get_db)):
    f = (await db.execute(
        select(Feedback).where(Feedback.id == feedback_id))).scalar_one_or_none()
    if f is None:
        raise AppError(404, "Not found")
    f.status = "seen"
    await db.commit()
    return {"ok": True}
