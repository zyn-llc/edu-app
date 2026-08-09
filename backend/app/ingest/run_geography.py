"""
Geography ingest runner.

Usage:
    PYTHONPATH=. python -m app.ingest.run_geography \
        app/ingest/sample_data/geo_core.json \
        app/ingest/sample_data/geo_uz.json

Reads your two-file core+uz arrays, joins them, and upserts into the canonical
schema. Idempotent on question source_ref (re-running won't duplicate). Topics
are auto-created per distinct topic code within the subject.
"""
from __future__ import annotations
import asyncio
import json
import sys

from sqlalchemy import select

from app.core.database import SessionLocal
from app.ingest.geography_adapter import join_layers
from app.models import (
    Option, OptionTranslation, Question, QuestionTranslation, Subject, Topic,
    TopicTranslation,
)


async def _get_subject_id(db, code: str):
    sid = (await db.execute(
        select(Subject.id).where(Subject.code == code)
    )).scalar_one_or_none()
    if sid is None:
        raise SystemExit(f"subject '{code}' not seeded — run sql/002_seed.sql first")
    return sid


async def _get_or_create_topic(db, subject_id, code: str, cache: dict):
    if code in cache:
        return cache[code]
    tid = (await db.execute(
        select(Topic.id).where(Topic.subject_id == subject_id, Topic.code == code)
    )).scalar_one_or_none()
    if tid is None:
        t = Topic(subject_id=subject_id, code=code)
        db.add(t)
        await db.flush()
        tid = t.id
        # Provide a readable uz-Latn title from the code until real titles arrive.
        title = code.replace("_", " ").strip().capitalize()
        db.add(TopicTranslation(topic_id=tid, lang="uz-Latn", title=title))
    cache[code] = tid
    return tid


async def run(core_path: str, uz_path: str):
    core = json.load(open(core_path, encoding="utf-8"))
    uz = json.load(open(uz_path, encoding="utf-8"))
    items = join_layers(core, [uz])

    inserted, skipped = 0, 0
    async with SessionLocal() as db:
        topic_cache: dict[str, object] = {}
        for it in items:
            subject_id = await _get_subject_id(db, it.subject_code)

            exists = (await db.execute(
                select(Question.id).where(Question.source_ref == it.source_id)
            )).scalar_one_or_none()
            if exists:
                skipped += 1
                continue

            topic_id = None
            if it.topic_code:
                topic_id = await _get_or_create_topic(
                    db, subject_id, it.topic_code, topic_cache)

            q = Question(
                subject_id=subject_id,
                topic_id=topic_id,
                grade=it.grade,
                exam_context=it.exam_context or None,
                type=it.type,
                grading_spec=it.grading_spec,     # *** server-only key ***
                tags=it.tags,
                source_ref=it.source_id,
            )
            db.add(q)
            await db.flush()

            for lang, stem in it.stems.items():
                db.add(QuestionTranslation(
                    question_id=q.id, lang=lang, stem=stem,
                    explanation=it.explanations.get(lang)))

            for opt in it.options:
                o = Option(question_id=q.id, option_key=opt.option_key,
                           position=opt.position)
                db.add(o)
                await db.flush()
                for lang, text in opt.texts.items():
                    db.add(OptionTranslation(option_id=o.id, lang=lang, text=text))

            inserted += 1
        await db.commit()

    print(f"ingest done: inserted={inserted} skipped(existing)={skipped} "
          f"total_items={len(items)}")


if __name__ == "__main__":
    asyncio.run(run(sys.argv[1], sys.argv[2]))
