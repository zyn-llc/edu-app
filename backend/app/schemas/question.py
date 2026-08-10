"""
The public / grading projection split — the structural guarantee that answer keys
cannot leak.

  * PublicOption / PublicQuestion  -> what a client may ever see. There is NO field
    on these models that can hold correctness. Serializing them cannot leak a key.

  * GradingQuestion                -> server-only. Carries grading_spec. It is never
    used as a response model anywhere in the API. Anything that loads it lives behind
    the trust boundary.

If you ever need to return question data to a client, you return PublicQuestion.
Because the public model has no answer field, leaking is impossible by construction,
not by remembering to strip a field.
"""
from __future__ import annotations
from enum import Enum
from typing import Any, Literal
from pydantic import BaseModel, Field

class QuestionType(str, Enum):
    mcq = "mcq"
    multi_select = "multi_select"
    numeric = "numeric"
    open_keyword = "open_keyword"
    matching = "matching"
    ordering = "ordering"
    open_text = "open_text"

# --------------------------------------------------------------------------- #
#  PUBLIC projection — safe to serialize to any client                         #
# --------------------------------------------------------------------------- #
class PublicOption(BaseModel):
    option_key: str
    position: int = 0
    side: str | None = None          # 'left'/'right' for matching
    text: str | None = None          # resolved for the requested language
    media_url: str | None = None
    # NOTE: intentionally no `is_correct`. The model cannot carry a key.

class PublicQuestion(BaseModel):
    id: str
    type: QuestionType
    subject_id: str
    topic_id: str | None = None
    grade: int | None = None
    exam_context: list[str] = Field(default_factory=list)
    difficulty: int = 2
    max_score: int = 1
    stem: str                        # resolved for requested language
    media: dict[str, Any] | None = None
    options: list[PublicOption] = Field(default_factory=list)
    # NOTE: no explanation, no grading_spec, no correct flag — ever.

class GradingQuestion(BaseModel):
    id: str
    type: QuestionType
    max_score: int = 1
    grading_spec: dict[str, Any]     # *** answer key lives here, server-side ***

# --------------------------------------------------------------------------- #
#  Submission + result                                                         #
# --------------------------------------------------------------------------- #
class SubmissionIn(BaseModel):
    """Whatever the student sends. Shape depends on question type.

    mcq          : {"option_ids": ["a"]}
    multi_select : {"option_ids": ["a","c"]}
    numeric      : {"value": 3.14}
    open_keyword : {"text": "Toshkent"}
    matching     : {"pairs": [["L1","R2"], ["L2","R1"]]}
    ordering     : {"order": ["B","A","C"]}
    """
    question_id: str
    payload: dict[str, Any]
    response_ms: int | None = None

class GradeResult(BaseModel):
    question_id: str
    is_correct: bool
    score: int
    max_score: int
    # Returned ONLY after the student submits (in the grade response), so they can
    # see the right answer and the explanation. Never present on PublicQuestion.
    correct_option_ids: list[str] = Field(default_factory=list)
    explanation: str | None = None
    xp_awarded: int = 0
    coins_awarded: int = 0
    coins_delta: int = 0
    reward_reason: str | None = None   # guest | repeat | wrong | ok
