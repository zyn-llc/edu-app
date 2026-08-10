"""
POST /v1/auth/invite — taklif kodi bilan telefonsiz kirish.

Nega bor: SMS shlyuzi (Eskiz) moderatsiyada turganda ham yopiq beta ishlashi
kerak. Kod kiritilganda telefonsiz akkaunt yaratiladi va odatdagi token juftligi
qaytariladi — undan keyin ilova uchun bu oddiy foydalanuvchi, hech qanday farq
yo'q. Eskiz kelganda bu yo'l o'chirilmaydi ham: kod bilan kirgan o'quvchi keyin
profilida telefon qo'shishi mumkin.

Xavfsizlik:
  * Kod 8 belgi, chalkash harflarsiz -> ~1.1 trln kombinatsiya. Bir IP'dan
    soatiga INVITE_IP_HOURLY_CAP urinish (standart 10) — brute-force amalda
    imkonsiz.
  * used_count atomik oshiriladi (UPDATE ... WHERE used_count < max_uses
    RETURNING). Ikki kishi bir vaqtda bitta oxirgi joyni olsa, faqat bittasi
    yutadi — race yo'q, LOCK ham kerak emas.
  * Kod javobda hech qachon qaytmaydi.
"""
from __future__ import annotations

import logging
import re

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.ratelimit import client_ip, hit as ratelimit_hit
from app.core import names
from app.core.regions import REGION_CODES
from app.models import InviteRedemption, User, UserProgress
from app.schemas.auth import TokenPair
from app.services import auth as auth_service

router = APIRouter(prefix="/v1/auth", tags=["auth"])
_settings = get_settings()
_log = logging.getLogger("bilim.invite")

_NON_ALNUM = re.compile(r"[^A-Z0-9]")

def normalize_code(raw: str) -> str:
    """'k7m4-x9qp' / 'K7M4 X9QP' -> 'K7M4X9QP'. Foydalanuvchi chiziqcha,
    bo'sh joy yoki kichik harf yozsa ham ishlashi kerak."""
    return _NON_ALNUM.sub("", (raw or "").upper())

class InviteIn(BaseModel):
    code: str = Field(min_length=4, max_length=32)
    display_name: str | None = Field(default=None, max_length=40)
    grade: int | None = Field(default=None, ge=1, le=11)
    region_code: str | None = None
    referred_by: str | None = Field(default=None, max_length=20)

@router.post("/invite", response_model=TokenPair)
async def redeem_invite(
    body: InviteIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    if not _settings.invite_login_enabled:
        raise AppError(404, "Not Found")

    ip = client_ip(request)
    allowed, _ = await ratelimit_hit(
        "invite_redeem", ip, _settings.invite_ip_hourly_cap, 3600,
        fail_closed=True)
    if not allowed:
        raise AppError(429, "Too many attempts",
                       "juda ko'p urinish, bir soatdan keyin qayta urinib ko'ring")

    code = normalize_code(body.code)
    if not code:
        raise AppError(400, "Invalid code")

    if body.region_code is not None and body.region_code not in REGION_CODES:
        raise AppError(400, "Invalid region", "unknown region_code")

    row = (await db.execute(text("""
        UPDATE invite_codes
           SET used_count = used_count + 1
         WHERE code = :code
           AND is_active
           AND used_count < max_uses
           AND (expires_at IS NULL OR expires_at > now())
        RETURNING code, grade, region_code
    """), {"code": code})).mappings().first()

    if row is None:
        await db.rollback()
        raise AppError(401, "Invalid code",
                       "kod noto'g'ri, ishlatilib bo'lingan yoki muddati o'tgan")

    name = names.safe_name(body.display_name) or None
    referred_by = await auth_service.resolve_referrer(db, body.referred_by)
    user = User(
        phone=None,
        role="student",
        display_name=name,
        grade=body.grade if body.grade is not None else row["grade"],
        region_code=body.region_code or row["region_code"],
        referred_by=referred_by,
        locale=_settings.default_lang,
    )
    db.add(user)
    await db.flush()
    db.add(UserProgress(user_id=user.id))
    db.add(InviteRedemption(code=row["code"], user_id=user.id))
    await db.flush()

    pair = await auth_service.issue_token_pair(db, user)
    await db.commit()
    _log.info("invite redeemed: code=%s user=%s", row["code"], user.id)
    return pair
