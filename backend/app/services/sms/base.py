"""
SMS provider abstraction.

Auth (and any future notification) sends go through `SmsProvider.send`, so the rest
of the app never knows or cares which gateway is behind it. Swapping Eskiz for Play
Mobile (or adding a fallback) is a new implementation + a config flag, nothing else.
"""
from __future__ import annotations

from typing import Protocol


class SmsError(Exception):
    """Delivery failed (auth, network, gateway rejection)."""


class SmsProvider(Protocol):
    async def send(self, phone: str, message: str) -> None:
        """Send `message` to E.164 `phone`. Raises SmsError on failure."""
        ...
