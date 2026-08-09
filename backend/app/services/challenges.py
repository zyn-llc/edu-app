"""
Challenge service — async 1v1 friend challenges with a coin stake.

Lifecycle (status):
  open      creator staked, waiting for an opponent (invite code)
  active    opponent joined + staked; both play the SAME frozen question set
  done      both results in -> settled (winner takes pot; draw refunds both)
  cancelled creator cancelled while open -> stake refunded
  expired   TTL passed -> all paid stakes refunded (applied lazily on read)

Money safety properties:
  * Stakes are ESCROWED through the coin ledger (challenge_stake, negative) the
    moment each player commits — no side balance, no trust in the client.
  * Settlement writes challenge_win (pot) or challenge_refund rows; every path
    (win / draw / cancel / expiry) conserves coins exactly. Closed loop holds:
    coins never leave the ledger, they only move between the two players. The
    "exactly once" half of that is enforced by uq_coin_challenge_settle
    (sql/026), not by application flow — see _lazy_expire.
  * The question set is frozen in challenges.question_ids at creation, so it
    can't be re-rolled for easier questions, and both players get identical Qs.
  * One result row per player (PK challenge_id+user_id) — a bet can't be retried.
  * Challenge answers do NOT mint XP/quiz coins and do NOT touch the public
    leaderboard: challenges must not become a farming loop.
"""
from __future__ import annotations

import secrets
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import Challenge, ChallengeResult, Question
from app.schemas.question import SubmissionIn
from app.services import coins, grading
from app.services.projection import to_grading

_settings = get_settings()

_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no ambiguous 0/O/1/I


class ChallengeError(Exception):
    def __init__(self, status: int, title: str, detail: str | None = None):
        self.status = status
        self.title = title
        self.detail = detail
        super().__init__(title)


def _gen_code() -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(6))


def _now() -> datetime:
    return datetime.now(timezone.utc)


# --------------------------------------------------------------------------- #
#  Create / join / cancel                                                     #
# --------------------------------------------------------------------------- #
async def create(
    db: AsyncSession,
    creator_id: uuid.UUID,
    *,
    subject_id: uuid.UUID,
    grade: int | None,
    question_count: int,
    stake: int,
) -> Challenge:
    if not (1 <= question_count <= _settings.challenge_max_questions):
        raise ChallengeError(400, "Bad question count",
                             f"1–{_settings.challenge_max_questions}")
    if not (0 <= stake <= _settings.challenge_max_stake):
        raise ChallengeError(400, "Bad stake",
                             f"0–{_settings.challenge_max_stake} coins")

    # Freeze the question set now (server-picked, identical for both players).
    stmt = select(Question.id).where(
        Question.subject_id == subject_id, Question.status == "active")
    if grade is not None:
        stmt = stmt.where(Question.grade == grade)
    qids = (await db.execute(
        stmt.order_by(func.random()).limit(question_count)
    )).scalars().all()
    if len(qids) < question_count:
        raise ChallengeError(400, "Not enough questions",
                             f"only {len(qids)} available for this selection")

    ch = Challenge(
        code=_gen_code(),
        creator_id=creator_id,
        subject_id=subject_id,
        grade=grade,
        question_count=question_count,
        stake=stake,
        question_ids=list(qids),
        status="open",
        expires_at=_now() + timedelta(hours=_settings.challenge_ttl_hours),
    )
    db.add(ch)

    # Escrow the creator's stake immediately.
    if stake > 0:
        await db.flush()   # need ch.id for the ledger ref
        ok = await coins.spend(db, creator_id, stake, "challenge_stake",
                               ref_type="challenge", ref_id=str(ch.id))
        if not ok:
            raise ChallengeError(402, "Not enough coins",
                                 "earn coins by answering, the daily bonus, or ads")
    await db.flush()
    return ch


