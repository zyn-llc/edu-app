"""
Auth service — turns a verified phone into a user + a token pair, and rotates
refresh tokens.

Refresh rotation is the security-critical bit: on every refresh we (1) look up the
presented token by its hash, (2) reject it if missing / revoked / expired, (3)
revoke that exact row, and (4) issue a brand-new refresh token. So a refresh token
is good for exactly one use; replaying a stolen one fails because the legitimate
client already rotated it (or, if the attacker rotates first, the legitimate
client's next refresh fails and the theft surfaces).
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import names, security
from app.core.config import get_settings
from app.models import RefreshToken, User, UserProgress
from app.schemas.auth import TokenPair

_settings = get_settings()

async def resolve_referrer(db: AsyncSession, raw: str | None,
                           new_username: str | None = None) -> str | None:
    """`?ref=<username>` orqali kelgan taklif havolasi — kim taklif qilgan.

    NEGA ALOHIDA FUNKSIYA, `password_auth.py` YOKI `invites.py` ICHIDA
    EMAS. Ikkalasi ham yangi hisob yaratadi va ikkalasiga ham referral
    kerak, lekin `password_auth.py` allaqachon `invites.py` dan import
    qiladi (`normalize_code`) — agar bu funksiya o'sha ikkitadan birida
    tursa, ikkinchisi uni import qilishga uringanda AYLANMA IMPORT
    (circular import) hosil bo'lardi. `services/` neytral qatlam.

    Topilmasa yoki o'z-o'ziga taklif bo'lsa `None` qaytaradi — ro'yxatdan
    o'tishni HECH QACHON to'xtatmaydi, chunki bu shunchaki statistika,
    invite_code kabi majburiy to'siq emas.
    """
    name = (raw or "").strip()
    if not name or len(name) > 20:
        return None
    if new_username and name.lower() == new_username.lower():
        return None
    row = (await db.execute(
        select(User.username).where(func.lower(User.username) == name.lower())
    )).scalar_one_or_none()
    return row

async def get_or_create_user(
    db: AsyncSession,
    phone: str,
    role: str,
    *,
    display_name: str | None = None,
    region_code: str | None = None,
    grade: int | None = None,
) -> User:
    # kirishni bloklamaydi, shunchaki olinmaydi.
    display_name = names.safe_name(display_name) or None

    user = (await db.execute(
        select(User).where(User.phone == phone)
    )).scalar_one_or_none()
    if user is None:
        user = User(
            phone=phone,
            role=role,
            display_name=display_name,
            region_code=region_code,
            grade=grade,
            locale=_settings.default_lang,
        )
        db.add(user)
        await db.flush()
        # every student gets a progress row up front so reads never special-case null
        if role == "student":
            db.add(UserProgress(user_id=user.id))
        await db.flush()
    else:
        # fill blanks on subsequent logins, but never silently change role
        if display_name and not user.display_name:
            user.display_name = display_name
        if region_code and not user.region_code:
            user.region_code = region_code
        if grade is not None and user.grade is None:
            user.grade = grade
    return user

async def issue_token_pair(db: AsyncSession, user: User) -> TokenPair:
    access = security.create_access_token(user.id, user.role)
    raw_refresh = security.new_refresh_token()
    db.add(RefreshToken(
        user_id=user.id,
        token_hash=security.hash_token(raw_refresh),
        expires_at=security.refresh_expiry(),
    ))
    await db.flush()
    return TokenPair(
        access_token=access,
        refresh_token=raw_refresh,
        expires_in=_settings.jwt_access_ttl_seconds,
    )

class AuthError(Exception):
    pass

async def rotate_refresh_token(db: AsyncSession, raw_refresh: str) -> TokenPair:
    token_hash = security.hash_token(raw_refresh)
    row = (await db.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    )).scalar_one_or_none()

    now = datetime.now(timezone.utc)
    if row is None or row.revoked_at is not None or row.expires_at <= now:
        raise AuthError("invalid or expired refresh token")

    user = (await db.execute(
        select(User).where(User.id == row.user_id)
    )).scalar_one_or_none()
    if user is None or not user.is_active:
        raise AuthError("user not found or inactive")

    row.revoked_at = now                       # one-time use
    pair = await issue_token_pair(db, user)
    return pair

async def revoke_refresh_token(db: AsyncSession, raw_refresh: str) -> None:
    """Logout: best-effort revoke. A token that isn't found is already gone."""
    token_hash = security.hash_token(raw_refresh)
    row = (await db.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    )).scalar_one_or_none()
    if row is not None and row.revoked_at is None:
        row.revoked_at = datetime.now(timezone.utc)
