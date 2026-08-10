"""Auth DTOs. Phone numbers are normalized to E.164 (+998XXXXXXXXX) on the way in
so the unique constraint on users.phone always sees one canonical form."""
from __future__ import annotations

import re

from pydantic import BaseModel, Field, field_validator

_DIGITS = re.compile(r"\d+")

def normalize_uz_phone(raw: str) -> str:
    """Accept the messy ways a user might type an Uzbek number and return E.164.

    Accepts: '+998 90 123 45 67', '998901234567', '901234567', '0901234567'.
    Returns: '+998901234567'. Raises ValueError if it can't be made into a valid
    9-digit national number.
    """
    digits = "".join(_DIGITS.findall(raw or ""))
    if digits.startswith("998"):
        digits = digits[3:]
    elif digits.startswith("0"):
        digits = digits[1:]
    if len(digits) != 9:
        raise ValueError("phone must be a 9-digit Uzbek number (optionally +998)")
    return "+998" + digits

class PhoneIn(BaseModel):
    phone: str

    @field_validator("phone")
    @classmethod
    def _norm(cls, v: str) -> str:
        return normalize_uz_phone(v)

class OtpRequestIn(PhoneIn):
    # 'student' (default) or 'parent'. Admins are provisioned, not self-registered.
    role: str = "student"

    @field_validator("role")
    @classmethod
    def _role(cls, v: str) -> str:
        if v not in ("student", "parent"):
            raise ValueError("role must be student or parent")
        return v

class OtpRequestOut(BaseModel):
    # seconds until another code can be requested for this phone
    retry_after_seconds: int
    expires_in_seconds: int
    # populated only when settings.otp_debug_return is true (dev). None in prod.
    debug_code: str | None = None

class OtpVerifyIn(PhoneIn):
    code: str = Field(min_length=4, max_length=8)
    # optional profile bootstrap on first verify
    display_name: str | None = None
    region_code: str | None = None
    grade: int | None = None

class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int            # access-token lifetime (seconds)

class RefreshIn(BaseModel):
    refresh_token: str

class UserOut(BaseModel):
    id: str
    role: str
    phone: str | None = None
    username: str | None = None
    display_name: str | None = None
    region_code: str | None = None
    grade: int | None = None
    locale: str | None = None
    avatar_color: int | None = None
    tg_notifications: bool | None = None

class ProfileUpdateIn(BaseModel):
    display_name: str | None = None
    region_code: str | None = None
    grade: int | None = None
    locale: str | None = None
    avatar_color: int | None = None
    tg_notifications: bool | None = None
