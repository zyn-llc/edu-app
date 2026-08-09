"""
Eskiz.uz SMS provider.

Flow: POST /auth/login (email+password) -> JWT token (≈30-day life) -> use as
Bearer on POST /message/sms/send {mobile_phone, message, from}. On a 401 we log in
again once and retry (covers token expiry without a separate refresh schedule).

The token is cached in-process. With multiple workers each logs in once — fine;
Eskiz tokens are not single-use. If you'd rather share one token across workers,
move the cache to Redis later.

IMPORTANT (ops): Eskiz requires the SMS *text* to match a pre-approved template
(moderation). Until your OTP template is approved, real sends only work to your own
verified number / test sender. Submit the template `otp_message_template` for
approval in the Eskiz cabinet before production.
"""
from __future__ import annotations

import logging

import httpx

from app.services.sms.base import SmsError

_log = logging.getLogger("bilim.sms")


class EskizSmsProvider:
    def __init__(self, base_url: str, email: str, password: str, sender: str):
        self._base = base_url.rstrip("/")
        self._email = email
        self._password = password
        self._sender = sender
        self._token: str | None = None

    async def _login(self, client: httpx.AsyncClient) -> str:
        resp = await client.post(
            f"{self._base}/auth/login",
            data={"email": self._email, "password": self._password},
        )
        if resp.status_code != 200:
            raise SmsError(f"eskiz login failed: {resp.status_code}")
        token = (resp.json().get("data") or {}).get("token")
        if not token:
            raise SmsError("eskiz login returned no token")
        self._token = token
        return token

    async def send(self, phone: str, message: str) -> None:
        # Eskiz wants the number without a leading '+'.
        mobile = phone.lstrip("+")
        async with httpx.AsyncClient(timeout=15) as client:
            if self._token is None:
                await self._login(client)

            async def _do() -> httpx.Response:
                return await client.post(
                    f"{self._base}/message/sms/send",
                    headers={"Authorization": f"Bearer {self._token}"},
                    data={"mobile_phone": mobile, "message": message,
                          "from": self._sender},
                )

            resp = await _do()
            if resp.status_code == 401:          # token expired — re-login once
                await self._login(client)
                resp = await _do()

            if resp.status_code not in (200, 201):
                _log.error("eskiz send failed %s: %s", resp.status_code, resp.text[:200])
                raise SmsError(f"eskiz send failed: {resp.status_code}")