async def join(db: AsyncSession, opponent_id: uuid.UUID, code: str) -> Challenge:
    ch = (await db.execute(
        select(Challenge)
        .where(Challenge.code == code.strip().upper())
        .with_for_update()
    )).scalar_one_or_none()
    if ch is None:
        raise ChallengeError(404, "Challenge not found")
    await _lazy_expire(db, ch)
    if ch.status != "open":
        raise ChallengeError(409, "Challenge not open", f"status is {ch.status}")
    if ch.creator_id == opponent_id:
        raise ChallengeError(400, "Cannot join your own challenge")

    if ch.stake > 0:
        ok = await coins.spend(db, opponent_id, ch.stake, "challenge_stake",
                               ref_type="challenge", ref_id=str(ch.id))
        if not ok:
            raise ChallengeError(402, "Not enough coins",
                                 "earn coins by answering, the daily bonus, or ads")
    ch.opponent_id = opponent_id
    ch.status = "active"
    return ch


async def cancel(db: AsyncSession, user_id: uuid.UUID, challenge_id: uuid.UUID) -> Challenge:
    ch = await _get(db, challenge_id, lock=True)
    if ch.creator_id != user_id:
        raise ChallengeError(403, "Not your challenge")
    if ch.status != "open":
        raise ChallengeError(409, "Only open challenges can be cancelled")
    ch.status = "cancelled"
    if ch.stake > 0:
        await coins.credit(db, ch.creator_id, ch.stake, "challenge_refund",
                           ref_type="challenge", ref_id=str(ch.id))
    return ch


# --------------------------------------------------------------------------- #
#  Play                                                                       #
# --------------------------------------------------------------------------- #
async def submit_result(
    db: AsyncSession,
    user_id: uuid.UUID,
    challenge_id: uuid.UUID,
    answers: list[dict],           # [{question_id, payload}]
) -> dict:
    """Grade a player's full answer sheet server-side, store their result, and
    settle the challenge if both players are now done.

    Batch (one call, all answers) rather than per-question on purpose: during a
    bet the client gets NO per-question feedback, so a player can't harvest the
    key set mid-game or relay answers to the opponent. Corrections come back only
    in this response, after the sheet is locked in.
    """
    ch = await _get(db, challenge_id, lock=True)
    await _lazy_expire(db, ch)
    if ch.status != "active":
        raise ChallengeError(409, "Challenge not active", f"status is {ch.status}")
    if user_id not in (ch.creator_id, ch.opponent_id):
        raise ChallengeError(403, "Not a participant")

    existing = (await db.execute(
        select(ChallengeResult).where(
            ChallengeResult.challenge_id == ch.id,
            ChallengeResult.user_id == user_id)
    )).scalar_one_or_none()
    if existing is not None:
        raise ChallengeError(409, "Already submitted", "a bet can't be retried")

    # Answers must cover exactly the frozen set (missing = wrong, extras rejected).
    frozen = {str(q) for q in ch.question_ids}
    by_qid = {}
    for a in answers:
        qid = str(a.get("question_id", ""))
        if qid not in frozen:
            raise ChallengeError(400, "Unknown question in answers", qid)
        by_qid[qid] = a.get("payload") or {}

    qrows = (await db.execute(
        select(Question).where(Question.id.in_(list(ch.question_ids)))
    )).scalars().all()

    score = 0
    max_score = 0
    detail = []
    for q in qrows:
        max_score += q.max_score
        payload = by_qid.get(str(q.id))
        correct = False
        if payload is not None:
            try:
                res = grading.grade(
                    to_grading(q),
                    SubmissionIn(question_id=str(q.id), payload=payload),
                )
                correct = res.is_correct
            except Exception:
                correct = False        # malformed answer = wrong, never a 500
        if correct:
            score += q.max_score
        detail.append({"question_id": str(q.id), "is_correct": correct})

    db.add(ChallengeResult(
        challenge_id=ch.id, user_id=user_id,
        score=score, max_score=max_score, detail=detail,
    ))
    if user_id == ch.creator_id:
        ch.creator_score = score
    else:
        ch.opponent_score = score

    settled = None
    if ch.creator_score is not None and ch.opponent_score is not None:
        settled = await _settle(db, ch)

    return {
        "challenge_id": str(ch.id),
        "your_score": score,
        "max_score": max_score,
        "detail": detail,
        "status": ch.status,
        "settled": settled,
    }


