"""
Coin ledger — closed-loop play currency.

Balance is never stored; it is SUM(amount) over the append-only ledger. Earns are
positive, spends negative. The only earn wired so far is the quiz reward; spends
(competition entry, cosmetics) land with their features. There is intentionally no
function that converts coins to money.

`try_award_quiz` is the anti-farm gate: it inserts a `quiz_reward` row guarded by a
partial unique index on (user_id, ref_id). The insert runs inside a SAVEPOINT, so a
duplicate (the user already earned for this question) rolls back just the savepoint
and returns False — the surrounding submission transaction is untouched. XP is
awarded only when this returns True, so re-answering a question can't farm XP/coins.
"""
from __future__ import annotations

import uuid

from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CoinTransaction

EARN_REASONS = {"quiz_reward", "streak_bonus", "daily_ad_reward", "purchase",
                "daily_login", "challenge_win", "challenge_refund"}
SPEND_REASONS = {"competition_entry", "cosmetic", "badge", "challenge_stake",
                 "quiz_penalty"}

async def balance(db: AsyncSession, user_id: uuid.UUID) -> int:
    total = await db.scalar(
        select(func.coalesce(func.sum(CoinTransaction.amount), 0))
        .where(CoinTransaction.user_id == user_id)
    )
    return int(total or 0)

async def recent(db: AsyncSession, user_id: uuid.UUID, limit: int = 20) -> list[dict]:
    rows = (await db.execute(
        select(CoinTransaction)
        .where(CoinTransaction.user_id == user_id)
        .order_by(CoinTransaction.created_at.desc())
        .limit(limit)
    )).scalars().all()
    return [
        {
            "amount": t.amount,
            "reason": t.reason,
            "ref_type": t.ref_type,
            "ref_id": t.ref_id,
            "created_at": t.created_at.isoformat() if t.created_at else None,
        }
        for t in rows
    ]

async def try_award_quiz(
    db: AsyncSession, user_id: uuid.UUID, question_id: str, amount: int
) -> bool:
    """Mint a one-time quiz reward for (user, question). Returns True if minted now,
    False if it already existed. Caller commits."""
    if amount <= 0:
        return False
    # Fast path: skip the savepoint if we can already see a prior reward.
    existing = await db.scalar(
        select(CoinTransaction.id).where(
            CoinTransaction.user_id == user_id,
            CoinTransaction.reason == "quiz_reward",
            CoinTransaction.ref_id == question_id,
        ).limit(1)
    )
    if existing is not None:
        return False
    try:
        async with db.begin_nested():       # SAVEPOINT
            db.add(CoinTransaction(
                user_id=user_id, amount=amount, reason="quiz_reward",
                source="earned", ref_type="question", ref_id=question_id,
            ))
        return True
    except IntegrityError:
        # Lost a race to the unique index — already rewarded. Outer tx intact.
        return False

async def spend(
    db: AsyncSession,
    user_id: uuid.UUID,
    amount: int,
    reason: str,
    *,
    ref_type: str | None = None,
    ref_id: str | None = None,
) -> bool:
    """Debit `amount` (>0) coins for a spend `reason`. Returns False if the balance
    is insufficient (no row written). Caller commits."""
    if amount <= 0 or reason not in SPEND_REASONS:
        return False
    # Serialize spends per user for this transaction: balance() + INSERT is a
    # read-then-write, so two concurrent spends could both pass the check and
    # overdraw (e.g. creating two staked challenges at once). The advisory lock
    # is keyed on the user id and released automatically at commit/rollback.
    await db.execute(
        text("SELECT pg_advisory_xact_lock(hashtext(:uid))"),
        {"uid": str(user_id)},
    )
    if await balance(db, user_id) < amount:
        return False
    db.add(CoinTransaction(
        user_id=user_id, amount=-amount, reason=reason,
        source="earned", ref_type=ref_type, ref_id=ref_id,
    ))
    return True

# --------------------------------------------------------------------------- #
#  Economy v2 — gentle penalty, guaranteed daily recovery, ad top-up           #
#                                                                              #
#  Design intent (product): coins gate CHALLENGE STAKES ONLY, never practice.  #
#  A wrong answer costs a little; a day of showing up restores more than a few #
#  wrong answers cost; ads are an instant top-up. Balance is floored at 0 —    #
#  debt UX punishes struggling students, which is exactly who we must keep.    #
# --------------------------------------------------------------------------- #
async def apply_wrong_penalty(
    db: AsyncSession, user_id: uuid.UUID, question_id: str, amount: int
) -> int:
    """Deduct up to `amount` coins for a wrong answer, never going below 0.
    Returns the coins actually deducted (0 if broke). Caller commits."""
    if amount <= 0:
        return 0
    await db.execute(
        text("SELECT pg_advisory_xact_lock(hashtext(:uid))"),
        {"uid": str(user_id)},
    )
    bal = await balance(db, user_id)
    take = min(amount, max(bal, 0))
    if take <= 0:
        return 0
    db.add(CoinTransaction(
        user_id=user_id, amount=-take, reason="quiz_penalty",
        source="earned", ref_type="question", ref_id=question_id,
    ))
    return take

async def try_award_daily_login(
    db: AsyncSession, user_id: uuid.UUID, day_iso: str, amount: int
) -> bool:
    """Once-per-day bonus (ref_id = 'YYYY-MM-DD', guarded by a partial unique
    index) — guarantees a zero balance always recovers by the next day. Same
    savepoint pattern as the quiz reward. Caller commits."""
    if amount <= 0:
        return False
    existing = await db.scalar(
        select(CoinTransaction.id).where(
            CoinTransaction.user_id == user_id,
            CoinTransaction.reason == "daily_login",
            CoinTransaction.ref_id == day_iso,
        ).limit(1)
    )
    if existing is not None:
        return False
    try:
        async with db.begin_nested():
            db.add(CoinTransaction(
                user_id=user_id, amount=amount, reason="daily_login",
                source="earned", ref_type="day", ref_id=day_iso,
            ))
        return True
    except IntegrityError:
        return False

async def award_ad_reward(
    db: AsyncSession, user_id: uuid.UUID, amount: int, ref_id: str
) -> None:
    """Credit a rewarded-ad view. The per-day cap lives in Redis at the endpoint
    (see api/v1/coins.py); this just writes the ledger row. Caller commits."""
    db.add(CoinTransaction(
        user_id=user_id, amount=amount, reason="daily_ad_reward",
        source="earned", ref_type="ad", ref_id=ref_id,
    ))

async def credit(
    db: AsyncSession, user_id: uuid.UUID, amount: int, reason: str,
    *, ref_type: str | None = None, ref_id: str | None = None,
) -> bool:
    """Generic earn-side credit (challenge_win / challenge_refund / streak_bonus).
    Returns True if a row was written, False if this exact settlement already
    existed. Caller commits.

    SAVEPOINT, like try_award_quiz — and for the same reason. Challenge expiry
    refunds are written from READ paths (`GET /v1/challenges`), which do not lock
    the row, so two concurrent reads used to see the same open-and-expired
    challenge and each pay out a full refund. `uq_coin_challenge_settle` (026)
    now rejects the second insert; the savepoint keeps that rejection from
    aborting the surrounding transaction.
    """
    if amount <= 0 or reason not in EARN_REASONS:
        raise ValueError(f"bad credit: {amount} {reason}")
    try:
        async with db.begin_nested():
            db.add(CoinTransaction(
                user_id=user_id, amount=amount, reason=reason,
                source="earned", ref_type=ref_type, ref_id=ref_id,
            ))
        return True
    except IntegrityError:
        return False
