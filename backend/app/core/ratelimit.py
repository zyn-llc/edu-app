from __future__ import annotations

import logging

from fastapi import Request

from app.core.config import get_settings
from app.core.redis import get_redis

_log = logging.getLogger("bilim.ratelimit")
_settings = get_settings()


def client_ip(request: Request) -> str:
    if _settings.trust_proxy_headers:
        fwd = request.headers.get("x-forwarded-for")
        if fwd:
            return fwd.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


async def hit(bucket: str, identity: str, limit: int, window_s: int,
              *, fail_closed: bool = False) -> tuple[bool, int]:
  
    key = f"rl:{bucket}:{identity}"
    try:
        redis = get_redis()
        n = await redis.incr(key)
        if n == 1:
            await redis.expire(key, window_s)
        return (n <= limit), n
    except Exception as e:                       # Redis down / network blip
        _log.warning("ratelimit unavailable (%s) — %s: %s", bucket,
                     "denying" if fail_closed else "allowing", e)
        return (not fail_closed), 0
