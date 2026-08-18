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
        async with db.begin_nested():       
            db.add(CoinTransaction(
                user_id=user_id, amount=amount, reason="quiz_reward",
                source="earned", ref_type="question", ref_id=question_id,
            ))
        return True
    except IntegrityError:
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
   
    is insufficient (no row written). Caller commits.
    if amount <= 0 or reason not in SPEND_REASONS:
        return False
    
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
