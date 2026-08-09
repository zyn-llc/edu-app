"""Leaderboard + progress DTOs."""
from __future__ import annotations

from pydantic import BaseModel, Field


class LeaderboardEntry(BaseModel):
    rank: int
    user_id: str
    display_name: str | None = None
    region_code: str | None = None
    # 021: avatar palitrasi indeksi — reytingda yuz ko'rinsin. NULL bo'lsa
    # klient ism hash'idan barqaror rang oladi, ya'ni bo'sh doira chiqmaydi.
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

    # ---- bugungi kesim ---------------------------------------------------
    # Ilgari klient "bugun mashq qilindimi" ni fanlarning `last_practiced_at`
    # idan TAXMIN qilardi va "12/20" kabi progressni umuman ko'rsata olmasdi.
    # Endi raqam serverdan keladi, ya'ni bosh ekrandagi maqsad chizig'i
    # haqiqiy.
    answered_today: int = 0
    correct_today: int = 0
    xp_today: int = 0                # faqat birinchi to'g'ri javoblar uchun

    # ---- so'nggi 7 kun ----------------------------------------------------
    answered_7d: int = 0
    correct_7d: int = 0
    accuracy_7d: float = 0.0         # 0..1 — umr bo'yi emas, YAQIN aniqlik
    xp_7d: int = 0
    active_days_7d: int = 0

    #: Har doim 7 ta element, eng eskisidan boshlab. Bo'sh kunlar ham bor —
    #: klient to'ldirishi shart emas.
    week: list[DayStat] = Field(default_factory=list)
