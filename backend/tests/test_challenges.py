"""
Challenge settlement tests — pure-logic level (DB calls monkeypatched).

The property that matters: EVERY terminal path conserves coins exactly.
Stakes escrowed = 2*stake (or 1*stake while open); settlement/refund must pay
out exactly that much, to the right players, and nothing on stake=0.
"""
import asyncio
import uuid
from types import SimpleNamespace
from datetime import datetime, timedelta, timezone

import pytest

from app.services import challenges as svc
from app.services import coins


class Ledger:
    """Records credit() calls so tests can assert conservation."""
    def __init__(self):
        self.rows = []      # (user_id, amount, reason)

    async def credit(self, db, user_id, amount, reason, **kw):
        assert amount > 0 and reason in coins.EARN_REASONS
        self.rows.append((user_id, amount, reason))

    def total(self):
        return sum(a for _, a, _ in self.rows)


def _ch(stake=100, creator_score=None, opponent_score=None, status="active",
        expires_in_h=24, opponent=True):
    return SimpleNamespace(
        id=uuid.uuid4(),
        creator_id=uuid.uuid4(),
        opponent_id=uuid.uuid4() if opponent else None,
        stake=stake,
        status=status,
        creator_score=creator_score,
        opponent_score=opponent_score,
        winner_id=None,
        expires_at=datetime.now(timezone.utc) + timedelta(hours=expires_in_h),
    )


def test_settle_winner_takes_full_pot(monkeypatch):
    led = Ledger()
    monkeypatch.setattr(svc.coins, "credit", led.credit)
    ch = _ch(stake=100, creator_score=8, opponent_score=5)
    asyncio.run(svc._settle(None, ch))
    assert ch.status == "done" and ch.winner_id == ch.creator_id
    assert led.rows == [(ch.creator_id, 200, "challenge_win")]
    assert led.total() == 2 * ch.stake                     # conservation


def test_settle_draw_refunds_both_exactly(monkeypatch):
    led = Ledger()
    monkeypatch.setattr(svc.coins, "credit", led.credit)
    ch = _ch(stake=100, creator_score=5, opponent_score=5)
    asyncio.run(svc._settle(None, ch))
    assert ch.status == "done" and ch.winner_id is None
    assert sorted(led.rows) == sorted([
        (ch.creator_id, 100, "challenge_refund"),
        (ch.opponent_id, 100, "challenge_refund"),
    ])
    assert led.total() == 2 * ch.stake                     # conservation


def test_settle_zero_stake_moves_no_coins(monkeypatch):
    led = Ledger()
    monkeypatch.setattr(svc.coins, "credit", led.credit)
    ch = _ch(stake=0, creator_score=1, opponent_score=0)
    asyncio.run(svc._settle(None, ch))
    assert ch.status == "done" and led.rows == []


def test_expiry_refunds_every_escrowed_stake(monkeypatch):
    led = Ledger()
    monkeypatch.setattr(svc.coins, "credit", led.credit)
    # active (both staked) + already expired
    ch = _ch(stake=50, expires_in_h=-1)
    asyncio.run(svc._lazy_expire(None, ch))
    assert ch.status == "expired"
    assert led.total() == 2 * ch.stake
    # open (only creator staked)
    led2 = Ledger()
    monkeypatch.setattr(svc.coins, "credit", led2.credit)
    ch2 = _ch(stake=50, status="open", opponent=False, expires_in_h=-1)
    asyncio.run(svc._lazy_expire(None, ch2))
    assert ch2.status == "expired"
    assert led2.rows == [(ch2.creator_id, 50, "challenge_refund")]


def test_expiry_noop_when_not_due_or_terminal(monkeypatch):
    led = Ledger()
    monkeypatch.setattr(svc.coins, "credit", led.credit)
    ch = _ch(stake=50, expires_in_h=1)                     # not due
    asyncio.run(svc._lazy_expire(None, ch))
    assert ch.status == "active" and led.rows == []
    done = _ch(stake=50, status="done", expires_in_h=-1)   # terminal stays terminal
    asyncio.run(svc._lazy_expire(None, done))
    assert done.status == "done" and led.rows == []


def test_invite_code_charset_unambiguous():
    for _ in range(200):
        code = svc._gen_code()
        assert len(code) == 6
        assert not set(code) & set("0O1I")                 # no lookalike chars


def test_new_reasons_keep_ledger_closed_loop():
    # challenge_win/refund are earn-side coin movements BETWEEN players — the
    # closed-loop guard (no reason converts coins to money) must still hold.
    forbidden = {"cashout", "withdraw", "transfer", "redeem_cash", "payout"}
    assert forbidden.isdisjoint(coins.EARN_REASONS | coins.SPEND_REASONS)
