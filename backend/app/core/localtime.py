from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

UZ_TZ = timezone(timedelta(hours=5))

UZ_UTC_OFFSET_HOURS = 5

def local_now() -> datetime:
    return datetime.now(UZ_TZ)

def local_today() -> date:
    return local_now().date()

def day_start_utc(d: date) -> datetime:
    return datetime(d.year, d.month, d.day, tzinfo=UZ_TZ).astimezone(timezone.utc)
