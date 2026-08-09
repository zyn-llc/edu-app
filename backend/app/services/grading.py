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
import ast
import math
import re
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


# --------------------------------------------------------------------------- #
#  Sonli javob: matematik ifodani baholash                                     #
#                                                                              #
#  Ilova javob maydoni ostida beshta tugma ko'rsatadi: a/b, √, π, x², ( ).
#  Ulardan faqat BIRINCHISI ishlardi — qolganlari grader tushunmaydigan belgi
#  qo'yardi, `float("π/2")` ValueError berardi va javob NOTO'G'RI deb
#  baholanardi. Ya'ni javobni bilgan o'quvchi ilova o'zi taklif qilgan
#  tugmani bosgani uchun jazolanardi.
#
#  NEGA `eval` EMAS. U foydalanuvchi yuborgan satrni bajaradi va serverni
#  ochib qo'yadi. Bu yerda satr `ast` bilan daraxtga aylantiriladi va daraxt
#  OQ RO'YXAT bo'yicha tekshiriladi: faqat son, `pi`, `sqrt`, to'rt amal,
#  daraja va unar minus. Nom, chaqiruv, indeks, atribut — rad etiladi.
#
#  CHEGARALAR: `9**9**9` serverni osib qo'yadi, shuning uchun daraja
#  ko'rsatkichi, satr uzunligi va daraxt hajmi cheklangan.
# --------------------------------------------------------------------------- #

_ALLOWED_NODES = (
    ast.Expression, ast.BinOp, ast.UnaryOp, ast.Constant, ast.Name, ast.Call,
    ast.Add, ast.Sub, ast.Mult, ast.Div, ast.Pow, ast.USub, ast.UAdd, ast.Load,
)
_ALLOWED_NAMES = {"pi": math.pi}
_ALLOWED_CALLS = {"sqrt": math.sqrt}

# O'quvchi javobida 2^100 dan katta son uchramaydi; hujumchi uchun esa daraja
# — serverni osishning eng arzon yo'li.
_MAX_EXPONENT = 100
_MAX_NODES = 60
_MAX_LEN = 120

# `√` dan keyin qavssiz keladigan atom: son yoki `pi`.
_SQRT_ATOM_RE = re.compile(r"√\s*(\d+(?:\.\d+)?|pi\b)")

# Yashirin ko'paytirish: o'quvchi "2π" deb yozadi, "2*π" deb emas.
_IMPLICIT_MULT = [
    re.compile(r"(\d)(pi\b|sqrt\b|\()"),
    re.compile(r"(pi\b)(\d|pi\b|sqrt\b|\()"),
    re.compile(r"(\))(\d|pi\b|sqrt\b|\()"),
]


def _eval_node(node, depth: int = 0) -> float:
    if depth > 20:
        raise ValueError("expression too deep")
    if not isinstance(node, _ALLOWED_NODES):
        raise ValueError(f"disallowed syntax: {type(node).__name__}")

    if isinstance(node, ast.Expression):
        return _eval_node(node.body, depth + 1)

    if isinstance(node, ast.Constant):
        if isinstance(node.value, bool) or not isinstance(node.value, (int, float)):
            raise ValueError("only numbers allowed")
        return float(node.value)

    if isinstance(node, ast.Name):
        if node.id not in _ALLOWED_NAMES:
            raise ValueError(f"unknown name {node.id}")
        return _ALLOWED_NAMES[node.id]

    if isinstance(node, ast.Call):
        if (not isinstance(node.func, ast.Name)
                or node.func.id not in _ALLOWED_CALLS
                or node.keywords or len(node.args) != 1):
            raise ValueError("unsupported call")
        arg = _eval_node(node.args[0], depth + 1)
        if node.func.id == "sqrt" and arg < 0:
            raise ValueError("sqrt of negative")
        return _ALLOWED_CALLS[node.func.id](arg)

    if isinstance(node, ast.UnaryOp):
        v = _eval_node(node.operand, depth + 1)
        return -v if isinstance(node.op, ast.USub) else +v

    left = _eval_node(node.left, depth + 1)
    right = _eval_node(node.right, depth + 1)
    if isinstance(node.op, ast.Add):
        return left + right
    if isinstance(node.op, ast.Sub):
        return left - right
    if isinstance(node.op, ast.Mult):
        return left * right
    if isinstance(node.op, ast.Div):
        if right == 0:
            raise ValueError("division by zero")
        return left / right
    if isinstance(node.op, ast.Pow):
        if abs(right) > _MAX_EXPONENT:
            raise ValueError("exponent too large")
        return float(left ** right)
    raise ValueError("unsupported operator")


