"""
/v1/announcements — server-driven yangiliklar tasmasi.

Yangi xabar chiqarish = bitta INSERT. Ilova relizi kerak emas — bu texnik
ishlar (maintenance) haqida xabar berishning yagona real yo'li.

Auth YO'Q: "server ta'mirlanmoqda" xabari faqat login qilganlarga ko'rinsa,
foydasi yo'q. Faqat `is_active` + allaqachon `published_at` + muddati o'tmagan
satrlar qaytadi, ya'ni jadvalda turgan qoralama tashqariga chiqmaydi.

Til: `?lang=uz|ru`. Tarjima yo'q bo'lsa `uz` ga, u ham bo'lmasa mavjud
birinchi tilga tushadi — xabar ko'rsatilmagandan ko'ra boshqa tilda ko'ringani
yaxshi.
"""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models import Announcement

router = APIRouter(prefix="/v1/announcements", tags=["announcements"])

_FALLBACK = "uz"

def _pick(translations, lang: str):
    by_lang = {t.lang: t for t in translations}
    return by_lang.get(lang) or by_lang.get(_FALLBACK) or (
        translations[0] if translations else None)

@router.get("")
async def list_announcements(
    lang: str = Query("uz", max_length=8),
    grade: int | None = Query(None, ge=1, le=11),
    limit: int = Query(30, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    now = datetime.now(timezone.utc)
    stmt = (
        select(Announcement)
        .where(
            Announcement.is_active.is_(True),
            Announcement.published_at <= now,
            or_(Announcement.expires_at.is_(None), Announcement.expires_at > now),
        )
        .order_by(Announcement.published_at.desc())
        .limit(limit)
    )
    if grade is not None:
        stmt = stmt.where(or_(Announcement.grade.is_(None),
                              Announcement.grade == grade))

    rows = (await db.execute(stmt)).scalars().all()

    items = []
    for a in rows:
        tr = _pick(a.translations, lang)
        if tr is None:
            continue
        items.append({
            "id": str(a.id),
            "kind": a.kind,
            "title": tr.title,
            "body": tr.body,
            "grade": a.grade,
            "published_at": a.published_at.isoformat() if a.published_at else None,
        })
    return {"items": items}
