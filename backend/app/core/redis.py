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
