"""
Qaytarish xabarlari — Telegram orqali.

Nima yuboriladi va NEGA aynan shu to'rttasi:

  challenge_invite    Do'sting seni chorladi. Yagona haqiqiy viral halqa, va u
                      xabarsiz umuman ishlamaydi: chorlangan odam ilovani o'zi
                      ochmasa, chaqiruv 24 soatdan keyin jim yonib ketadi.
  challenge_result    Raqib o'ynadi. Natijani ko'rish — qaytishning eng arzon
                      sababi, chunki qiziqish allaqachon bor.
  challenge_expiring  Muddat tugayapti. Bu YO'QOTISH xabari, ya'ni eng kuchlisi:
                      tikilgan noncoin qaytib ketishi mumkin.
  streak_at_risk      Seriya bugun uziladi. Faqat seriyasi 3+ bo'lganlarga —
                      2 kunlik seriya uchun xabar yuborish spam, chunki
                      foydalanuvchi hali unga bog'lanmagan.

QAT'IY QOIDALAR (ular buzilsa botni o'chirishadi):

  1. Bitta xabar — bir marta. `notifications` jadvalining birlamchi kaliti
     (user_id, kind, ref_id) shuni ta'minlaydi, skript emas.
  2. Kuniga ko'pi bilan `MAX_PER_DAY` ta xabar. Bir kunda uchta bellashuv
     kelsa ham uchta xabar ketmaydi.
  3. `users.tg_notifications = false` bo'lsa — hech narsa yuborilmaydi.
  4. Telegram'siz hisoblar (telefon/taklif kodi bilan kirganlar) chetlab
     o'tiladi: `telegram_id IS NULL`.

Ishga tushirish (VPS'da, kuniga bir marta):
    docker compose -f docker-compose.prod.yml exec -T api \\
        python -m app.services.notify
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import SessionLocal
from app.core.localtime import local_today
from app.services import telegram as tg

_log = logging.getLogger("topagon.notify")

MAX_PER_DAY = 2

STREAK_MIN = 3

_APP_URL = "https://app.topagon.uz"

_INVITES_SQL = """
SELECT c.id::text AS ref_id, u.telegram_id, u.display_name,
       cr.display_name AS from_name
FROM challenges c
JOIN users u  ON u.id = c.opponent_id
JOIN users cr ON cr.id = c.creator_id
WHERE c.status = 'active'
  AND c.expires_at > now()
  AND u.telegram_id IS NOT NULL
  AND u.tg_notifications IS DISTINCT FROM false
  AND NOT EXISTS (SELECT 1 FROM challenge_results r
                   WHERE r.challenge_id = c.id AND r.user_id = u.id)
"""

#: Muddati 6 soatdan kam qolgan va hali o'ynalmagan bellashuvlar.
_EXPIRING_SQL = """
SELECT c.id::text AS ref_id, u.telegram_id, u.display_name
FROM challenges c
JOIN users u ON u.id IN (c.creator_id, c.opponent_id)
WHERE c.status IN ('open', 'active')
  AND c.expires_at BETWEEN now() AND now() + interval '6 hours'
  AND u.telegram_id IS NOT NULL
  AND u.tg_notifications IS DISTINCT FROM false
  AND NOT EXISTS (SELECT 1 FROM challenge_results r
                   WHERE r.challenge_id = c.id AND r.user_id = u.id)
"""

_RESULTS_SQL = """
SELECT c.id::text AS ref_id, u.telegram_id, u.display_name,
       (c.winner_id = u.id) AS i_won, (c.winner_id IS NULL) AS is_draw
FROM challenges c
JOIN users u ON u.id IN (c.creator_id, c.opponent_id)
WHERE c.status = 'done'
  AND c.created_at > now() - interval '3 days'
  AND u.telegram_id IS NOT NULL
  AND u.tg_notifications IS DISTINCT FROM false
"""

_STREAK_SQL = """
SELECT u.id::text AS uid, u.telegram_id, u.display_name, p.streak_days
FROM user_progress p
JOIN users u ON u.id = p.user_id
WHERE p.streak_days >= :min_streak
  AND p.last_active = :yesterday
  AND u.telegram_id IS NOT NULL
  AND u.tg_notifications IS DISTINCT FROM false
