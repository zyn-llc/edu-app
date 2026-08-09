"""
Anti-scraping / content-exfiltration controls.

The question bank (~14k items) is the product's core asset. It is never shipped
to the client wholesale — it is served question-by-question — so the realistic
attack is not decompiling the APK, it is an authenticated client walking the
/v1/questions endpoint until it has the whole bank.

Two layers here, and they do different jobs:

  1. RATE  — a hard per-minute cap on questions served. Stops bursts.
  2. VOLUME — distinct questions seen per rolling hour. A patient scraper stays
     under any per-minute cap, so the cap alone is not protection; what gives a
     scraper away is *breadth* — a real student revisits a narrow set, a scraper
     never repeats. This is the layer that actually detects harvesting.

Distinct counting uses Redis HyperLogLog (PFADD/PFCOUNT): ~0.8% error, and for
the few-hundred cardinalities we care about it stays in sparse encoding, so it
costs a few hundred bytes per active user instead of a real set's tens of KB.

Guest access is additionally narrowed to a deterministic sample of the bank
(see guest_pool_clause) so an anonymous caller cannot reach most of the content
at all, regardless of rate.

Redis failure NEVER blocks a learner: every check fails open and logs.
"""
from __future__ import annotations

import logging
import time

from sqlalchemy import String, cast, func

from app.core.redis import get_redis

_log = logging.getLogger("bilim.antiabuse")

# --- tunables ---------------------------------------------------------------
QUESTIONS_PER_MINUTE = 30      # hard burst cap (per identity)
DISTINCT_PER_HOUR_WARN = 600   # log + flag above this
DISTINCT_PER_HOUR_BLOCK = 900  # refuse above this
# Guests only ever see questions whose id-hash starts with one of these hex
# chars: a deterministic, evenly-spread slice of every subject and grade.
#
# 1/16 (~1 080 of 17k) was too tight in practice: inside one narrow topic a
# guest ran into the same questions within a single session and concluded the
# bank was thin — the opposite of the first impression the content is supposed
# to give. 3/16 (~3 200) still keeps most of the asset behind signup.
GUEST_POOL_PREFIXES = ("0", "7", "b")


def guest_pool_clause():
    """SQLAlchemy predicate limiting guests to a fixed sample of the bank.

    Hash-based rather than 'first N rows': it is stable across requests (a guest
    sees a consistent app, not a shifting one), spreads evenly over every
    subject/grade/topic without per-subject bookkeeping, and cannot be walked by
    changing paging parameters.
    """
    from app.models import Question
    return func.substr(func.md5(cast(Question.id, String)), 1, 1).in_(
        GUEST_POOL_PREFIXES)


async def check_rate(identity: str) -> tuple[bool, int]:
    """Per-minute questions-served cap. Returns (allowed, count_this_minute)."""
    window = int(time.time() // 60)
    key = f"ab:qrate:{identity}:{window}"
    try:
        redis = get_redis()
        n = await redis.incr(key)
        if n == 1:
            await redis.expire(key, 120)
        return n <= QUESTIONS_PER_MINUTE, n
    except Exception as e:
        _log.warning("antiabuse rate check unavailable — allowing: %s", e)
        return True, 0


async def track_distinct(identity: str, question_ids: list[str]) -> int:
    """Record which questions this identity has seen this hour; return distinct total.

    Rolling by clock hour. A student who legitimately grinds across an hour
    boundary just starts a fresh window — we would rather miss a slow scraper
    than lock out a keen learner.
    """
    if not question_ids:
        return 0
    window = int(time.time() // 3600)
    key = f"ab:qseen:{identity}:{window}"
    try:
        redis = get_redis()
        await redis.pfadd(key, *question_ids)
        await redis.expire(key, 7200)
        return int(await redis.pfcount(key))
    except Exception as e:
        _log.warning("antiabuse distinct tracking unavailable: %s", e)
        return 0


async def enforce(identity: str, is_guest: bool) -> None:
    """Raise 429 if this identity is over the burst cap. Call BEFORE querying."""
    from app.core.errors import AppError
    allowed, n = await check_rate(identity)
    if not allowed:
        _log.warning("question rate cap hit identity=%s count=%s guest=%s",
                     identity, n, is_guest)
        raise AppError(429, "Too many requests", "please slow down")


async def observe(identity: str, question_ids: list[str], is_guest: bool) -> None:
    """Record breadth AFTER serving; refuse further harvesting past the block line."""
    from app.core.errors import AppError
    distinct = await track_distinct(identity, question_ids)
    if distinct >= DISTINCT_PER_HOUR_BLOCK:
        _log.error("SCRAPE BLOCK identity=%s distinct_this_hour=%s guest=%s",
                   identity, distinct, is_guest)
        raise AppError(429, "Unusual activity detected",
                       "too many different questions in a short period")
    if distinct >= DISTINCT_PER_HOUR_WARN:
        _log.warning("scrape watch identity=%s distinct_this_hour=%s guest=%s",
                     identity, distinct, is_guest)
