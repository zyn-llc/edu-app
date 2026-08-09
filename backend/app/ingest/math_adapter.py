"""
Math ingest adapter — numeric open-type questions in Zizu's two-layer format.

Differences from the geography layers (verified against real math_11 samples):
  * core rows carry the grading key inline: type "numeric", `value`, `tolerance`
    (geography carried `correct_option_id` instead)
  * the uz layer is keyed by `id` (geography's uz layer used `question_id`) and
    has NO `lang` field and NO options — just question_text + explanation
  * `max_score` is explicit in core

Produces the same IngestQuestion the geography writer consumes, so run_math.py
is a thin runner over the shared upsert. LaTeX in stems ($...$) is stored
verbatim — rendering is the client's job (flutter_math_fork), the DB stays
presentation-agnostic.

Key hygiene (mirrors the digitization conventions): grading keys are copied
authentically from core — value/tolerance are NEVER inferred or "fixed" here.
A core row missing `value` is a defect: it is reported and skipped, not guessed.
"""
from __future__ import annotations

from app.ingest.geography_adapter import IngestQuestion

SUBJECT_CODE_MAP = {
    "Mathematics": "matematika",
    "Math": "matematika",
}


def join_math_layers(core: list[dict], uz: list[dict]) -> tuple[list[IngestQuestion], list[str]]:
    """Join core[] and uz[] on id. Returns (items, defects). Defects are ids
    that cannot be ingested truthfully (missing key / missing uz text)."""
    uz_by_id = {row["id"]: row for row in uz}

    items: list[IngestQuestion] = []
    defects: list[str] = []
    for c in core:
        cid = c["id"]
        u = uz_by_id.get(cid)
        if u is None or not (u.get("question_text") or "").strip():
            defects.append(f"{cid}: no uz question_text")
            continue
        if c.get("type") != "numeric":
            defects.append(f"{cid}: unsupported type {c.get('type')!r} for math adapter")
            continue
        if "value" not in c:
            defects.append(f"{cid}: core has no `value` (authentic keys only — not inferring)")
            continue

        subject_code = SUBJECT_CODE_MAP.get(c.get("subject", ""), None)
        if subject_code is None:
            defects.append(f"{cid}: unknown subject {c.get('subject')!r}")
            continue

        grading_spec = {"value": c["value"]}
        if "tolerance" in c:
            grading_spec["tolerance"] = c["tolerance"]

        items.append(IngestQuestion(
            source_id=cid,
            type="numeric",
            subject_code=subject_code,
            topic_code=c.get("topic"),
            grade=c.get("grade"),
            exam_context=c.get("exam_context") or [],
            tags={
                "skill_tags": c.get("skill_tags") or [],
                "concept_tags": c.get("concept_tags") or [],
                "subtopic": c.get("subtopic"),
            },
            grading_spec=grading_spec,
            stems={"uz-Latn": u["question_text"]},
            explanations={"uz-Latn": u.get("explanation")} if u.get("explanation") else {},
            options=[],
        ))
    return items, defects
