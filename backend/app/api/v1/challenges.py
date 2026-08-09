"""
/v1/challenges — async 1v1 friend challenges with coin stakes.

All endpoints require auth (guests can't bet). The question list endpoint serves
the PUBLIC projection only — during a bet no correctness info leaves the server
until the player's whole sheet is submitted (see services/challenges.py).
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db
from app.core.config import get_settings
from app.core.errors import AppError
from app.models import Question, User
from app.services import challenges as svc
from app.services.projection import to_public

router = APIRouter(prefix="/v1/challenges", tags=["challenges"])
_settings = get_settings()


# --------------------------------------------------------------------------- #
#  Schemas                                                                    #
# --------------------------------------------------------------------------- #
class ChallengeCreateIn(BaseModel):
    subject_id: str
    grade: int | None = Field(None, ge=1, le=11)
    question_count: int = Field(5, ge=1)
    stake: int = Field(0, ge=0)


class ChallengeJoinIn(BaseModel):
    code: str = Field(min_length=4, max_length=12)


class ChallengeAnswerIn(BaseModel):
    question_id: str
    payload: dict


class ChallengeSubmitIn(BaseModel):
    answers: list[ChallengeAnswerIn]


def _out(ch, me: uuid.UUID) -> dict:
    role = "creator" if ch.creator_id == me else "opponent"
    return {
        "id": str(ch.id),
        "code": ch.code,
        "role": role,
        "subject_id": str(ch.subject_id),
        "grade": ch.grade,
        "question_count": ch.question_count,
        "stake": ch.stake,
        "status": ch.status,
        "creator_score": ch.creator_score,
        "opponent_score": ch.opponent_score,
        "winner_id": str(ch.winner_id) if ch.winner_id else None,
        "i_won": (ch.winner_id == me) if ch.status == "done" else None,
        "my_score": ch.creator_score if role == "creator" else ch.opponent_score,
        "their_score": ch.opponent_score if role == "creator" else ch.creator_score,
        "has_opponent": ch.opponent_id is not None,
        "expires_at": ch.expires_at.isoformat() if ch.expires_at else None,
        "created_at": ch.created_at.isoformat() if ch.created_at else None,
    }


def _raise(e: svc.ChallengeError):
    raise AppError(e.status, e.title, e.detail)


# --------------------------------------------------------------------------- #
#  Endpoints                                                                  #
# --------------------------------------------------------------------------- #
@router.get("")
async def my_challenges(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    rows = await svc.list_mine(db, user.id)
    await db.commit()          # lazy expiry may have written refunds
    return {"items": [_out(ch, user.id) for ch in rows]}


@router.post("", status_code=201)
async def create_challenge(
    body: ChallengeCreateIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    try:
        ch = await svc.create(
            db, user.id,
            subject_id=uuid.UUID(body.subject_id),
            grade=body.grade,
            question_count=body.question_count,
            stake=body.stake,
        )
    except svc.ChallengeError as e:
        await db.rollback()
        _raise(e)
    await db.commit()
    return _out(ch, user.id)


@router.post("/join")
async def join_challenge(
    body: ChallengeJoinIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    try:
        ch = await svc.join(db, user.id, body.code)
    except svc.ChallengeError as e:
        await db.rollback()
        _raise(e)
    await db.commit()
    return _out(ch, user.id)


@router.post("/{challenge_id}/cancel")
async def cancel_challenge(
    challenge_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    try:
        ch = await svc.cancel(db, user.id, challenge_id)
    except svc.ChallengeError as e:
        await db.rollback()
        _raise(e)
    await db.commit()
    return _out(ch, user.id)


@router.get("/{challenge_id}/questions")
async def challenge_questions(
    challenge_id: uuid.UUID,
    lang: str = "uz-Latn",
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """The frozen question set, public projection only, participants only."""
    try:
        ch = await svc.get_for_participant(db, user.id, challenge_id)
    except svc.ChallengeError as e:
        await db.rollback()
        _raise(e)
    qrows = (await db.execute(
        select(Question).where(Question.id.in_(list(ch.question_ids)))
    )).scalars().all()
    # Preserve the frozen order (identical experience for both players).
    by_id = {str(q.id): q for q in qrows}
    ordered = [by_id[str(qid)] for qid in ch.question_ids if str(qid) in by_id]
    await db.commit()
    return {"items": [to_public(q, lang).model_dump() for q in ordered]}


@router.post("/{challenge_id}/submit")
async def submit_challenge(
    challenge_id: uuid.UUID,
    body: ChallengeSubmitIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    try:
        res = await svc.submit_result(
            db, user.id, challenge_id,
            [a.model_dump() for a in body.answers],
        )
    except svc.ChallengeError as e:
        await db.rollback()
        _raise(e)
    await db.commit()
    return res
