"""
OTP lifecycle tests against an in-memory Redis (fakeredis). Skipped if fakeredis
isn't installed, so the core suite still runs without it:

    pip install fakeredis      # to exercise these
"""
import asyncio

import pytest

fakeredis = pytest.importorskip("fakeredis")
import fakeredis.aioredis  # noqa: E402

from app.services import otp  # noqa: E402


def _redis():
    return fakeredis.aioredis.FakeRedis(decode_responses=True)


def test_issue_then_verify_consumes_code():
    async def run():
        r = _redis()
        code, ttl = await otp.issue(r, "+998901234567")
        assert len(code) == 6 and code.isdigit()
        assert ttl > 0
        assert await otp.verify(r, "+998901234567", code) is True
        # single-use: the same code can't be replayed
        assert await otp.verify(r, "+998901234567", code) is False
    asyncio.run(run())


def test_wrong_code_does_not_authenticate():
    async def run():
        r = _redis()
        await otp.issue(r, "+998901234567")
        assert await otp.verify(r, "+998901234567", "000000") is False
    asyncio.run(run())


def test_code_burned_after_max_attempts():
    async def run():
        r = _redis()
        code, _ = await otp.issue(r, "+998901234567")
        for _ in range(otp._settings.otp_max_attempts):
            await otp.verify(r, "+998901234567", "999999")  # wrong
        # even the correct code is now rejected — the code was burned
        assert await otp.verify(r, "+998901234567", code) is False
    asyncio.run(run())


def test_request_cooldown_blocks_rapid_reissue():
    async def run():
        r = _redis()
        await otp.issue(r, "+998901234567")
        with pytest.raises(otp.OtpError) as ei:
            await otp.issue(r, "+998901234567")
        assert ei.value.code == "cooldown"
    asyncio.run(run())


def test_role_intent_roundtrips():
    async def run():
        r = _redis()
        await otp.issue(r, "+998901234567", role="parent")
        assert await otp.pop_role(r, "+998901234567") == "parent"
        # cleared after pop -> falls back to default
        assert await otp.pop_role(r, "+998901234567") == "student"
    asyncio.run(run())
