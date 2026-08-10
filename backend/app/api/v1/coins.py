"""
/v1/me/coins — balance, history, and the rewarded-ad top-up.

Ad reward: the client calls this after AdMob reports a completed rewarded view.
MVP trusts the client but caps abuse hard (N per day, Redis). Before launch,
switch to AdMob Server-Side Verification: Google signs a callback to YOUR server
with a nonce; only then credit. The endpoint shape already anticipates that —
`ad_id` becomes the SSV transaction id, and the unique ref stops double-credits.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db
from app.core.config import get_settings
from app.core.errors import AppError
from app.core.redis import get_redis
from app.models import User
from app.services import coins

router = APIRouter(prefix="/v1/me/coins", tags=["coins"])
_settings = get_settings()

class AdRewardIn(BaseModel):
    ad_id: str = Field(default="", max_length=128)   # SSV transaction id later

@router.get("")
async def my_coins(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return {
        "balance": await coins.balance(db, user.id),
        "history": await coins.recent(db, user.id),
        "per_correct": _settings.coins_per_correct,
        "per_wrong": _settings.coins_per_wrong_penalty,
        "daily_bonus": _settings.coins_daily_login,
        "per_ad": _settings.coins_per_ad,
        "ads_left_today": await _ads_left(user.id),
    }

async def _ads_left(user_id: uuid.UUID) -> int:
    redis = get_redis()
    key = f"ads:{user_id}:{datetime.now(timezone.utc).date().isoformat()}"
    used = int(await redis.get(key) or 0)
    return max(_settings.ads_per_day_cap - used, 0)

@router.post("/ad-reward")
async def ad_reward(
    body: AdRewardIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    # exists in client-trust mode (dev). With the flag off there is no way to
    # verify an ad was watched, so the only safe answer is 403.
    if not _settings.allow_client_ad_rewards:
        raise AppError(403, "Ad rewards unavailable",
                       "ad verification is not enabled on this server")
    redis = get_redis()
    day = datetime.now(timezone.utc).date().isoformat()
    key = f"ads:{user.id}:{day}"
    used = await redis.incr(key)
    if used == 1:
        await redis.expire(key, 24 * 3600)
    if used > _settings.ads_per_day_cap:
        raise AppError(429, "Daily ad limit reached",
                       f"max {_settings.ads_per_day_cap} rewarded ads per day")
    await coins.award_ad_reward(
        db, user.id, _settings.coins_per_ad,
        ref_id=body.ad_id or f"{day}#{used}",
    )
    await db.commit()
    return {
        "awarded": _settings.coins_per_ad,
        "balance": await coins.balance(db, user.id),
        "ads_left_today": max(_settings.ads_per_day_cap - used, 0),
    }
