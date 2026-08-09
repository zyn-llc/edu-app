"""
Mahalliy kalendar kuni — O'zbekiston vaqti (UTC+5).

NEGA KERAK. Ilgari "bugun" hamma joyda UTC kuni edi. O'zbekistonda UTC+5,
ya'ni mahalliy 00:00–05:00 oralig'ida yechilgan savol KECHAGI kunga tushardi.
Oqibati foydalanuvchi ko'radigan joyda chiqadi:

  * kechqurun 01:00 da mashq qilgan o'quvchi ertalab "bugun 0 savol" ni
    ko'radi, holbuki u bir necha soat oldin ishlagan;
  * seriya ("streak") ham xuddi shu sababli buziladi — bir kun ikki marta
    sanaladi yoki umuman sanalmaydi.

O'zbekistonda yozgi vaqt YO'Q (1996 dan beri), shuning uchun qat'iy +5
ofset to'g'ri va tz ma'lumotlar bazasiga bog'liq emas. Bu esa muhim: SQL
tomonda ham xuddi shu ofset `interval '5 hours'` bilan qo'llanadi
(`app/services/progress.py`), ya'ni Python va Postgres bir xil kunni
ko'radi. Agar bu yerda `ZoneInfo("Asia/Tashkent")` ishlatilsa, konteynerda
tz bazasi bo'lmasa jim ravishda UTC ga tushib qolardi.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

#: O'zbekiston vaqti. Yozgi vaqt yo'q — qat'iy ofset.
UZ_TZ = timezone(timedelta(hours=5))

#: SQL tomonda ishlatiladigan bir xil ofset (soatlarda).
UZ_UTC_OFFSET_HOURS = 5


def local_now() -> datetime:
    """Hozirgi mahalliy vaqt (tz-aware)."""
    return datetime.now(UZ_TZ)


def local_today() -> date:
    """Bugungi MAHALLIY kalendar kuni."""
    return local_now().date()


def day_start_utc(d: date) -> datetime:
    """Mahalliy `d` kunining boshlanishi, UTC lahzasi sifatida.

    `WHERE created_at >= :x` uchun — `submissions.created_at` timestamptz.
    """
    return datetime(d.year, d.month, d.day, tzinfo=UZ_TZ).astimezone(timezone.utc)