"""

def _name(row) -> str:
    return (row.display_name or "").strip() or "do'stim"

def _msg_invite(r) -> str:
    who = (r.from_name or "").strip() or "Do'stingiz"
    return (f"{_name(r)}, {who} sizni bellashuvga chorladi ⚔️\n\n"
            f"Javob bermasangiz 24 soatdan keyin bekor bo'ladi.\n{_APP_URL}")

def _msg_result(r) -> str:
    if r.i_won:
        return f"{_name(r)}, bellashuv yakunlandi — SIZ YUTDINGIZ 🏆\n{_APP_URL}"
    if r.is_draw:
        return (f"{_name(r)}, bellashuv durang bilan tugadi. "
                f"Garov qaytarildi.\n{_APP_URL}")
    return f"{_name(r)}, bellashuv yakunlandi. Natijani ko'ring:\n{_APP_URL}"

def _msg_expiring(r) -> str:
    return (f"{_name(r)}, bellashuvingizga 6 soatdan kam vaqt qoldi ⏳\n"
            f"O'ynamasangiz garov qaytariladi.\n{_APP_URL}")

def _msg_streak(r) -> str:
    return (f"{_name(r)}, {r.streak_days} kunlik seriyangiz bugun uziladi 🔥\n"
            f"Bitta savol yetadi.\n{_APP_URL}")

async def _already_sent_today(db: AsyncSession, telegram_ids: list[int]) -> set[str]:
    """Bugun allaqachon MAX_PER_DAY ta xabar olgan foydalanuvchilar."""
    if not telegram_ids:
        return set()
    rows = (await db.execute(text("""
        SELECT u.telegram_id::text
        FROM notifications n
        JOIN users u ON u.id = n.user_id
        WHERE n.sent_at >= now() - interval '24 hours'
          AND u.telegram_id = ANY(:ids)
        GROUP BY u.telegram_id
        HAVING count(*) >= :cap
    """), {"ids": telegram_ids, "cap": MAX_PER_DAY})).scalars().all()
    return set(rows)

async def _claim(db: AsyncSession, telegram_id: int, kind: str, ref_id: str) -> bool:
    """Xabarni "band qilish". `False` — allaqachon yuborilgan.

    INSERT ... ON CONFLICT DO NOTHING: takrorlanmaslik kafolati birlamchi
    kalitda, ya'ni skript ikki marta ishga tushsa ham ikkinchi xabar ketmaydi.
    Yozuv yuborishdan OLDIN qo'yiladi — Telegram javob bermay qolsa bitta
    xabar yo'qoladi, bu takroriy spamdan yaxshiroq.
    """
    row = (await db.execute(text("""
        INSERT INTO notifications (user_id, kind, ref_id)
        SELECT u.id, :kind, :ref FROM users u WHERE u.telegram_id = :tg
        ON CONFLICT DO NOTHING
        RETURNING user_id
    """), {"kind": kind, "ref": ref_id, "tg": telegram_id})).first()
    return row is not None

async def run_once(db: AsyncSession) -> dict[str, int]:
    """Barcha turdagi xabarlarni bir marta yuboradi. Yuborilganlar sonini
    qaytaradi — cron log'ida shu ko'rinadi."""
    sent: dict[str, int] = {}
    yesterday = local_today() - timedelta(days=1)

    plans = [
        ("challenge_invite", _INVITES_SQL, {}, _msg_invite),
        ("challenge_result", _RESULTS_SQL, {}, _msg_result),
        ("challenge_expiring", _EXPIRING_SQL, {}, _msg_expiring),
        ("streak_at_risk", _STREAK_SQL,
         {"min_streak": STREAK_MIN, "yesterday": yesterday}, _msg_streak),
    ]

    for kind, sql, params, render in plans:
        rows = (await db.execute(text(sql), params)).all()
        if not rows:
            continue
        capped = await _already_sent_today(db, [int(r.telegram_id) for r in rows])

        n = 0
        for r in rows:
            tg_id = int(r.telegram_id)
            if str(tg_id) in capped:
                continue
            ref = (local_today().isoformat() if kind == "streak_at_risk"
                   else r.ref_id)
            if not await _claim(db, tg_id, kind, ref):
                continue
            await db.commit()
            try:
                await tg.send_message(tg_id, render(r))
                n += 1
            except Exception:
                _log.exception("notify failed kind=%s tg=%s", kind, tg_id)
        sent[kind] = n

    await db.commit()
    return sent

async def main() -> None:
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    async with SessionLocal() as db:
        result = await run_once(db)
    total = sum(result.values())
    _log.info("notify: %s ta xabar yuborildi %s", total, result or "{}")

if __name__ == "__main__":
    asyncio.run(main())
