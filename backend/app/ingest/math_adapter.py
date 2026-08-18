from __future__ import annotations

from app.ingest.geography_adapter import IngestQuestion

SUBJECT_CODE_MAP = {
    "Mathematics": "matematika",
    "Math": "matematika",
}


def join_math_layers(core: list[dict], uz: list[dict]) -> tuple[list[IngestQuestion], list[str]]:

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
