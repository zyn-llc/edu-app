"""Provider selection from config. Cached: one provider instance per process."""
from __future__ import annotations

from functools import lru_cache

from app.core.config import get_settings
from app.services.sms.base import SmsError, SmsProvider
from app.services.sms.console import ConsoleSmsProvider
from app.services.sms.eskiz import EskizSmsProvider

__all__ = ["SmsError", "SmsProvider", "get_sms_provider", "render_otp_message"]


@lru_cache
def get_sms_provider() -> SmsProvider:
    s = get_settings()
    if s.sms_provider == "eskiz":
        if not (s.eskiz_email and s.eskiz_password):
            raise SmsError("eskiz selected but ESKIZ_EMAIL/PASSWORD not set")
        return EskizSmsProvider(
            base_url=s.eskiz_base_url,
            email=s.eskiz_email,
            password=s.eskiz_password,
            sender=s.eskiz_from,
        )
    return ConsoleSmsProvider()


def render_otp_message(code: str) -> str:
    return get_settings().otp_message_template.format(code=code)
