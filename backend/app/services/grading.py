"""
GradingService — the single server-authoritative judge.

Dispatches on question.type. Adding a future type = add one branch + register it;
no change to callers, no change to the schema. MCQ is the type you ship today; the
others are implemented here too (they are cheap and prove the architecture handles
"later" types — matching, numeric, keyword — without a rewrite). open_text/AI-rubric
is the one genuine stub, because it needs an LLM call.

The grader reads GradingQuestion (server-only) and the student's payload, and returns
a GradeResult. It NEVER puts the correct answer in that result.

The key IS released — but only by the caller, only on a correct answer, and only in
one place: api/v1/content.submit. That single `if result.is_correct:` is the whole
disclosure policy; if you need to change it, change it there, not here.
"""
from __future__ import annotations
from typing import Callable

from app.schemas.question import (
    GradingQuestion,
    GradeResult,
    QuestionType,
    SubmissionIn,
)
from app.services.normalizer import normalize


class GradingError(Exception):
    """Malformed submission or grading_spec."""


# Registry: type -> grader(question, payload) -> bool(correct)
_GRADERS: dict[QuestionType, Callable[[GradingQuestion, dict], bool]] = {}


def _register(qtype: QuestionType):
    def deco(fn):
        _GRADERS[qtype] = fn
        return fn
    return deco


# --------------------------------------------------------------------------- #
#  Implemented today                                                          #
# --------------------------------------------------------------------------- #
@_register(QuestionType.mcq)
def _grade_mcq(q: GradingQuestion, payload: dict) -> bool:
    correct = set(q.grading_spec.get("correct_option_ids", []))
    if len(correct) != 1:
        raise GradingError("mcq grading_spec must have exactly one correct option")
    submitted = payload.get("option_ids", [])
    return len(submitted) == 1 and submitted[0] in correct


@_register(QuestionType.multi_select)
def _grade_multi_select(q: GradingQuestion, payload: dict) -> bool:
    correct = set(q.grading_spec.get("correct_option_ids", []))
    submitted = set(payload.get("option_ids", []))
    return submitted == correct and len(correct) > 0


def _parse_student_number(raw) -> float:
    """Parse a student's numeric answer the way they actually type it.

    Handles: plain numbers (int/float payloads pass through), comma decimals
    ("0,5" — the Uzbek/Russian convention), simple fractions ("1/3", "-16/3"),
    Unicode minus ("−2"), and stray whitespace. Anything else raises ValueError
    (graded as wrong upstream). Deliberately NOT an expression evaluator — no
    eval, no "4ln2"; keys must be stored as decimal value+tolerance, and the
    fraction form covers the exact-answer cases like 1/3 that a truncated
    decimal key would otherwise fail on tolerance.
    """
    if isinstance(raw, (int, float)) and not isinstance(raw, bool):
        return float(raw)
    s = str(raw).strip().replace("\u2212", "-").replace(" ", "")
    s = s.replace(",", ".")
    if "/" in s:
        num, _, den = s.partition("/")
        d = float(den)
        if d == 0:
            raise ValueError("division by zero")
        return float(num) / d
    return float(s)


@_register(QuestionType.numeric)
def _grade_numeric(q: GradingQuestion, payload: dict) -> bool:
    spec = q.grading_spec
    try:
        target = float(spec["value"])
        tol = float(spec.get("tolerance", 0.0))
    except (KeyError, TypeError, ValueError) as e:
        raise GradingError(f"numeric grading failed: {e}")
    try:
        given = _parse_student_number(payload["value"])
    except (KeyError, TypeError, ValueError, ZeroDivisionError):
        return False        # unparseable student input = wrong, never a 500
    return abs(given - target) <= tol


@_register(QuestionType.open_keyword)
def _grade_keyword(q: GradingQuestion, payload: dict) -> bool:
    accepted = [normalize(a) for a in q.grading_spec.get("accepted", [])]
    given = normalize(payload.get("text", ""))
    if not given:
        return False
    # 'any' (default): student answer matches at least one accepted form.
    return given in accepted


@_register(QuestionType.matching)
def _grade_matching(q: GradingQuestion, payload: dict) -> bool:
    correct = {tuple(p) for p in q.grading_spec.get("pairs", [])}
    submitted = {tuple(p) for p in payload.get("pairs", [])}
    return submitted == correct and len(correct) > 0


@_register(QuestionType.ordering)
def _grade_ordering(q: GradingQuestion, payload: dict) -> bool:
    correct = list(q.grading_spec.get("order", []))
    submitted = list(payload.get("order", []))
    return submitted == correct and len(correct) > 0


# NOTE: `open_text` has NO grader and is not registered here. It needs an LLM
# rubric call, which does not exist yet. A registered function that only raises
# would make this registry look complete when it is not — `grade()` below
# already reports an unregistered type clearly, and `ingest/audit_grading.py`
# refuses to publish such questions in the first place.


# --------------------------------------------------------------------------- #
#  Public entrypoint                                                          #
# --------------------------------------------------------------------------- #
def grade(question: GradingQuestion, submission: SubmissionIn) -> GradeResult:
    grader = _GRADERS.get(question.type)
    if grader is None:
        raise GradingError(f"no grader registered for type {question.type}")
    is_correct = grader(question, submission.payload)
    return GradeResult(
        question_id=question.id,
        is_correct=is_correct,
        score=question.max_score if is_correct else 0,
        max_score=question.max_score,
    )
