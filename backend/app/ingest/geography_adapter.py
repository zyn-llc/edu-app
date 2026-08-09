"""
Geography ingest adapter — matches YOUR real two-file format.

Your dataset is two parallel JSON arrays per topic:

  core[]  (language-neutral)        uz[]  (Uzbek content)
  ----------------------------      --------------------------------
  id            geo_g6_q721         question_id   geo_g6_q721
  type          mcq                 lang          uz
  subject       Geography           question_text "..."
  topic         materik_...         options       [{id:opt_a,text:..}, ...]
  subtopic      history_of_geo      explanation   "..."
  difficulty    2                   seq           1
  grade         6
  exam_context  [school, entrance]
  skill_tags    [recall]
  concept_tags  [geography_scientists]
  correct_option_id  opt_a
  seq / status / created_at

This adapter joins the two layers on id == question_id and produces a
source-shape-agnostic IngestQuestion. The DB writer (run_geography.py) consumes it.

Mapping into the canonical schema:
  core.subject "Geography"  -> subjects.code 'geografiya'   (SUBJECT_CODE_MAP)
  core.topic                -> topics.code (auto-created per distinct value)
  core.correct_option_id    -> questions.grading_spec {"correct_option_ids": [...]}
  core.exam_context (array) -> questions.exam_context  text[]
  core.{skill,concept}_tags -> questions.tags (jsonb)
  uz.question_text          -> question_translations.stem   (lang 'uz' -> 'uz-Latn')
  uz.options[*].text        -> option_translations.text     (option_key = opt id)
  uz.explanation            -> question_translations.explanation
"""
from __future__ import annotations
from dataclasses import dataclass, field

# Your data labels the subject "Geography"; canonical slug is 'geografiya'.
SUBJECT_CODE_MAP = {
    "geography": "geografiya",
    "jahon tarixi": "jahon_tarixi",
    "world history": "jahon_tarixi",
    "o'zbekiston tarixi": "ozbekiston_tarixi",
    "mathematics": "matematika",
    "geometry": "geometriya",
    "physics": "fizika",
    "chemistry": "kimyo",
    "biology": "biologiya",
}

# Your content lang tag is "uz" (Uzbek Latin in the source).
LANG_MAP = {"uz": "uz-Latn", "uz-cyrl": "uz-Cyrl", "ru": "ru", "en": "en"}


@dataclass
class IngestOption:
    option_key: str
    position: int
    texts: dict[str, str]                  # lang -> text


@dataclass
class IngestQuestion:
    source_id: str
    type: str
    subject_code: str
    topic_code: str | None
    grade: int | None
    exam_context: list[str]
    tags: dict
    grading_spec: dict
    stems: dict[str, str]                  # lang -> stem
    explanations: dict[str, str]           # lang -> explanation
    options: list[IngestOption] = field(default_factory=list)


def join_layers(core: list[dict], langs: list[list[dict]]) -> list[IngestQuestion]:
    """core: the core[] array. langs: one or more uz[]/ru[]/... arrays."""
    # index language rows by (question_id, lang)
    by_qid: dict[str, dict[str, dict]] = {}
    for arr in langs:
        for row in arr:
            qid = row["question_id"]
            lang = LANG_MAP.get(row.get("lang", "uz"), row.get("lang", "uz"))
            by_qid.setdefault(qid, {})[lang] = row

    out: list[IngestQuestion] = []
    for c in core:
        qid = c["id"]
        langrows = by_qid.get(qid, {})
        if not langrows:
            continue  # no content for this id yet

        # options come from the first available language row's options[]
        any_lang = next(iter(langrows))
        opt_ids = [o["id"] for o in langrows[any_lang]["options"]]
        options = []
        for pos, oid in enumerate(opt_ids):
            texts = {}
            for lang, row in langrows.items():
                opt = next((o for o in row["options"] if o["id"] == oid), None)
                if opt:
                    texts[lang] = opt["text"]
            options.append(IngestOption(option_key=oid, position=pos, texts=texts))

        qtype = c.get("type", "mcq")
        if qtype == "mcq":
            grading_spec = {"correct_option_ids": [c["correct_option_id"]]}
        elif qtype == "multi_select":
            grading_spec = {"correct_option_ids": c["correct_option_ids"]}
        else:
            # open/numeric/ai types carry a 'grading' block already (phase 4)
            grading_spec = c.get("grading", {})

        subj = SUBJECT_CODE_MAP.get(str(c.get("subject", "")).lower(),
                                    str(c.get("subject", "")).lower())

        out.append(IngestQuestion(
            source_id=qid,
            type=qtype,
            subject_code=subj,
            topic_code=c.get("topic"),
            grade=c.get("grade"),
            exam_context=c.get("exam_context") or [],
            tags={
                "skill_tags": c.get("skill_tags", []),
                "concept_tags": c.get("concept_tags", []),
                "subtopic": c.get("subtopic"),
            },
            grading_spec=grading_spec,
            stems={lang: row["question_text"] for lang, row in langrows.items()},
            explanations={lang: row.get("explanation", "")
                          for lang, row in langrows.items()},
            options=options,
        ))
    return out
