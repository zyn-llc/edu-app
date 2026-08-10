"""
Leaderboard + self endpoints.

  GET /v1/leaderboard?scope=total|subject|region&key=<code>&limit=50
        -> top N for the board + the caller's own standing (even if off-page)
  GET /v1/me        -> profile + progress (xp/level/streak/accuracy) + total rank

Ranking numbers come from Redis (services/ranking); Postgres is touched only to put
names on the rows being returned.
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_current_user_optional
from app.api.v1.auth import _user_out
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.redis import get_redis
from app.core.regions import REGIONS
from app.models import User
from app.schemas.leaderboard import LeaderboardEntry, LeaderboardOut, ProgressOut
from app.services import analysis as analysis_service
from app.services import coins as coin_service
from app.services import progress as progress_service
from app.services import ranking

router = APIRouter(prefix="/v1", tags=["ranking"])
_settings = get_settings()

async def _names(db: AsyncSession, ids: list[str]) -> dict[str, User]:
    if not ids:
        return {}
    uuids = [uuid.UUID(i) for i in ids]
    rows = (await db.execute(select(User).where(User.id.in_(uuids)))).scalars().all()
    return {str(u.id): u for u in rows}

@router.get("/leaderboard", response_model=LeaderboardOut)
async def leaderboard(
    scope: str = Query("total"),
    key: str | None = Query(None),
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db),
    me: User | None = Depends(get_current_user_optional),
):
    if scope not in ("total", "subject", "region"):
        raise AppError(400, "Bad scope", "scope must be total|subject|region")
    if scope in ("subject", "region") and not key:
        raise AppError(400, "Missing key", f"{scope} board requires ?key=")

    try:
        rows = await ranking.top(get_redis(), scope, key, limit)
        total = await ranking.total_ranked(get_redis(), scope, key)
    except ValueError as e:
        raise AppError(400, "Bad board", str(e))

    me_id = str(me.id) if me else None
    name_map = await _names(db, [uid for uid, _ in rows])
    entries = []
    for i, (uid, score) in enumerate(rows):
        u = name_map.get(uid)
        entries.append(LeaderboardEntry(
            rank=i + 1, user_id=uid,
            display_name=u.display_name if u else None,
            region_code=u.region_code if u else None,
            avatar_color=u.avatar_color if u else None,
            score=score, is_me=(uid == me_id),
        ))

    me_entry = None
    if me:
        st = await ranking.standing(get_redis(), scope, key, me_id)
        if st is not None:
            rank, score = st
            me_entry = LeaderboardEntry(
                rank=rank, user_id=me_id, display_name=me.display_name,
                region_code=me.region_code, avatar_color=me.avatar_color,
                score=score, is_me=True,
            )

    return LeaderboardOut(scope=scope, key=key, entries=entries,
                          me=me_entry, total_ranked=total)

@router.get("/me")
async def me_overview(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    prog = await progress_service.get_progress(db, user.id)
    st = await ranking.standing(get_redis(), "total", None, str(user.id))
    coin_balance = await coin_service.balance(db, user.id)
    return {
        "user": _user_out(user).model_dump(),
        "progress": ProgressOut(**prog).model_dump(),
        "rank": (st[0] if st else None),
        "coins": coin_balance,
    }

@router.get("/me/analysis")
async def my_analysis(
    accept_language: str | None = Header(None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    lang = (accept_language or "uz-Latn").split(",")[0].strip()
    return await analysis_service.full_analysis(db, user.id, lang)

# /me/coins moved to app/api/v1/coins.py (richer payload: economy numbers +
# rewarded-ad state). Keeping one canonical route avoids the duplicate-route
# shadowing that broke the challenge tab's coin bar.

@router.get("/regions")
async def regions():
    """Static reference for the profile region picker + region leaderboard keys."""
    return {"regions": REGIONS}
