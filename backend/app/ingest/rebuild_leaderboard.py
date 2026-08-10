#!/usr/bin/env python3
"""
rebuild_leaderboard.py — Redis leaderboard'larini Postgres'dan qayta quradi.

    PYTHONPATH=. python -m app.ingest.rebuild_leaderboard --dry-run
    PYTHONPATH=. python -m app.ingest.rebuild_leaderboard

Leaderboard'lar Redis sorted set'larida yashaydi (lb:total, lb:subject:*,
lb:region:*) va `ranking.award()` ularni inkremental yangilaydi. Redis
flush qilinsa, persistence'siz qayta ishga tushsa yoki drift bo'lsa — reyting
noto'g'ri bo'ladi va buni SEZISHNING YO'LI YO'Q. Bu skript hammasini
`submissions` jadvalidan qayta hisoblaydi.

Mehmon (guest) yuborishlari CHIQARIB TASHLANADI — mehmon umumiy akkaunt,
u reytingda ko'rinmasligi kerak (submit handler ham shunday qiladi).

Almashtirish har bir board uchun ATOMAR: avval `lb:*:rebuild` quriladi, keyin
RENAME bilan tirik kalit ustiga qo'yiladi — o'quvchi hech qachon yarim
to'ldirilgan reytingni ko'rmaydi.

DIQQAT: bu fayl ilgari xato joyda — `app/api/v1/` da yotgan edi. U yerda
router emas, CLI skript turishi mantiqsiz (`main.py` uni import qilmaydi,
lekin papka ko'rgan odam router deb o'ylaydi). Eski nusxani o'chir:
    Remove-Item "D:\\platform edu\\backend\\app\\api\\v1\\rebuild_leaderboard.py"
"""
from __future__ import annotations

import asyncio
import os
import re
import sys
from collections import defaultdict

def resolve_url() -> str:
    """`.env` dagi manzilni HOST mashinadan ishlaydigan shaklga keltiradi.

    `DATABASE_URL` da host `db:5432` turadi — bu konteyner ichida to'g'ri,
    lekin skript Windows host'dan ishga tushirilsa `getaddrinfo failed`
    beradi. `localhost` ham ishlamaydi: Windows uni IPv6 `::1` ga hal qiladi,
    Docker esa IPv4'da tinglaydi.

    Konteyner ICHIDA esa aksincha — almashtirish kerak emas, chunki u yerda
    `127.0.0.1` konteynerning o'zi. Shu farqni `app/ingest/dsn.py` hal qiladi.
    """
    from app.ingest.dsn import resolve_url as _resolve
    return _resolve()

async def main(dry: bool) -> int:
    from sqlalchemy import select, func as sqlfunc
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

    from app.core.config import get_settings
    from app.core.redis import get_redis, close_redis
    from app.models import Question, Submission, Subject, User
    from app.services import ranking

    settings = get_settings()
    guest_id = str(settings.guest_user_id)

    engine = create_async_engine(resolve_url(), pool_pre_ping=True)
    Session = async_sessionmaker(engine, expire_on_commit=False)

    total: dict[str, int] = defaultdict(int)
    by_subject: dict[tuple[str, str], int] = defaultdict(int)
    by_region: dict[tuple[str, str], int] = defaultdict(int)

    try:
        async with Session() as db:
            subj_code = {sid: code for sid, code in
                         (await db.execute(select(Subject.id, Subject.code))).all()}
            user_region = {str(uid): rc for uid, rc in
                           (await db.execute(select(User.id, User.region_code))).all()}

            rows = (await db.execute(
                select(Submission.user_id,
                       Question.subject_id,
                       sqlfunc.sum(Submission.score))
                .join(Question, Question.id == Submission.question_id)
                .group_by(Submission.user_id, Question.subject_id)
            )).all()
    except Exception as e:
        print("!! DB ULANMADI:", type(e).__name__, str(e)[:200])
        await engine.dispose()
        return 1
    finally:
        await engine.dispose()

    skipped_guest = 0
    for uid, sid, score in rows:
        uid_s = str(uid)
        pts = int(score or 0)
        if uid_s == guest_id:
            skipped_guest += 1
            continue
        if pts == 0:
            continue
        total[uid_s] += pts
        code = subj_code.get(sid)
        if code:
            by_subject[(code, uid_s)] += pts
        region = user_region.get(uid_s)
        if region:
            by_region[(region, uid_s)] += pts

    print(f"hisoblandi: {len(total)} user, {len(by_subject)} subject-entry, "
          f"{len(by_region)} region-entry (guest satrlar: {skipped_guest})")

    if dry:
        top = sorted(total.items(), key=lambda kv: -kv[1])[:10]
        print("\nTOP 10 (lb:total bo'ladigan):")
        for i, (uid, pts) in enumerate(top, 1):
            print(f"  {i:>2}. {uid}  {pts}")
        print("\nDRY-RUN: Redis'ga hech narsa yozilmadi.")
        return 0

    redis = get_redis()
    try:
        boards: dict[str, dict[str, int]] = {ranking.TOTAL_KEY: dict(total)}
        for (code, uid), pts in by_subject.items():
            boards.setdefault(ranking.subject_key(code), {})[uid] = pts
        for (region, uid), pts in by_region.items():
            boards.setdefault(ranking.region_key(region), {})[uid] = pts

        for key, mapping in boards.items():
            tmp = key + ":rebuild"
            await redis.delete(tmp)
            if mapping:
                items = list(mapping.items())
                for i in range(0, len(items), 500):
                    await redis.zadd(tmp, dict(items[i:i + 500]))
                await redis.rename(tmp, key)      # atomar almashtirish
            else:
                await redis.delete(key)
            print(f"  {key}: {len(mapping)} entry")
        print("\nREBUILD tayyor.")
    finally:
        await close_redis()
    return 0

if __name__ == "__main__":
    raise SystemExit(asyncio.run(main("--dry-run" in sys.argv)))
