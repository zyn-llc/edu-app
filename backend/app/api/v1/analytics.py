from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_admin
from app.core.config import get_settings
from app.core.database import get_db

router = APIRouter(prefix="/v1/admin", tags=["admin"])
_settings = get_settings()

def _guest() -> uuid.UUID:
    return uuid.UUID(str(_settings.guest_user_id))

async def _rows(db: AsyncSession, sql: str, **params) -> list[dict]:
    res = await db.execute(text(sql), params)
    return [dict(r) for r in res.mappings().all()]


_RETENTION_SQL = """
WITH cohorts AS (
    SELECT u.id, date_trunc('day', u.created_at) AS cohort_day
    FROM users u
    WHERE u.created_at >= :since
      AND u.id <> :guest
),
activity AS (
    SELECT DISTINCT s.user_id, date_trunc('day', s.created_at) AS active_day
    FROM submissions s
    WHERE s.created_at >= :since
      AND s.user_id <> :guest
)
SELECT
    to_char(c.cohort_day, 'YYYY-MM-DD')                       AS cohort,
    count(*)                                                  AS users,
    count(*) FILTER (WHERE a1.user_id IS NOT NULL)            AS returned_d1,
    count(*) FILTER (WHERE a7.user_id IS NOT NULL)            AS returned_d7
FROM cohorts c
LEFT JOIN activity a1
       ON a1.user_id = c.id AND a1.active_day = c.cohort_day + interval '1 day'
LEFT JOIN activity a7
       ON a7.user_id = c.id AND a7.active_day = c.cohort_day + interval '7 day'
GROUP BY c.cohort_day
ORDER BY c.cohort_day
"""

_TIMESERIES_SQL = """
SELECT
    to_char(d.day, 'YYYY-MM-DD')                              AS day,
    coalesce(s.submissions, 0)                                AS submissions,
    coalesce(s.active_users, 0)                               AS active_users,
    coalesce(u.signups, 0)                                    AS signups
FROM generate_series(
        date_trunc('day', CAST(:since AS timestamptz)),
        date_trunc('day', now()),
        interval '1 day') AS d(day)
LEFT JOIN (
    SELECT date_trunc('day', created_at) AS day,
           count(*)                      AS submissions,
           count(DISTINCT user_id)       AS active_users
    FROM submissions
    WHERE created_at >= :since AND user_id <> :guest
    GROUP BY 1
) s ON s.day = d.day
LEFT JOIN (
    SELECT date_trunc('day', created_at) AS day, count(*) AS signups
    FROM users
    WHERE created_at >= :since AND id <> :guest
    GROUP BY 1
) u ON u.day = d.day
ORDER BY d.day
"""

_SUBJECTS_SQL = """
SELECT
    sub.code                                                  AS subject,
    count(*)                                                  AS submissions,
    count(DISTINCT s.user_id)                                 AS users,
    round(100.0 * avg(CASE WHEN s.is_correct THEN 1 ELSE 0 END), 1) AS accuracy_pct
FROM submissions s
JOIN questions q ON q.id = s.question_id
JOIN subjects sub ON sub.id = q.subject_id
WHERE s.created_at >= :since AND s.user_id <> :guest
GROUP BY sub.code
ORDER BY submissions DESC
"""

_SUSPECT_SQL = """
SELECT
    q.id::text                                                AS question_id,
    q.source_ref                                              AS source_ref,
    sub.code                                                  AS subject,
    q.grade                                                   AS grade,
    (q.media IS NOT NULL)                                     AS has_media,
    count(*)                                                  AS attempts,
    round(100.0 * avg(CASE WHEN s.is_correct THEN 1 ELSE 0 END), 1) AS correct_pct,
    left(coalesce(qt.stem, ''), 120)                          AS stem
FROM submissions s
JOIN questions q ON q.id = s.question_id
JOIN subjects sub ON sub.id = q.subject_id
LEFT JOIN question_translations qt
       ON qt.question_id = q.id AND qt.lang = 'uz'
WHERE s.created_at >= :since
GROUP BY q.id, q.source_ref, sub.code, q.grade, (q.media IS NOT NULL), qt.stem
HAVING count(*) >= :min_attempts
   AND avg(CASE WHEN s.is_correct THEN 1 ELSE 0 END) < :max_correct
ORDER BY count(*) DESC
LIMIT :limit
"""

@router.get("/analytics", dependencies=[Depends(require_admin)])
async def analytics(
    days: int = Query(30, ge=1, le=180),
    min_attempts: int = Query(20, ge=5, le=1000),
    max_correct_pct: float = Query(15.0, ge=0.0, le=100.0),
    suspect_limit: int = Query(50, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
):
    since = datetime.now(timezone.utc) - timedelta(days=days)
    guest = _guest()

    cohorts = await _rows(db, _RETENTION_SQL, since=since, guest=guest)

    today = datetime.now(timezone.utc).date()

    def _rate(offset_days: int, key: str) -> dict:
        eligible = [c for c in cohorts
                    if (today - datetime.strptime(c["cohort"], "%Y-%m-%d").date()).days
                    > offset_days]
        users = sum(c["users"] for c in eligible)
        returned = sum(c[key] for c in eligible)
        return {
            "users": users,
            "returned": returned,
            "pct": round(100.0 * returned / users, 1) if users else None,
            "cohorts_counted": len(eligible),
        }

    timeseries = await _rows(db, _TIMESERIES_SQL, since=since, guest=guest)
    subjects = await _rows(db, _SUBJECTS_SQL, since=since, guest=guest)
    suspects = await _rows(db, _SUSPECT_SQL, since=since,
                           min_attempts=min_attempts,
                           max_correct=max_correct_pct / 100.0,
                           limit=suspect_limit)

    return {
        "window_days": days,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "retention": {
            "d1": _rate(1, "returned_d1"),
            "d7": _rate(7, "returned_d7"),
            "by_cohort": cohorts,
        },
        "timeseries": timeseries,
        "subjects": subjects,
        "suspect_questions": {
            "criteria": {"min_attempts": min_attempts,
                         "max_correct_pct": max_correct_pct},
            "items": suspects,
        },
    }
