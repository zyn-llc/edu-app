"""
Progress service — server-authoritative XP, level, and daily streak.

The streak/level arithmetic is pure (no DB) so it can be unit-tested directly;
`touch_activity` loads the row and applies it. XP is the same number that feeds the
leaderboard, so "rank" and "level" can never disagree.

`touch_activity` and `award_xp` are deliberately SEPARATE: the streak advances on
every answer (showing up counts), while XP is minted only on a question's first
correct answer — gated by the coin ledger's unique index, see services/coins.py.

Streak rule: answering on a new calendar day continues the streak if the previous
active day was exactly yesterday, otherwise it resets to 1.

Calendar day is the LOCAL (UTC+5) day — see app/core/localtime.py for why. The
same offset is applied on the SQL side so Python and Postgres never disagree
about which day a submission belongs to.
"""
from __future__ import annotations

import logging
import uuid
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import Integer, func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.localtime import UZ_UTC_OFFSET_HOURS, day_start_utc, local_today
from app.models import Submission, UserProgress

_log = logging.getLogger("topagon.progress")
_settings = get_settings()


def level_for_xp(xp: int) -> int:
    return 1 + xp // _settings.xp_per_level


def xp_for_score(score: int) -> int:
    return score * _settings.xp_per_point


def next_streak(prev_streak: int, last_active: date | None, today: date) -> int:
    if last_active == today:
        return max(prev_streak, 1)            # already counted today
    if last_active is not None and (today - last_active).days == 1:
        return prev_streak + 1                # consecutive day
    return 1                                  # first ever, or a gap broke it


async def touch_activity(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    today: date | None = None,
) -> UserProgress:
    """Record that the user was active today (advances/holds the streak). Runs on
    EVERY answer, right or wrong, repeat or not — showing up is what the streak
    rewards. Returns the row (not committed). XP is handled separately so it can be
    gated on first-correct."""
    today = today or local_today()
    prog = (await db.execute(
        select(UserProgress).where(UserProgress.user_id == user_id)
    )).scalar_one_or_none()
    if prog is None:
        prog = UserProgress(user_id=user_id, xp=0, level=1, streak_days=0)
        db.add(prog)
    prog.streak_days = next_streak(prog.streak_days, prog.last_active, today)
    prog.last_active = today
    return prog


def award_xp(prog: UserProgress, score: int) -> None:
    """Add XP for a score and recompute level. Call ONLY on a first-correct answer
    (gated by the coin ledger's one-reward-per-question guard) so XP can't be farmed
    by re-answering."""
    prog.xp = (prog.xp or 0) + xp_for_score(score)
    prog.level = level_for_xp(prog.xp)


async def parent_signals(db: AsyncSession, user_id: uuid.UUID) -> dict:
    """Ota-ona uchun MA'NOLI ko'rsatkichlar.

    NEGA ALOHIDA (2026-08-06, sinovda aytilgan e'tiroz). Ota-ona paneli
    bolaning o'zi ko'radigan raqamlarni takrorlardi: XP, daraja, seriya,
    aniqlik. Ota-onaga bularning ma'nosi yo'q — u XP nima ekanini bilmaydi.
    Ota-ona bilmoqchi bo'lgan narsa boshqacha:

      * bola ODATDA shug'ullanadimi  -> oxirgi mashq qachon bo'lgan,
                                         shu haftada nechta savol,
                                         nechta kun faol bo'lgan;
      * qayerda qiynalyapti          -> so'nggi 7 kundagi aniqlik
                                         (umr bo'yi emas — u eskirgan).

    Hammasi `submissions` dan hisoblanadi, qo'shimcha jadval kerak emas.
    """
    now = datetime.now(timezone.utc)
    week_ago = now - timedelta(days=7)

    row = (await db.execute(
        select(
            func.count(),
            func.coalesce(func.sum(func.cast(Submission.is_correct, Integer)), 0),
            func.count(func.distinct(func.date(Submission.created_at))),
        ).where(
            Submission.user_id == user_id,
            Submission.created_at >= week_ago,
        )
    )).one()
    answered_7d = int(row[0] or 0)
    correct_7d = int(row[1] or 0)
    active_days_7d = int(row[2] or 0)

    last_at = (await db.execute(
        select(func.max(Submission.created_at))
        .where(Submission.user_id == user_id)
    )).scalar_one_or_none()

    return {
        "answered_7d": answered_7d,
        "correct_7d": correct_7d,
        "accuracy_7d": (correct_7d / answered_7d) if answered_7d else 0.0,
        "active_days_7d": active_days_7d,
        "last_practiced_at": last_at.isoformat() if last_at else None,
    }