def _eval_math_expression(s: str) -> float:
    """`π/2`, `√2`, `2^3`, `(1+2)/3` -> float. Boshqa hammasi ValueError."""
    if len(s) > _MAX_LEN:
        raise ValueError("expression too long")
    expr = (s.replace("π", "pi")
             .replace("^", "**").replace("·", "*").replace("×", "*"))
    # `√` o'zidan keyingi BITTA atomga tegishli: `√2` -> `sqrt(2)`,
    # `√2+3` -> `sqrt(2)+3` (matematik odat). Qavs qo'yilmasa `√2` shunchaki
    # `sqrt2` degan noma'lum nomga aylanib, javob rad etilardi — holbuki
    # tugmani bosgan o'quvchi aynan shu shaklda yozadi.
    expr = _SQRT_ATOM_RE.sub(r"sqrt(\1)", expr)
    # Qolgani `√(...)` — bu yerda qavs allaqachon bor.
    expr = expr.replace("√", "sqrt")
    for pattern in _IMPLICIT_MULT:
        # Bir necha yurish: "2pi3" kabi zanjirda bitta almashtirish yetmaydi.
        for _ in range(3):
            new = pattern.sub(r"\1*\2", expr)
            if new == expr:
                break
            expr = new
    # HAMMA nosozlik ValueError bo'lib chiqishi SHART.
    #
    # `_grade_numeric` aynan ValueError ni ushlaydi va uni «noto'g'ri javob»
    # ga aylantiradi. `ast.parse` esa bo'sh satrda SyntaxError beradi —
    # u ushlanmay o'tib ketsa, o'quvchining bo'sh javobi 500 xatoga
    # aylanadi. `tests/test_grading.py` dagi "garbage is wrong, not 500"
    # aynan shuni ushladi.
    try:
        tree = ast.parse(expr, mode="eval")
        if sum(1 for _ in ast.walk(tree)) > _MAX_NODES:
            raise ValueError("expression too complex")
        value = _eval_node(tree)
    except ValueError:
        raise
    except (SyntaxError, TypeError, RecursionError, OverflowError,
            ZeroDivisionError, MemoryError) as e:
        raise ValueError(f"unparseable expression: {type(e).__name__}") from e
    if not math.isfinite(value):
        raise ValueError("not finite")
    return value


def _parse_student_number(raw) -> float:
    """Parse a student's numeric answer the way they actually type it.

    Handles: plain numbers (int/float payloads pass through), comma decimals
    ("0,5" — the Uzbek/Russian convention), simple fractions ("1/3", "-16/3"),
    Unicode minus ("−2"), and stray whitespace.

    Beyond that it evaluates the small set of expressions the answer field's
    OWN BUTTONS produce: π, √, powers and parentheses ("π/2", "√2", "2^3").
    Those buttons shipped long before the grader understood them, so pressing
    one turned a correct answer into a wrong one.

    ORDERING MATTERS. The plain-number and fraction paths run FIRST and are
    unchanged, so every input that graded correctly before still takes the
    same code path and returns the same float. The evaluator only ever sees
    strings that previously raised ValueError — it can add correct answers,
    it cannot take any away.

    Still NOT a general calculator: no `eval`, no functions beyond sqrt, no
    names beyond pi. Anything else raises ValueError (graded as wrong
    upstream, never a 500).
    """
    if isinstance(raw, (int, float)) and not isinstance(raw, bool):
        return float(raw)
    s = str(raw).strip().replace("\u2212", "-").replace(" ", "")
    s = s.replace(",", ".")
    try:
        if "/" in s:
            num, _, den = s.partition("/")
            d = float(den)
            if d == 0:
                raise ValueError("division by zero")
            return float(num) / d
        return float(s)
    except ValueError:
        # Eski yo'l tushunmadi \u2014 ehtimol bu ifoda: "\u03c0/2", "\u221a2", "2^3".
        return _eval_math_expression(s)


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
