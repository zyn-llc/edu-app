from __future__ import annotations

import hmac
import logging
import uuid

from fastapi import Depends, Header, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.ratelimit import client_ip, hit as ratelimit_hit
from app.core.security import TokenError, decode_access_token
from app.models import User

_log = logging.getLogger("bilim.deps")
_settings = get_settings()


def _bearer(authorization: str | None) -> str | None:
    if not authorization:
        return None
    parts = authorization.split(" ", 1)
    if len(parts) != 2 or parts[0].lower() != "bearer":
        return None
    return parts[1].strip()


async def get_current_claims(authorization: str | None = Header(None)) -> dict:
    token = _bearer(authorization)
    if token is None:
        raise AppError(401, "Not authenticated")
    try:
        return decode_access_token(token)
    except TokenError as e:
        raise AppError(401, "Invalid token", str(e))


async def get_current_claims_optional(
    authorization: str | None = Header(None),
) -> dict | None:
    token = _bearer(authorization)
    if token is None:
        return None
    try:
        return decode_access_token(token)
    except TokenError:
        return None


async def get_current_user(
    claims: dict = Depends(get_current_claims),
    db: AsyncSession = Depends(get_db),
) -> User:
    user = (await db.execute(
        select(User).where(User.id == uuid.UUID(claims["sub"]))
    )).scalar_one_or_none()
    if user is None or not user.is_active:
        raise AppError(401, "User not found or inactive")
    return user


async def get_current_user_optional(
    claims: dict | None = Depends(get_current_claims_optional),
    db: AsyncSession = Depends(get_db),
) -> User | None:
    if claims is None:
        return None
    return (await db.execute(
        select(User).where(User.id == uuid.UUID(claims["sub"]))
    )).scalar_one_or_none()


def require_role(*roles: str):
    async def _dep(user: User = Depends(get_current_user)) -> User:
        if user.role not in roles:
            raise AppError(403, "Forbidden", f"requires role: {', '.join(roles)}")
        return user
    return _dep


_ADMIN_TRIES_PER_HOUR = 20


async def require_admin(
    request: Request,
    x_admin_key: str | None = Header(None),
) -> None:
    
    if not _settings.admin_api_key:
        raise AppError(404, "Not Found")

    ip = client_ip(request)
    allowed, n = await ratelimit_hit("admin_key", ip, _ADMIN_TRIES_PER_HOUR,
                                     3600, fail_closed=True)
    if not allowed:
        _log.warning("admin key rate limit hit ip=%s count=%s", ip, n)
        raise AppError(404, "Not Found")

    if not hmac.compare_digest(x_admin_key or "", _settings.admin_api_key):
        _log.warning("admin key mismatch ip=%s", ip)
        raise AppError(404, "Not Found")
