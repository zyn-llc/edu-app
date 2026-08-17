from __future__ import annotations

import logging
import re
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import func, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.v1.invites import normalize_code
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.ratelimit import client_ip, hit as ratelimit_hit
from app.core import names
from app.core.regions import REGION_CODES
from app.core.security import hash_password, verify_password
from app.models import InviteRedemption, RefreshToken, User, UserProgress
from app.schemas.auth import TokenPair
from app.services import auth as auth_service

router = APIRouter(prefix="/v1/auth", tags=["auth"])
_settings = get_settings()
_log = logging.getLogger("bilim.password")

USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,20}$")

RESERVED = {
    "admin", "administrator", "root", "topagon", "support", "help",
    "moderator", "system", "bot", "official", "rasmiy", "api", "me",
    "null", "undefined", "guest", "mehmon",
}

_IP_HOURLY = 40
_NAME_HOURLY = 10

def _norm(raw: str | None) -> str:
    """Bo'sh joylarni kesadi. Katta-kichik harf SAQLANADI — foydalanuvchi
    o'zi yozgan shakl profilda ko'rinadi; solishtirish `lower()` bilan."""
    return (raw or "").strip()

def _validate_username(raw: str) -> str:
    name = _norm(raw)
    if not USERNAME_RE.match(name):
        raise AppError(
            400, "Invalid username",
            "foydalanuvchi nomi 3–20 belgidan iborat bo'lsin: lotin harflari, "
            "raqamlar va pastki chiziq",
            type_="urn:bilim:auth:bad_username")
    if name.lower() in RESERVED:
        raise AppError(409, "Username taken", "bu nom band",
                       type_="urn:bilim:auth:username_taken")
    return name

def _validate_password(raw: str) -> str:
    pw = raw or ""
    if len(pw) < 6:
        raise AppError(400, "Weak password",
                       "parol kamida 6 belgidan iborat bo'lsin",
                       type_="urn:bilim:auth:weak_password")
    if len(pw) > 128:
        raise AppError(400, "Password too long", "parol juda uzun")
    return pw

async def _find_by_username(db: AsyncSession, name: str) -> User | None:
    return (await db.execute(
        select(User).where(func.lower(User.username) == name.lower())
    )).scalar_one_or_none()

async def _guard(request: Request, bucket: str, name: str) -> None:
    """IP + foydalanuvchi nomi bo'yicha ikki qatlamli cheklov."""
    ip = client_ip(request)
    ok_ip, _ = await ratelimit_hit(f"{bucket}_ip", ip, _IP_HOURLY, 3600,
                                   fail_closed=True)
    ok_name, _ = await ratelimit_hit(f"{bucket}_name", name.lower(),
                                     _NAME_HOURLY, 3600, fail_closed=True)
    if not (ok_ip and ok_name):
        raise AppError(429, "Too many attempts",
                       "juda ko'p urinish — bir oz kutib qayta urining")

class RegisterIn(BaseModel):
    username: str = Field(min_length=3, max_length=20)
    password: str = Field(min_length=6, max_length=128)
    display_name: str | None = Field(default=None, max_length=40)
    grade: int | None = Field(default=None, ge=1, le=11)
    region_code: str | None = None
    invite_code: str | None = Field(default=None, min_length=4, max_length=32)
    # baribir bajariladi. Batafsili `sql/030_challenge_as_invite.sql` da.
    join_code: str | None = Field(default=None, min_length=4, max_length=16)
    referred_by: str | None = Field(default=None, max_length=20)

class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=20)
    password: str = Field(min_length=1, max_length=128)

class SetPasswordIn(BaseModel):
    """Mavjud hisobga (Telegram yoki taklif kodi bilan yaratilgan) parol
    qo'shish. `username` faqat hisobda hali nom bo'lmaganda talab qilinadi."""
    username: str | None = Field(default=None, max_length=20)
    password: str = Field(min_length=6, max_length=128)

@router.get("/username-free")
async def username_free(
    username: str = Query(min_length=1, max_length=20),
    db: AsyncSession = Depends(get_db),
):
   
    name = _norm(username)
    if not USERNAME_RE.match(name):
        return {"username": name, "free": False, "reason": "shape"}
    if name.lower() in RESERVED:
        return {"username": name, "free": False, "reason": "reserved"}
    taken = await _find_by_username(db, name) is not None
    return {"username": name, "free": not taken,
            "reason": "taken" if taken else None}

