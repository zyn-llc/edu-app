"""Leaderboard + progress DTOs."""
from __future__ import annotations

from pydantic import BaseModel, Field

class LeaderboardEntry(BaseModel):
    rank: int
    user_id: str
    display_name: str | None = None
    region_code: str | None = None
    avatar_color: int | None = None
    score: int
    is_me: bool = False

class LeaderboardOut(BaseModel):
    scope: str                       # 'total' | 'subject' | 'region'
    key: str | None = None           # subject_code or region_code for scoped boards
    entries: list[LeaderboardEntry] = Field(default_factory=list)
    # The requester's own standing, even if outside the returned page.
    me: LeaderboardEntry | None = None
    total_ranked: int = 0

class DayStat(BaseModel):
    """Bitta MAHALLIY kalendar kuni (UTC+5) — haftalik chiziq uchun."""
    date: str                        # YYYY-MM-DD
    answered: int = 0
    correct: int = 0
    is_today: bool = False

class ProgressOut(BaseModel):
    xp: int = 0
    level: int = 1
    streak_days: int = 0
    answered: int = 0
    correct: int = 0
    accuracy: float = 0.0            # 0..1

    answered_today: int = 0
    correct_today: int = 0
    xp_today: int = 0

    answered_7d: int = 0
    correct_7d: int = 0
    accuracy_7d: float = 0.0
    xp_7d: int = 0
    active_days_7d: int = 0

    week: list[DayStat] = Field(default_factory=list)
