from __future__ import annotations

from typing import Protocol


class SmsError(Exception):
    
class SmsProvider(Protocol):
    async def send(self, phone: str, message: str) -> None:
    