# --------------------------------------------------------------------------- #
#  Bugungi va haftalik kesim                                                   #
# --------------------------------------------------------------------------- #
#
# NEGA KERAK (2026-08-08). Bosh ekranda "Bugungi maqsad" bor edi, lekin
# BAJARILGANLIK darajasi yo'q edi: server "bugun nechta savol yechildi" ni
# bilmasdi, shuning uchun klient uni ha/yo'q sifatida taxmin qilardi
# (fanlarning `last_practiced_at` i orqali). Natijada eng motivatsion element
# — to'ladigan progress chizig'i — umuman ko'rsatilmasdi.
#
# Hammasi `submissions` dan hisoblanadi: yangi jadval ham, denormalizatsiya
# ham kerak emas. 30 sinovchi va bir necha ming submission uchun bu arzon.

#: Kun chegarasini SQL tomonda mahalliy vaqtga o'tkazish.
#
# `created_at` timestamptz. `AT TIME ZONE 'UTC'` uni UTC devor-soatiga
# aylantiradi (natija — oddiy timestamp), so'ng ofset qo'shiladi va sana
# olinadi. `AT TIME ZONE 'Asia/Tashkent'` ATAYLAB ISHLATILMADI: u konteynerda
# tz bazasi bo'lishini talab qiladi va bo'lmasa jim ravishda noto'g'ri
# javob beradi.
_LOCAL_DAY = (
    f"((s.created_at AT TIME ZONE 'UTC') "
    f"+ interval '{UZ_UTC_OFFSET_HOURS} hours')::date"
)

_DAILY_SQL = f"""
SELECT {_LOCAL_DAY}                                        AS day,
       count(*)                                            AS answered,
       count(*) FILTER (WHERE s.is_correct)                AS correct
FROM submissions s
WHERE s.user_id = :uid
  AND s.created_at >= :since
GROUP BY 1
ORDER BY 1
"""

# XP faqat savolga BIRINCHI marta to'g'ri javob berilganda beriladi (tanga
# daftaridagi "bitta savol — bitta mukofot" qo'riqchisi bilan). Shu sababli
# "bugun qancha XP" ni submission'larni shunchaki sanab chiqarib bo'lmaydi:
# takroriy to'g'ri javoblar XP bermaydi va raqam shishib ketardi.
#
# `DISTINCT ON (question_id) ... ORDER BY question_id, created_at` — har bir
# savolning ENG BIRINCHI to'g'ri javobi. XP o'sha lahzada berilgan.
_XP_WINDOW_SQL = """
WITH firsts AS (
    SELECT DISTINCT ON (s.question_id)
           s.question_id, s.created_at, s.score
    FROM submissions s
    WHERE s.user_id = :uid AND s.is_correct
    ORDER BY s.question_id, s.created_at
)
SELECT
    coalesce(sum(score) FILTER (WHERE created_at >= :today_start), 0) AS today,
    coalesce(sum(score) FILTER (WHERE created_at >= :week_start), 0)  AS week
FROM firsts
"""


