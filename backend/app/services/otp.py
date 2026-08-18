from __future__ import annotations

import secrets

from redis.asyncio import Redis

from app.core.config import get_settings
from app.core.security import hash_token

_settings = get_settings()


def _gen_code(length: int) -> str:
    # numeric, zero-padded, cryptographically random
    upper = 10 ** length
    return str(secrets.randbelow(upper)).zfill(length)


class OtpError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code          
        self.message = message
        super().__init__(message)


def _k(kind: str, phone: str) -> str:
    return f"otp:{kind}:{phone}"


async def issue(redis: Redis, phone: str, role: str = "student") -> tuple[str, int]:
  
    cooldown_key = _k("cooldown", phone)
    ttl = await redis.ttl(cooldown_key)
    if ttl and ttl > 0:
        raise OtpError("cooldown", f"try again in {ttl}s")

    daily_key = _k("daily", phone)
    count = await redis.incr(daily_key)
    if count == 1:
        await redis.expire(daily_key, 24 * 3600)
    if count > _settings.otp_request_daily_cap:
        raise OtpError("daily_cap", "too many codes requested today")

    code = _gen_code(_settings.otp_length)
    await redis.set(_k("code", phone), hash_token(code), ex=_settings.otp_ttl_seconds)
    await redis.set(_k("role", phone), role, ex=_settings.otp_ttl_seconds)
    await redis.delete(_k("attempts", phone))
    await redis.set(cooldown_key, "1", ex=_settings.otp_request_cooldown_seconds)
    return code, _settings.otp_ttl_seconds


async def pop_role(redis: Redis, phone: str, default: str = "student") -> str:
    role = await redis.get(_k("role", phone))
    await redis.delete(_k("role", phone))
    return role or default


async def verify(redis: Redis, phone: str, code: str) -> bool:
    is hit (single-use). Returns True iff correct."""
    code_key = _k("code", phone)
    stored = await redis.get(code_key)
    if stored is None:
        return False  

    if hash_token(code) == stored:
        await redis.delete(code_key, _k("attempts", phone))
        return True

    attempts = await redis.incr(_k("attempts", phone))

    await redis.expire(_k("attempts", phone), _settings.otp_ttl_seconds)
    if attempts >= _settings.otp_max_attempts:
        await redis.delete(code_key, _k("attempts", phone))  
    return False
