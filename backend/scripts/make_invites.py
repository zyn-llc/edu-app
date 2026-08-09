"""
Taklif kodlarini generatsiya qiladi va bazaga yozadi.

    python scripts/make_invites.py --count 30 --label "Yopiq beta"
    python scripts/make_invites.py --count 1 --uses 40 --label "Ustoz markazi" --days 30
    python scripts/make_invites.py --list

Ikki xil strategiya:
  * --count 30 --uses 1   -> 30 ta shaxsiy kod. Kim kirganini aniq bilasan,
                             lekin 30 ta kodni tarqatish kerak.
  * --count 1 --uses 40   -> bitta guruh kodi. O'quv markazi rahbariga bitta
                             xabar yuborasan, u guruhga tashlaydi. Amalda tezroq
                             va odamlar adashmaydi.

Alifbo ataylab chalkash belgilarsiz: 0/O, 1/I/L yo'q — telefonda ko'chirib
yozganda xato bo'lmasin.
"""
from __future__ import annotations

import argparse
import asyncio
import secrets
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, ".")

from sqlalchemy import text                                    # noqa: E402
from app.core.database import SessionLocal                     # noqa: E402

ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"


def gen_code(length: int = 8) -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(length))


def pretty(code: str) -> str:
    """K7M4X9QP -> K7M4-X9QP (faqat ko'rsatish uchun; bazada chiziqchasiz)."""
    mid = len(code) // 2
    return f"{code[:mid]}-{code[mid:]}"


async def create(count: int, uses: int, label: str | None,
                 days: int | None, grade: int | None) -> None:
    expires = (datetime.now(timezone.utc) + timedelta(days=days)) if days else None
    created: list[str] = []

    async with SessionLocal() as db:
        for _ in range(count):
            for _attempt in range(5):                # to'qnashuv ehtimoli ~0
                code = gen_code()
                row = (await db.execute(text("""
                    INSERT INTO invite_codes
                        (code, label, max_uses, grade, expires_at)
                    VALUES (:code, :label, :uses, :grade, :expires)
                    ON CONFLICT (code) DO NOTHING
                    RETURNING code
                """), {"code": code, "label": label, "uses": uses,
                       "grade": grade, "expires": expires})).scalar()
                if row:
                    created.append(row)
                    break
            else:
                print("!! kod generatsiya qilinmadi, qayta urinib ko'ring")
        await db.commit()

    print(f"\n{len(created)} ta kod yaratildi"
          f"{f' — {label}' if label else ''}, har biri {uses} marta ishlatiladi"
          f"{f', {days} kun amal qiladi' if days else ''}:\n")
    for c in created:
        print("   ", pretty(c))
    print("\nO'quvchiga chiziqcha bilan yuborsang ham bo'ladi — ilova uni "
          "o'zi tozalaydi.\n")


async def show() -> None:
    async with SessionLocal() as db:
        rows = (await db.execute(text("""
            SELECT code, label, used_count, max_uses, is_active, expires_at
            FROM invite_codes ORDER BY created_at DESC LIMIT 200
        """))).mappings().all()
    if not rows:
        print("kod yo'q")
        return
    print(f"{'kod':<12} {'ishlatilgan':<12} {'holat':<10} label")
    print("-" * 60)
    for r in rows:
        alive = r["is_active"] and (
            r["expires_at"] is None or r["expires_at"] > datetime.now(timezone.utc))
        used = f"{r['used_count']}/{r['max_uses']}"
        state = "aktiv" if alive and r["used_count"] < r["max_uses"] else "yopiq"
        print(f"{pretty(r['code']):<12} {used:<12} {state:<10} {r['label'] or ''}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=30, help="nechta kod")
    ap.add_argument("--uses", type=int, default=1, help="har bir kod necha marta")
    ap.add_argument("--label", type=str, default=None, help="izoh: maktab/markaz nomi")
    ap.add_argument("--days", type=int, default=None, help="necha kun amal qiladi")
    ap.add_argument("--grade", type=int, default=None, help="yangi akkauntga sinf yozish")
    ap.add_argument("--list", action="store_true", help="mavjud kodlarni ko'rsatish")
    a = ap.parse_args()

    if a.list:
        asyncio.run(show())
    else:
        asyncio.run(create(a.count, a.uses, a.label, a.days, a.grade))


if __name__ == "__main__":
    main()
