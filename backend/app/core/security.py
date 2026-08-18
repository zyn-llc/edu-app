from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from app.core.config import get_settings

_settings = get_settings()
_ph = PasswordHasher()

ALGO = "HS256"


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _ph.verify(password_hash, password)
    except VerifyMismatchError:
        return False



def create_access_token(
    user_id: str | uuid.UUID,
    role: str,
    now: datetime | None = None,
) -> str:
    now = now or datetime.now(timezone.utc)
    payload: dict[str, Any] = {
        "sub": str(user_id),
        "role": role,
        "type": "access",
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=_settings.jwt_access_ttl_seconds)).timestamp()),
    }
    return jwt.encode(payload, _settings.jwt_secret, algorithm=ALGO)


class TokenError(Exception):
    """Invalid / expired / wrong-type token."""


def decode_access_token(token: str) -> dict[str, Any]:
    try:
        claims = jwt.decode(token, _settings.jwt_secret, algorithms=[ALGO])
    except jwt.ExpiredSignatureError as e:
        raise TokenError("token expired") from e
    except jwt.PyJWTError as e:
        raise TokenError("invalid token") from e
    if claims.get("type") != "access":
        raise TokenError("wrong token type")
    return claims



def new_refresh_token() -> str:
    """A high-entropy opaque string handed to the client. Never persisted raw."""
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    """SHA-256 hex. Used for refresh tokens and OTP codes stored in Redis.

    SHA-256 (not argon2) is correct here: the inputs are already high-entropy
    (refresh) or short-lived + rate-limited + single-use (OTP), so the slow-hash
    protection argon2 buys for human passwords does not apply, and we want O(1)
    lookups.
    """
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def refresh_expiry(now: datetime | None = None) -> datetime:
    now = now or datetime.now(timezone.utc)
    return now + timedelta(seconds=_settings.jwt_refresh_ttl_seconds)
