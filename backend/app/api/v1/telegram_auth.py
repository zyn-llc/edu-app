from __future__ import annotations

import hmac
import logging
import uuid as uuidlib

from fastapi import APIRouter, Depends, Header, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.ratelimit import client_ip, hit as ratelimit_hit
from app.core.redis import get_redis
from app.models import User
from app.schemas.auth import TokenPair
from app.services import auth as auth_service
from app.services import telegram as tg

router = APIRouter(tags=["auth"])
_settings = get_settings()
_log = logging.getLogger("bilim.telegram")

def _require_enabled() -> None:
    if not _settings.telegram_login_enabled:
        raise AppError(404, "Not Found")

class StartOut(BaseModel):
    nonce: str
    deep_link: str
    expires_in_seconds: int
    confirm_code: str

class PollIn(BaseModel):
    nonce: str = Field(min_length=8, max_length=128)

@router.post("/v1/auth/telegram/start", response_model=StartOut)
async def telegram_start(request: Request):
    _require_enabled()
    ip = client_ip(request)
    #
    #
    # nonce alohida Redis kaliti va 10 daqiqada o'chadi.
    allowed, _ = await ratelimit_hit("tg_start", ip, 120, 3600,
                                     fail_closed=True)
    if not allowed:
        raise AppError(429, "Too many attempts")

    nonce = tg.new_nonce()
    code = tg.new_confirm_code()
    ttl = _settings.telegram_login_ttl_seconds
    await get_redis().set(tg.nonce_key(nonce), tg.pending_value(code), ex=ttl)
    return StartOut(nonce=nonce, deep_link=tg.deep_link(nonce),
                    expires_in_seconds=ttl, confirm_code=code)

@router.post("/v1/auth/telegram/poll")
async def telegram_poll(
    body: PollIn,
    db: AsyncSession = Depends(get_db),
):
    _require_enabled()
    allowed, _ = await ratelimit_hit("tg_poll", body.nonce, 400, 3600)
    if not allowed:
        raise AppError(429, "Too many attempts")

    redis = get_redis()
    key = tg.nonce_key(body.nonce)
    value = await redis.get(key)

    if value is None:
        raise AppError(410, "Expired", "havola muddati tugagan, qaytadan boshlang")
    if tg.pending_code(value) is not None:
        return {"status": "pending"}

    try:
        user_id = uuidlib.UUID(value)
    except ValueError:
        await redis.delete(key)
        raise AppError(410, "Expired")

    user = (await db.execute(
        select(User).where(User.id == user_id)
    )).scalar_one_or_none()
    if user is None:
        await redis.delete(key)
        raise AppError(410, "Expired")

    await redis.delete(key)
    pair = await auth_service.issue_token_pair(db, user)
    await db.commit()
    return {
        "status": "ok",
        "access_token": pair.access_token,
        "refresh_token": pair.refresh_token,
        "expires_in": pair.expires_in,
    }

@router.post("/v1/telegram/webhook", include_in_schema=False)
async def telegram_webhook(
    request: Request,
    x_telegram_bot_api_secret_token: str | None = Header(None),
    db: AsyncSession = Depends(get_db),
):
    if not _settings.telegram_login_enabled:
        raise AppError(404, "Not Found")
    if (not _settings.telegram_webhook_secret
            or not hmac.compare_digest(x_telegram_bot_api_secret_token or "",
                                       _settings.telegram_webhook_secret)):
        raise AppError(404, "Not Found")

    try:
        update = await request.json()
    except Exception:
        return {"ok": True}

    try:
        await tg.handle_update(db, update)
    except Exception:
        await db.rollback()
        _log.exception("telegram update failed")
    return {"ok": True}

__all__ = ["router", "TokenPair"]
