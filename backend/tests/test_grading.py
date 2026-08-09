"""Grading tests — prove MCQ works today and that 'later' types already work."""
import pytest

from app.schemas.question import GradingQuestion, QuestionType, SubmissionIn
from app.services import grading


def _q(qtype, spec, max_score=1):
    return GradingQuestion(id="q1", type=qtype, max_score=max_score, grading_spec=spec)


def _s(payload):
    return SubmissionIn(question_id="q1", payload=payload)


# ---- MCQ (ships today) ----------------------------------------------------- #
def test_mcq_correct():
    q = _q(QuestionType.mcq, {"correct_option_ids": ["b"]})
    r = grading.grade(q, _s({"option_ids": ["b"]}))
    assert r.is_correct and r.score == 1 and r.max_score == 1


def test_mcq_incorrect_reveals_nothing():
    q = _q(QuestionType.mcq, {"correct_option_ids": ["b"]})
    r = grading.grade(q, _s({"option_ids": ["a"]}))
    assert not r.is_correct and r.score == 0
    # result must not contain the correct answer anywhere
    assert "b" not in r.model_dump_json()


# ---- multi_select ---------------------------------------------------------- #
def test_multi_select_exact_set():
    q = _q(QuestionType.multi_select, {"correct_option_ids": ["a", "c"]})
    assert grading.grade(q, _s({"option_ids": ["c", "a"]})).is_correct
    assert not grading.grade(q, _s({"option_ids": ["a"]})).is_correct


# ---- numeric --------------------------------------------------------------- #
def test_numeric_within_tolerance():
    q = _q(QuestionType.numeric, {"value": 3.14, "tolerance": 0.01})
    assert grading.grade(q, _s({"value": 3.145})).is_correct
    assert not grading.grade(q, _s({"value": 3.2})).is_correct


# ---- open_keyword: Uzbek Latin <-> Cyrillic must both count as correct ----- #
def test_keyword_latin_and_cyrillic_equivalent():
    q = _q(QuestionType.open_keyword, {"accepted": ["Toshkent"]})
    assert grading.grade(q, _s({"text": "toshkent"})).is_correct
    assert grading.grade(q, _s({"text": "Тошкент"})).is_correct   # Cyrillic
    assert not grading.grade(q, _s({"text": "Samarqand"})).is_correct


# ---- matching -------------------------------------------------------------- #
def test_matching_pairs():
    q = _q(QuestionType.matching, {"pairs": [["L1", "R2"], ["L2", "R1"]]})
    assert grading.grade(q, _s({"pairs": [["L2", "R1"], ["L1", "R2"]]})).is_correct
    assert not grading.grade(q, _s({"pairs": [["L1", "R1"], ["L2", "R2"]]})).is_correct


# ---- open_text has no grader, and says so clearly --------------------------- #
def test_open_text_has_no_grader():
    """Ro'yxatdan o'tmagan tur — `GradingError`. Ilgari bu yerda faqat
    `NotImplementedError` ko'taradigan soxta grader ro'yxatdan o'tgan edi va
    registry to'liqdek ko'rinardi."""
    q = _q(QuestionType.open_text, {"rubric": "..."})
    with pytest.raises(grading.GradingError):
        grading.grade(q, _s({"text": "essay"}))


# ---- Numeric input parsing (math content is open-type: students TYPE answers) --
def test_numeric_comma_decimal():
    q = _q(QuestionType.numeric, {"value": 0.5, "tolerance": 0.001})
    assert grading.grade(q, _s({"value": "0,5"})).is_correct


def test_numeric_fraction_beats_truncated_key():
    # Key stored as truncated decimal (0.33333, tol 0.001): a student who types
    # the EXACT answer "1/3" must pass — this is the real math_11 data shape.
    q = _q(QuestionType.numeric, {"value": 0.33333, "tolerance": 0.001})
    assert grading.grade(q, _s({"value": "1/3"})).is_correct
    assert grading.grade(q, _s({"value": "-1/3"})).is_correct is False


def test_numeric_unicode_minus_and_spaces():
    q = _q(QuestionType.numeric, {"value": -2.0, "tolerance": 0.0})
    assert grading.grade(q, _s({"value": "\u22122"})).is_correct
    assert grading.grade(q, _s({"value": " -2 "})).is_correct


def test_numeric_garbage_is_wrong_not_500():
    q = _q(QuestionType.numeric, {"value": 1.0, "tolerance": 0.0})
    for bad in ["abc", "1/0", "", None, "1+1", {"x": 1}]:
        assert grading.grade(q, _s({"value": bad})).is_correct is False
