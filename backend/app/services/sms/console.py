"""Dev SMS provider — logs instead of sending. Pairs with otp_debug_return=true so
the code is also returned in the API response. Never used in prod (the config guard
rejects it)."""
from __future__ import annotations

import logging

_log = logging.getLogger("bilim.sms")


class ConsoleSmsProvider:
    async def send(self, phone: str, message: str) -> None:
        _log.info("[console-sms] to=%s | %s", phone, message)
