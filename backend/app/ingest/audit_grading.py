#!/usr/bin/env python3
"""
audit_grading.py - read-only integrity audit of loaded questions.

Catches: grading_spec.correct_option_ids that do NOT match the real option_key
values (e.g. old loader stored 'opt_a' while options are keyed 'a') -> such a
question marks every attempt wrong.

  PYTHONPATH=. python -m app.ingest.audit_grading

Connection: uses DATABASE_URL if set, else app settings. Rewrites the docker
service host 'db' -> 127.0.0.1 when running from the host, and disables SSL for
local connections (Windows/Docker port-proxy drops asyncpg's SSL negotiation).
Exit 0 if clean, 1 if any problem. Writes nothing.
"""
from __future__ import annotations
import asyncio, os, re
from collections import defaultdict


def resolve_url() -> str:
    # Almashtirish mantig'i `app/ingest/dsn.py` da — u konteyner ichida
    # ekanligini tekshiradi. Ilgari bu yerda shartsiz `@db:` -> `@127.0.0.1:`
    # turardi va `docker compose exec api ...` da skript o'z konteynerining
    # loopback'iga ulanmoqchi bo'lib yiqilardi.
    from app.ingest.dsn import resolve_url as _resolve
    return _resolve()


async def main() -> int:
    from sqlalchemy import select
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
    from app.models import Option, Question

    url = resolve_url()
    engine = create_async_engine(url, pool_pre_ping=True)
    Session = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with Session() as db:
            q_opts: dict = defaultdict(set)
            for qid, key in (await db.execute(
                    select(Option.question_id, Option.option_key))).all():
                q_opts[qid].add(key)

            rows = (await db.execute(select(
                Question.id, Question.type, Question.grading_spec,
                Question.source_ref))).all()
    except Exception as e:
        print("!! DB ULANMADI:", type(e).__name__, str(e)[:200])
        print("   URL:", url)
        print("   Diagnostika:  python -m app.ingest.db_check")
        await engine.dispose()
        return 1
    finally:
        await engine.dispose()

    # Har turning o'z grading_spec shakli bor. Ilgari bu funksiya faqat
    # `correct_option_ids` ni bilardi va `numeric` / `open_keyword` savollarni
    # "empty correct_option_ids" deb noto'g'ri belgilardi.
    #
    # Tekshiruv `services/grading.py` dagi graderlar HAQIQATAN o'qiydigan
    # maydonlarga qarab yozilgan — ikkisi bir-biriga mos bo'lishi shart.
    bad = []
    by_type = defaultdict(int)
    for qid, qtype, spec, src in rows:
        by_type[qtype] += 1
        keys = q_opts.get(qid, set())
        spec = spec or {}

        if qtype in ("mcq", "multi_select"):
            correct = list(spec.get("correct_option_ids", []))
            if qtype == "mcq" and len(correct) != 1:
                bad.append((src, qtype, "mcq needs exactly 1 correct, has "
                            + str(len(correct)), correct, sorted(keys)))
                continue
            if not correct:
                bad.append((src, qtype, "empty correct_option_ids", correct, sorted(keys)))
                continue
            missing = [c for c in correct if c not in keys]
            if missing:
                bad.append((src, qtype, "correct id(s) " + str(missing)
                            + " not in option_keys", correct, sorted(keys)))

        elif qtype == "numeric":
            # `_grade_numeric` float(spec["value"]) va float(spec["tolerance"]) o'qiydi.
            if "value" not in spec:
                bad.append((src, qtype, "numeric: 'value' yo'q", [], []))
                continue
            try:
                float(spec["value"])
                float(spec.get("tolerance", 0.0))
            except (TypeError, ValueError):
                bad.append((src, qtype, "numeric: value/tolerance son emas",
                            [str(spec.get("value")), str(spec.get("tolerance"))], []))

        elif qtype == "open_keyword":
            # `_grade_keyword` spec["accepted"] ro'yxatini o'qiydi.
            acc = spec.get("accepted")
            if not isinstance(acc, list) or not [a for a in acc if str(a).strip()]:
                bad.append((src, qtype, "open_keyword: 'accepted' bo'sh yoki ro'yxat emas",
                            acc if isinstance(acc, list) else [str(acc)], []))

        elif qtype == "matching":
            if not spec.get("pairs"):
                bad.append((src, qtype, "matching: 'pairs' bo'sh", [], []))

        elif qtype == "ordering":
            if not spec.get("order"):
                bad.append((src, qtype, "ordering: 'order' bo'sh", [], []))

        elif qtype == "open_text":
            # AI-rubric bilan baholanadi (phase 4) — hali grader yo'q.
            bad.append((src, qtype, "open_text graderi hali yozilmagan "
                        "(phase 4) — status='draft' bo'lishi kerak", [], []))

        else:
            bad.append((src, qtype, "noma'lum tur — grader ro'yxatdan o'tmagan",
                        [], sorted(keys)))

    print("audited", len(rows), "question(s);", len(bad), "problem(s)")
    print("  turlar bo'yicha: "
          + ", ".join(f"{t}={n}" for t, n in sorted(by_type.items(),
                                                    key=lambda kv: -kv[1])))
    for src, qtype, why, correct, keys in bad[:100]:
        print("  BAD", src, "[" + str(qtype) + "]:", why, "spec=", correct, "keys=", keys)
    if len(bad) > 100:
        print("  ... +", len(bad) - 100, "more")
    if bad:
        print("RESULT: grading integrity FAILED - fix before launch.")
        return 1
    print("RESULT: all grading_spec consistent with options.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))