"""Math adapter tests — real math_11 data shape, defect-not-guess convention."""
from app.ingest.math_adapter import join_math_layers

CORE = [
    {"id": "math_11_q1298", "type": "numeric", "subject": "Mathematics",
     "topic": "yuza_integral", "subtopic": "egri_trapetsiya", "grade": 11,
     "difficulty": 3, "exam_context": ["school", "entrance"],
     "skill_tags": ["integration"], "concept_tags": ["area_under_curve"],
     "max_score": 1, "value": 0.33333, "tolerance": 0.001},
    {"id": "math_11_q9999", "type": "numeric", "subject": "Mathematics",
     "topic": "t", "grade": 11},                          # missing value -> defect
    {"id": "math_11_q9998", "type": "mcq", "subject": "Mathematics",
     "topic": "t", "grade": 11, "value": 1},              # wrong type -> defect
]
UZ = [
    {"id": "math_11_q1298",
     "question_text": "Egri chiziqli trapetsiyaning yuzini toping: $y=(x-1)^2$ ...",
     "explanation": "To'g'ri javob — yuza $\\dfrac{1}{3}$."},
    {"id": "math_11_q9999", "question_text": "x"},
    {"id": "math_11_q9998", "question_text": "x"},
]


def test_join_produces_numeric_grading_spec():
    items, defects = join_math_layers(CORE, UZ)
    assert len(items) == 1
    it = items[0]
    assert it.grading_spec == {"value": 0.33333, "tolerance": 0.001}
    assert it.subject_code == "matematika"
    assert it.stems["uz-Latn"].startswith("Egri")
    assert "$" in it.stems["uz-Latn"]           # LaTeX passes through verbatim
    assert it.options == []
    assert it.tags["subtopic"] == "egri_trapetsiya"


def test_defects_reported_never_guessed():
    items, defects = join_math_layers(CORE, UZ)
    assert len(defects) == 2
    assert any("q9999" in d and "value" in d for d in defects)
    assert any("q9998" in d and "type" in d for d in defects)


def test_missing_uz_text_is_defect():
    items, defects = join_math_layers(
        [CORE[0]], [{"id": "math_11_q1298", "question_text": "  "}])
    assert items == [] and len(defects) == 1
