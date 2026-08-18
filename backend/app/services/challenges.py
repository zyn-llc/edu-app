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

   
    if stake > 0:
        await db.flush()   
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


async def submit_result(
    db: AsyncSession,
    user_id: uuid.UUID,
    challenge_id: uuid.UUID,
    answers: list[dict],           
) -> dict:
   
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
                correct = False        
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
    exactly (pot = 2*stake in every branch).
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


async def _get(db: AsyncSession, challenge_id: uuid.UUID, *, lock: bool = False) -> Challenge:
    stmt = select(Challenge).where(Challenge.id == challenge_id)
    if lock:
        stmt = stmt.with_for_update()
    ch = (await db.execute(stmt)).scalar_one_or_none()
    if ch is None:
        raise ChallengeError(404, "Challenge not found")
    return ch

async def _lazy_expire(db: AsyncSession, ch: Challenge) -> None:
   
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
    ch = await _get(db, challenge_id, lock=True)
    await _lazy_expire(db, ch)
    if user_id not in (ch.creator_id, ch.opponent_id):
        raise ChallengeError(403, "Not a participant")
    return ch
