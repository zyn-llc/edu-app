"""
Async Redis client — one lazily-created connection pool for the whole app.

Used for:
  * OTP storage + rate limiting (this phase)
  * Leaderboard sorted sets (this phase)
  * WebSocket pub/sub backplane (phase 3)

Importing this module does not connect; the pool is created on first use, so unit
tests that never touch Redis don't need a server running.
"""
from __future__ import annotations

from redis.asyncio import Redis, from_url

from app.core.config import get_settings

_settings = get_settings()
_client: Redis | None = None


def get_redis() -> Redis:
    global _client
    if _client is None:
        _client = from_url(_settings.redis_url, decode_responses=True)
    return _client


async def close_redis() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None
