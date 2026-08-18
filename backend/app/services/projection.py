from __future__ import annotations

from app.models import Question as QuestionORM
from app.schemas.question import (
    GradingQuestion, PublicOption, PublicQuestion, QuestionType,
)


def _resolve(translations, lang: str, fallback: str, attr: str) -> str | None:
    by_lang = {t.lang: getattr(t, attr) for t in translations}
    return by_lang.get(lang) or by_lang.get(fallback) or next(iter(by_lang.values()), None)


def to_public(q: QuestionORM, lang: str, fallback: str = "uz-Latn") -> PublicQuestion:
    options = [
        PublicOption(
            option_key=o.option_key,
            position=o.position,
            side=o.side,
            media_url=o.media_url,
            text=_resolve(o.translations, lang, fallback, "text"),
        )
        for o in sorted(q.options, key=lambda x: x.position)
    ]
    return PublicQuestion(
        id=str(q.id),
        type=QuestionType(q.type),
        subject_id=str(q.subject_id),
        topic_id=str(q.topic_id) if q.topic_id else None,
        grade=q.grade,
        exam_context=q.exam_context or [],
        difficulty=q.difficulty,
        max_score=q.max_score,
        stem=_resolve(q.translations, lang, fallback, "stem") or "",
        media=q.media,
        options=options,
    )


def to_grading(q: QuestionORM) -> GradingQuestion:
    return GradingQuestion(
        id=str(q.id),
        type=QuestionType(q.type),
        max_score=q.max_score,
        grading_spec=q.grading_spec,
    )
