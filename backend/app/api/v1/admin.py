"""
/v1/admin/stats — operational metrics for the founder, zero extra infra.

Auth: `api.deps.require_admin` — X-Admin-Key, constant-time, rate limited, and
404 on every failure so there is nothing to probe. This is founder tooling, not
a user-facing surface; when a team exists, replace with role-based admin
accounts. nginx should ALSO restrict /v1/admin/ by IP (deploy/nginx.conf).

Numbers are computed live with a handful of aggregate queries — fine well past
100k users. When dashboards/history are needed, point Grafana or Metabase at a
Postgres read replica instead of growing this endpoint.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db, require_admin
from app.core.config import get_settings
from app.models import Challenge, CoinTransaction, Question, Submission, User

router = APIRouter(prefix="/v1/admin", tags=["admin"])
_settings = get_settings()


@router.get("/stats", dependencies=[Depends(require_admin)])
async def stats(db: AsyncSession = Depends(get_db)):
    now = datetime.now(timezone.utc)
    day_ago = now - timedelta(days=1)
    week_ago = now - timedelta(days=7)
    guest = _settings.guest_user_id

    async def one(stmt):
        return (await db.execute(stmt)).scalar() or 0

    users_total = await one(select(func.count(User.id)))
    users_new_24h = await one(
        select(func.count(User.id)).where(User.created_at >= day_ago))
    users_new_7d = await one(
        select(func.count(User.id)).where(User.created_at >= week_ago))

    # Engagement: distinct answering users = the honest "active" number.
    dau = await one(
        select(func.count(func.distinct(Submission.user_id)))
        .where(Submission.created_at >= day_ago,
               Submission.user_id != guest))
    wau = await one(
        select(func.count(func.distinct(Submission.user_id)))
        .where(Submission.created_at >= week_ago,
               Submission.user_id != guest))
    submissions_24h = await one(
        select(func.count(Submission.id))
        .where(Submission.created_at >= day_ago))
    guest_submissions_24h = await one(
        select(func.count(Submission.id))
        .where(Submission.created_at >= day_ago,
               Submission.user_id == guest))

    questions_active = await one(
        select(func.count(Question.id)).where(Question.status == "active"))

    challenges_active = await one(
        select(func.count(Challenge.id))
        .where(Challenge.status.in_(["open", "active"])))
    challenges_done_7d = await one(
        select(func.count(Challenge.id))
        .where(Challenge.status == "done", Challenge.created_at >= week_ago))

    # Economy: minted vs sunk in 24h. If minted consistently dwarfs sunk, the
    # coin supply inflates and stakes stop meaning anything — the number to watch.
    coins_minted_24h = await one(
        select(func.coalesce(func.sum(CoinTransaction.amount), 0))
        .where(CoinTransaction.created_at >= day_ago, CoinTransaction.amount > 0))
    coins_sunk_24h = await one(
        select(func.coalesce(func.sum(-CoinTransaction.amount), 0))
        .where(CoinTransaction.created_at >= day_ago, CoinTransaction.amount < 0))

    # "Do'stlaringizni taklif qiling" (024) — mukofotsiz, shuning uchun
    # yagona nazorat vositasi shu: kim qancha odam olib kelganini ko'rish.
    # Faqat TOP 10 — dashboard, cheksiz ro'yxat emas.
    referrals_total = await one(
        select(func.count(User.id)).where(User.referred_by.isnot(None)))
    top_referrers = (await db.execute(
        select(User.referred_by, func.count(User.id))
        .where(User.referred_by.isnot(None))
        .group_by(User.referred_by)
        .order_by(func.count(User.id).desc())
        .limit(10)
    )).all()

    return {
        "generated_at": now.isoformat(),
        "users": {"total": users_total, "new_24h": users_new_24h,
                  "new_7d": users_new_7d},
        "engagement": {"dau": dau, "wau": wau,
                       "submissions_24h": submissions_24h,
                       "guest_submissions_24h": guest_submissions_24h},
        "content": {"questions_active": questions_active},
        "challenges": {"open_or_active": challenges_active,
                       "settled_7d": challenges_done_7d},
        "economy": {"coins_minted_24h": int(coins_minted_24h),
                    "coins_sunk_24h": int(coins_sunk_24h)},
        "referrals": {
            "total": referrals_total,
            "top": [{"username": u, "count": c} for u, c in top_referrers],
        },
    }
