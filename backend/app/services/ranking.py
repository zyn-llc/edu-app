from __future__ import annotations

from redis.asyncio import Redis

TOTAL_KEY = "lb:total"


def subject_key(subject_code: str) -> str:
    return f"lb:subject:{subject_code}"


def region_key(region_code: str) -> str:
    return f"lb:region:{region_code}"


def _board_key(scope: str, key: str | None) -> str:
    if scope == "total":
        return TOTAL_KEY
    if scope == "subject" and key:
        return subject_key(key)
    if scope == "region" and key:
        return region_key(key)
    raise ValueError(f"bad board scope/key: {scope}/{key}")


async def award(
    redis: Redis,
    user_id: str,
    points: int,
    *,
    subject_code: str | None = None,
    region_code: str | None = None,
) -> None:
    if points == 0:
        return
    pipe = redis.pipeline()
    pipe.zincrby(TOTAL_KEY, points, user_id)
    if subject_code:
        pipe.zincrby(subject_key(subject_code), points, user_id)
    if region_code:
        pipe.zincrby(region_key(region_code), points, user_id)
    await pipe.execute()


async def standing(
    redis: Redis, scope: str, key: str | None, user_id: str
) -> tuple[int, int] | None:
    """(rank, score) for one user on a board, rank 1-based. None if unranked."""
    bk = _board_key(scope, key)
    rank = await redis.zrevrank(bk, user_id)
    if rank is None:
        return None
    score = await redis.zscore(bk, user_id)
    return rank + 1, int(score or 0)


async def top(
    redis: Redis, scope: str, key: str | None, limit: int
) -> list[tuple[str, int]]:
    """Top `limit` as [(user_id, score), ...], highest first."""
    bk = _board_key(scope, key)
    rows = await redis.zrevrange(bk, 0, max(0, limit - 1), withscores=True)
    return [(uid, int(score)) for uid, score in rows]


async def total_ranked(redis: Redis, scope: str, key: str | None) -> int:
    return int(await redis.zcard(_board_key(scope, key)))
