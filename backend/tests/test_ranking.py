"""Leaderboard sorted-set behavior against fakeredis. Skipped without fakeredis."""
import asyncio

import pytest

fakeredis = pytest.importorskip("fakeredis")
import fakeredis.aioredis  # noqa: E402

from app.services import ranking  # noqa: E402

U1 = "11111111-1111-1111-1111-111111111111"
U2 = "22222222-2222-2222-2222-222222222222"


def _redis():
    return fakeredis.aioredis.FakeRedis(decode_responses=True)


def test_award_accumulates_and_orders():
    async def run():
        r = _redis()
        await ranking.award(r, U1, 30, subject_code="geografiya")
        await ranking.award(r, U2, 50, subject_code="geografiya")
        await ranking.award(r, U1, 40, subject_code="geografiya")  # U1 now 70

        top = await ranking.top(r, "total", None, 10)
        assert top == [(U1, 70), (U2, 50)]                  # highest first

        subj = await ranking.top(r, "subject", "geografiya", 10)
        assert subj == [(U1, 70), (U2, 50)]
    asyncio.run(run())


def test_standing_is_one_based_and_none_when_absent():
    async def run():
        r = _redis()
        await ranking.award(r, U1, 30)
        await ranking.award(r, U2, 50)
        assert await ranking.standing(r, "total", None, U2) == (1, 50)
        assert await ranking.standing(r, "total", None, U1) == (2, 30)
        assert await ranking.standing(r, "total", None, "nope") is None
    asyncio.run(run())


def test_total_ranked_counts_members():
    async def run():
        r = _redis()
        await ranking.award(r, U1, 10)
        await ranking.award(r, U2, 20)
        assert await ranking.total_ranked(r, "total", None) == 2
    asyncio.run(run())


def test_zero_points_is_noop():
    async def run():
        r = _redis()
        await ranking.award(r, U1, 0)
        assert await ranking.total_ranked(r, "total", None) == 0
    asyncio.run(run())


def test_bad_scope_raises():
    async def run():
        r = _redis()
        with pytest.raises(ValueError):
            await ranking.top(r, "subject", None, 10)   # missing key
    asyncio.run(run())
