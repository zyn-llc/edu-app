"""
The leak-proof test. If someone later adds a 'correct' field to PublicQuestion,
this test fails loudly. The guarantee is structural, and this locks it in.
"""
import json

from app.schemas.question import PublicQuestion, PublicOption, QuestionType

FORBIDDEN_KEYS = {
    "is_correct", "correct", "correct_option_ids", "answer", "answer_key",
    "grading_spec", "explanation_key",
}


def _walk_keys(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield k
            yield from _walk_keys(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _walk_keys(v)


def test_public_question_has_no_answer_fields():
    q = PublicQuestion(
        id="q1",
        type=QuestionType.mcq,
        subject_id="s1",
        stem="Poytaxt qayer?",
        options=[
            PublicOption(option_key="a", text="Samarqand"),
            PublicOption(option_key="b", text="Toshkent"),
        ],
    )
    data = json.loads(q.model_dump_json())
    present = set(_walk_keys(data))
    leaked = present & FORBIDDEN_KEYS
    assert not leaked, f"public projection leaked answer fields: {leaked}"


def test_public_option_model_cannot_hold_correctness():
    # The model itself must not even define a correctness field.
    assert "is_correct" not in PublicOption.model_fields
    assert "correct" not in PublicOption.model_fields