@router.post("/register", response_model=TokenPair)
async def register(
    body: RegisterIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    name = _validate_username(body.username)
    pw = _validate_password(body.password)
    await _guard(request, "pw_register", name)

    if body.region_code is not None and body.region_code not in REGION_CODES:
        raise AppError(400, "Invalid region", "noma'lum hudud kodi")

    if await _find_by_username(db, name) is not None:
        raise AppError(409, "Username taken",
                       "bu nom allaqachon band — boshqasini tanlang",
                       type_="urn:bilim:auth:username_taken")

    invite_row = None
    challenge_row = None
    if _settings.require_invite_for_password_register:
        code = normalize_code(body.invite_code or "")
        join = (body.join_code or "").strip().upper()

        if not code and join:
            challenge_row = (await db.execute(text("""
                UPDATE challenges
                   SET invite_used_at = now()
                 WHERE code = :code
                   AND status = 'open'
                   AND expires_at > now()
                   AND invite_used_at IS NULL
                RETURNING id, grade
            """), {"code": join})).mappings().first()
            if challenge_row is None:
                await db.rollback()
                raise AppError(
                    401, "Invalid challenge link",
                    "bellashuv havolasi eskirgan yoki allaqachon "
                    "ishlatilgan — taklif kodi bilan urinib ko'ring",
                    type_="urn:bilim:auth:invite_required")

        if not code and challenge_row is None:
            raise AppError(400, "Invite code required",
                           "ro'yxatdan o'tish uchun taklif kodi kerak",
                           type_="urn:bilim:auth:invite_required")
       
        if code:
            invite_row = (await db.execute(text("""
                UPDATE invite_codes
                   SET used_count = used_count + 1
                 WHERE code = :code
                   AND is_active
                   AND used_count < max_uses
                   AND (expires_at IS NULL OR expires_at > now())
                RETURNING code, grade, region_code
            """), {"code": code})).mappings().first()
            if invite_row is None:
                await db.rollback()
                raise AppError(401, "Invalid code",
                               "kod noto'g'ri, ishlatilib bo'lingan yoki "
                               "muddati o'tgan",
                               type_="urn:bilim:auth:invite_required")

    referred_by = await auth_service.resolve_referrer(db, body.referred_by, name)

    user = User(
        phone=None,
        role="student",
        username=name,
        password_hash=hash_password(pw),
        display_name=(names.safe_name(body.display_name) or name),
        grade=body.grade if body.grade is not None
              else (invite_row["grade"] if invite_row
                    else (challenge_row["grade"] if challenge_row else None)),
        region_code=body.region_code or
                    (invite_row["region_code"] if invite_row else None),
        referred_by=referred_by,
        locale=_settings.default_lang,
    )
    db.add(user)
    try:
        await db.flush()
    except Exception:
        # ishlata oladi.
        await db.rollback()
        raise AppError(409, "Username taken", "bu nom allaqachon band",
                       type_="urn:bilim:auth:username_taken")

    db.add(UserProgress(user_id=user.id))
    if invite_row is not None:
        db.add(InviteRedemption(code=invite_row["code"], user_id=user.id))
    await db.flush()
    pair = await auth_service.issue_token_pair(db, user)
    await db.commit()
    _log.info("password register: user=%s invite=%s challenge=%s", user.id,
              invite_row["code"] if invite_row else None,
              challenge_row["id"] if challenge_row else None)
    return pair

@router.post("/login", response_model=TokenPair)
async def login(
    body: LoginIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    name = _norm(body.username)
    await _guard(request, "pw_login", name)

    user = await _find_by_username(db, name) if name else None

    stored = user.password_hash if (user and user.password_hash) else None
    if stored:
        ok = verify_password(body.password, stored)
    else:
        hash_password(body.password)
        ok = False

    if not ok or user is None or not user.is_active:
        raise AppError(401, "Invalid credentials",
                       "foydalanuvchi nomi yoki parol noto'g'ri",
                       type_="urn:bilim:auth:bad_credentials")

    pair = await auth_service.issue_token_pair(db, user)
    await db.commit()
    return pair

@router.post("/password")
async def set_password(
    body: SetPasswordIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Kirgan foydalanuvchi o'ziga parol o'rnatadi yoki almashtiradi.

    Telegram bilan kirgan o'quvchi shu yerda nom+parol qo'yadi va keyingi
    safar Telegram'siz kira oladi. Teskarisi ham to'g'ri: parol bilan
    ro'yxatdan o'tgan o'quvchi Telegram'ni ulab, uni tiklash yo'li sifatida
    ishlatadi.

    Eski parolni so'ramaymiz, chunki bu yerga faqat amaldagi access token
    bilan kirib bo'ladi — ya'ni sessiya allaqachon isbotlangan.
    """
    pw = _validate_password(body.password)

    if not user.username:
        if not body.username:
            raise AppError(400, "Username required",
                           "avval foydalanuvchi nomini tanlang",
                           type_="urn:bilim:auth:username_required")
        name = _validate_username(body.username)
        existing = await _find_by_username(db, name)
        if existing is not None and existing.id != user.id:
            raise AppError(409, "Username taken", "bu nom allaqachon band",
                           type_="urn:bilim:auth:username_taken")
        user.username = name
    elif body.username and body.username.strip().lower() != user.username.lower():
        raise AppError(409, "Username locked",
                       "foydalanuvchi nomini o'zgartirib bo'lmaydi",
                       type_="urn:bilim:auth:username_locked")

    user.password_hash = hash_password(pw)

    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id,
               RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(timezone.utc))
    )
    pair = await auth_service.issue_token_pair(db, user)
    await db.commit()
    return {"ok": True, "username": user.username, **pair.model_dump()}
