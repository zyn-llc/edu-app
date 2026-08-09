"""
Tier-1 analysis — pure SQL aggregation over submissions. No ML, no LLM. Powers the
student's own dashboard and (for linked children) the parent view.

Mastery is computed over DISTINCT questions, not raw attempts, so re-answering a
question can't inflate it: a topic's accuracy is (distinct questions ever answered
correctly) / (distinct questions attempted). This is the honest, farm-resistant
proxy for "how well does this student know this topic".
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import Integer, case, distinct, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    Question, Subject, Submission, Topic, TopicTranslation,
)


async def topic_mastery(
    db: AsyncSession, user_id: uuid.UUID, lang: str = "uz-Latn", limit: int = 50
) -> list[dict]:
    correct_q = func.count(distinct(
        case((Submission.is_correct, Submission.question_id))))
    answered_q = func.count(distinct(Submission.question_id))

    rows = (await db.execute(
        select(
            Question.topic_id,
            Topic.code,
            answered_q.label("answered"),
            correct_q.label("correct"),
        )
        .join(Question, Question.id == Submission.question_id)
        .join(Topic, Topic.id == Question.topic_id)
        .where(Submission.user_id == user_id, Question.topic_id.isnot(None))
        .group_by(Question.topic_id, Topic.code)
        .order_by(answered_q.desc())
        .limit(limit)
    )).all()

    if not rows:
        return []

    # Resolve topic names in the requested language (fallback to any/code).
    topic_ids = [r.topic_id for r in rows]
    name_rows = (await db.execute(
        select(TopicTranslation.topic_id, TopicTranslation.lang,
               TopicTranslation.title)      # ustun `title` (sql/001), `name` EMAS
        .where(TopicTranslation.topic_id.in_(topic_ids))
    )).all()
    names: dict[uuid.UUID, dict[str, str]] = {}
    for tid, lng, nm in name_rows:
        names.setdefault(tid, {})[lng] = nm

    out = []
    for r in rows:
        nm = names.get(r.topic_id, {})
        name = nm.get(lang) or (next(iter(nm.values())) if nm else r.code)
        answered = int(r.answered or 0)
        correct = int(r.correct or 0)
        out.append({
            "topic_code": r.code,
            "name": name,
            "answered": answered,
            "correct": correct,
            "accuracy": (correct / answered) if answered else 0.0,
        })
    return out


async def activity_by_day(
    db: AsyncSession, user_id: uuid.UUID, days: int = 14
) -> list[dict]:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    day = func.date(Submission.created_at).label("day")
    rows = (await db.execute(
        select(
            day,
            func.count().label("answered"),
            func.coalesce(
                func.sum(func.cast(Submission.is_correct, Integer)), 0)
            .label("correct"),
        )
        .where(Submission.user_id == user_id, Submission.created_at >= since)
        .group_by(day)
        .order_by(day)
    )).all()
    return [
        {"day": str(r.day), "answered": int(r.answered), "correct": int(r.correct)}
        for r in rows
    ]


async def recent_quizzes(
    db: AsyncSession, user_id: uuid.UUID, limit: int = 15
) -> list[dict]:
    rows = (await db.execute(
        select(
            Submission.created_at,
            Submission.is_correct,
            Submission.score,
            Submission.max_score,
            Subject.code.label("subject_code"),
        )
        .join(Question, Question.id == Submission.question_id)
        .join(Subject, Subject.id == Question.subject_id)
        .where(Submission.user_id == user_id)
        .order_by(Submission.created_at.desc())
        .limit(limit)
    )).all()
    return [
        {
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "subject_code": r.subject_code,
            "score": int(r.score),
            "max_score": int(r.max_score),
            "is_correct": bool(r.is_correct),
        }
        for r in rows
    ]


async def full_analysis(
    db: AsyncSession, user_id: uuid.UUID, lang: str = "uz-Latn",
    *, include_recent: bool = True,
) -> dict:
    return {
        "topics": await topic_mastery(db, user_id, lang),
        "activity": await activity_by_day(db, user_id),
        "recent": await recent_quizzes(db, user_id) if include_recent else [],
    }