async def daily_breakdown(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    days: int = 7,
) -> dict:
    """So'nggi `days` mahalliy kun: kunlik ro'yxat + bugungi/haftalik yig'indi.

    Qaytadigan `week` ro'yxati HAR DOIM `days` ta elementdan iborat va eng
    eskisidan boshlanadi — klientda "bo'sh kun" ni to'ldirish kerak emas,
    ya'ni Du–Ya nuqtalari qatori bir xil uzunlikda qoladi.
    """
    today = local_today()
    first_day = today - timedelta(days=days - 1)
    week_start = day_start_utc(first_day)
    today_start = day_start_utc(today)

    rows = (await db.execute(
        text(_DAILY_SQL), {"uid": user_id, "since": week_start}
    )).mappings().all()
    by_day = {r["day"]: r for r in rows}

    week: list[dict] = []
    for i in range(days):
        d = first_day + timedelta(days=i)
        r = by_day.get(d)
        week.append({
            "date": d.isoformat(),
            "answered": int(r["answered"]) if r else 0,
            "correct": int(r["correct"]) if r else 0,
            "is_today": d == today,
        })

    xp_row = (await db.execute(
        text(_XP_WINDOW_SQL),
        {"uid": user_id, "today_start": today_start, "week_start": week_start},
    )).one()

    answered_7d = sum(d["answered"] for d in week)
    correct_7d = sum(d["correct"] for d in week)
    todays = week[-1]

    return {
        "answered_today": todays["answered"],
        "correct_today": todays["correct"],
        "xp_today": int(xp_row[0] or 0) * _settings.xp_per_point,
        "answered_7d": answered_7d,
        "correct_7d": correct_7d,
        "accuracy_7d": (correct_7d / answered_7d) if answered_7d else 0.0,
        "xp_7d": int(xp_row[1] or 0) * _settings.xp_per_point,
        "active_days_7d": sum(1 for d in week if d["answered"] > 0),
        "week": week,
    }


async def get_progress(db: AsyncSession, user_id: uuid.UUID) -> dict:
    """Progress + lifetime answer stats for /v1/me and parent dashboards."""
    prog = (await db.execute(
        select(UserProgress).where(UserProgress.user_id == user_id)
    )).scalar_one_or_none()

    answered, correct = (await db.execute(
        select(func.count(), func.coalesce(func.sum(
            func.cast(Submission.is_correct, Integer)), 0))
        .where(Submission.user_id == user_id)
    )).one()

    answered = int(answered or 0)
    correct = int(correct or 0)
    base = {
        "xp": prog.xp if prog else 0,
        "level": prog.level if prog else 1,
        "streak_days": prog.streak_days if prog else 0,
        "answered": answered,
        "correct": correct,
        "accuracy": (correct / answered) if answered else 0.0,
    }

    # Kunlik kesim ALOHIDA qo'riqlanadi.
    #
    # NEGA. `/v1/me` — ilovaning eng issiq endpointi: bosh ekran har
    # ochilganda chaqiriladi va u yerda XP, daraja, seriya, reyting bor.
    # Kunlik kesim esa xom SQL bilan yoziladi (`text()`), ya'ni Postgres
    # versiyasi yoki ustun turi kutilmagan bo'lsa xato ISH VAQTIDA chiqadi.
    # Qo'riqchisiz bitta shunday xato butun bosh ekranni o'ldiradi.
    #
    # Qo'riqchi bilan eng yomon holat: yangi bloklar (bugungi maqsad
    # progressi, haftalik chiziq) ko'rinmaydi, qolgan hamma narsa ishlaydi.
    # Klient bo'sh `week` ni allaqachon "ko'rsatma" deb tushunadi.
    #
    # SAVEPOINT MAJBURIY, oddiy `try/except` YETARLI EMAS: Postgres'da
    # xato bergan so'rov butun tranzaksiyani "aborted" holatiga o'tkazadi va
    # SHU sessiyadagi keyingi so'rovlar ham yiqiladi. `/v1/me` da esa
    # `get_progress` dan KEYIN yana bazaga murojaat bor
    # (`coin_service.balance`) — savepointsiz qo'riqchi hech narsani
    # qutqarmagan bo'lardi. Bu naqsh `content.py` dagi mukofot hisobidan
    # olingan (u yerda ham xuddi shu sabab bo'lgan).
    #
    # Xato JIM YUTILMAYDI — `docker compose logs api | grep daily_breakdown`.
    try:
        async with db.begin_nested():
            base.update(await daily_breakdown(db, user_id))
    except Exception:                                   # noqa: BLE001
        _log.exception("daily_breakdown failed for user %s — "
                       "progress served without today/week fields", user_id)
    return base