async def _settle(db: AsyncSession, ch: Challenge) -> dict:
    """Both results in: winner takes the pot; draw refunds both. Conserves coins
    exactly (pot = 2*stake in every branch)."""
    ch.status = "done"
    pot = ch.stake * 2
    if ch.creator_score > ch.opponent_score:
        ch.winner_id = ch.creator_id
    elif ch.opponent_score > ch.creator_score:
        ch.winner_id = ch.opponent_id
    else:
        ch.winner_id = None

    if ch.stake > 0:
        if ch.winner_id is not None:
            await coins.credit(db, ch.winner_id, pot, "challenge_win",
                               ref_type="challenge", ref_id=str(ch.id))
        else:
            await coins.credit(db, ch.creator_id, ch.stake, "challenge_refund",
                               ref_type="challenge", ref_id=str(ch.id))
            await coins.credit(db, ch.opponent_id, ch.stake, "challenge_refund",
                               ref_type="challenge", ref_id=str(ch.id))
    return {"winner_id": str(ch.winner_id) if ch.winner_id else None, "pot": pot}


# --------------------------------------------------------------------------- #
#  Read + expiry                                                              #
# --------------------------------------------------------------------------- #
async def _get(db: AsyncSession, challenge_id: uuid.UUID, *, lock: bool = False) -> Challenge:
    stmt = select(Challenge).where(Challenge.id == challenge_id)
    if lock:
        # Mutating paths lock the row: without it, two players joining the same
        # open challenge (or join+cancel) both read status='open', both escrow a
        # stake, and the second commit silently overwrites the first opponent —
        # losing their coins. FOR UPDATE makes the second waiter re-read 'active'
        # and fail cleanly on the status check.
        stmt = stmt.with_for_update()
    ch = (await db.execute(stmt)).scalar_one_or_none()
    if ch is None:
        raise ChallengeError(404, "Challenge not found")
    return ch


async def _lazy_expire(db: AsyncSession, ch: Challenge) -> None:
    """Expiry is applied on read (no cron needed yet). Every escrowed stake is
    refunded; a player who already submitted into a challenge the other abandoned
    gets their stake back too.

    CONCURRENCY. This runs from READ endpoints too (`GET /v1/challenges`), which
    do not hold a row lock, so two parallel requests can both see the same
    open-and-expired challenge and both try to refund. The guarantee that this
    pays out exactly once is NOT the lock — it is `uq_coin_challenge_settle`
    (sql/026): `coins.credit` returns False on the duplicate instead of writing
    a second row. Setting `status` twice is harmless; paying twice was not.
    """
    if ch.status not in ("open", "active") or ch.expires_at > _now():
        return
    ch.status = "expired"
    if ch.stake > 0:
        await coins.credit(db, ch.creator_id, ch.stake, "challenge_refund",
                           ref_type="challenge", ref_id=str(ch.id))
        if ch.opponent_id is not None:
            await coins.credit(db, ch.opponent_id, ch.stake, "challenge_refund",
                               ref_type="challenge", ref_id=str(ch.id))


async def list_mine(db: AsyncSession, user_id: uuid.UUID, limit: int = 30) -> list[Challenge]:
    rows = (await db.execute(
        select(Challenge).where(
            (Challenge.creator_id == user_id) | (Challenge.opponent_id == user_id)
        ).order_by(Challenge.created_at.desc()).limit(limit)
    )).scalars().all()
    for ch in rows:
        await _lazy_expire(db, ch)
    return rows


async def get_for_participant(
    db: AsyncSession, user_id: uuid.UUID, challenge_id: uuid.UUID
) -> Challenge:
    # `lock=True` — bu yo'l ham `_lazy_expire` chaqiradi va u YOZADI. Bitta
    # satr uchun qulf arzon, va u parallel so'rovlarni behuda rollback
    # qilishdan qutqaradi (to'g'rilikning o'zi 026 indeksida).
    ch = await _get(db, challenge_id, lock=True)
    await _lazy_expire(db, ch)
    if user_id not in (ch.creator_id, ch.opponent_id):
        raise ChallengeError(403, "Not a participant")
    return ch
