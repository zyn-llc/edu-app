"""
Reusable Redis rate limiting — fixed-window counters.

One helper used by several call sites so limits behave identically everywhere:
  * guest submission flood control        (content.submit)
  * content fetch caps / anti-scraping    (Faza 2.5)

Fixed window (INCR + EXPIRE) instead of a sliding log: one round-trip, O(1)
memory, and at these limits the boundary burst is irrelevant.

Behaviour when Redis is unreachable is a PER-CALL-SITE decision, not a global one:

  * learning paths (questions, submissions) fail OPEN — a Redis blip must never
    stop a student mid-quiz, and the worst case is a few free requests;
  * auth paths (login, register, OTP, invite, Telegram) pass `fail_closed=True`
    — there the limiter is the ONLY thing between a 6-character password and
    unlimited guessing, and between a rotated phone number and a real SMS bill.
    A brief 429 during an outage is cheaper than a breach.
"""
from __future__ import annotations

import logging

from fastapi import Request

from app.core.config import get_settings
from app.core.redis import get_redis

_log = logging.getLogger("bilim.ratelimit")
_settings = get_settings()


def client_ip(request: Request) -> str:
    """Caller IP, honouring X-Forwarded-For only when we sit behind our proxy."""
    if _settings.trust_proxy_headers:
        fwd = request.headers.get("x-forwarded-for")
        if fwd:
            return fwd.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


async def hit(bucket: str, identity: str, limit: int, window_s: int,
              *, fail_closed: bool = False) -> tuple[bool, int]:
    """
    Count one event. Returns (allowed, current_count).

    bucket      — logical name, e.g. "guest_submit"
    identity    — what we're limiting on: ip, user id, nonce, or "user:ip"
    fail_closed — deny instead of allow when Redis is unreachable. See the
                  module docstring: True on every auth/OTP call site.
    """
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