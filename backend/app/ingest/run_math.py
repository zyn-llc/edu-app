"""
Math ingest runner.

Usage (files can live anywhere the container sees, e.g. docker cp to /tmp):
    PYTHONPATH=. python -m app.ingest.run_math math_11_core.json math_11_uz.json

Prerequisite: subject 'matematika' seeded (see GUIDES.md §3.1).
Idempotent on source_ref — re-running never duplicates. Defective rows (missing
key / missing text) are reported and skipped, never guessed — same convention
as the digitization pipeline.
"""
from __future__ import annotations
import asyncio
import json
import sys

from sqlalchemy import select

from app.core.database import SessionLocal
from app.ingest.math_adapter import join_math_layers
from app.ingest.run_geography import _get_or_create_topic, _get_subject_id
from app.models import Question, QuestionTranslation


async def run(core_path: str, uz_path: str):
    core = json.load(open(core_path, encoding="utf-8"))
    uz = json.load(open(uz_path, encoding="utf-8"))
    items, defects = join_math_layers(core, uz)

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
                grading_spec=it.grading_spec,      # *** server-only key ***
                tags=it.tags,
                source_ref=it.source_id,
            )
            db.add(q)
            await db.flush()

            for lang, stem in it.stems.items():
                db.add(QuestionTranslation(
                    question_id=q.id, lang=lang, stem=stem,
                    explanation=it.explanations.get(lang)))
            inserted += 1
        await db.commit()

    print(f"math ingest done: inserted={inserted} skipped(existing)={skipped} "
          f"defects={len(defects)}")
    for d in defects[:50]:
        print("  DEFECT", d)
    if len(defects) > 50:
        print(f"  ... and {len(defects) - 50} more")


if __name__ == "__main__":
    asyncio.run(run(sys.argv[1], sys.argv[2]))
