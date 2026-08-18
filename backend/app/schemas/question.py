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


class PublicOption(BaseModel):
    option_key: str
    position: int = 0
    side: str | None = None          
    text: str | None = None          
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
    stem: str                       
    media: dict[str, Any] | None = None
    options: list[PublicOption] = Field(default_factory=list)
   

class GradingQuestion(BaseModel):
    id: str
    type: QuestionType
    max_score: int = 1
    grading_spec: dict[str, Any]    


class SubmissionIn(BaseModel):
 

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
   
    correct_option_ids: list[str] = Field(default_factory=list)
    explanation: str | None = None
    xp_awarded: int = 0
    coins_awarded: int = 0
    coins_delta: int = 0
    reward_reason: str | None = None   # guest | repeat | wrong | ok
