"""
Har bir `Model.attr` havolasi haqiqiy ustunga tegishimi.

NEGA BU TEST BOR. `services/analysis.py` uzoq vaqt `TopicTranslation.name` ni
so'radi — ustun esa `title`. SQLAlchemy bunday atributni faqat SO'ROV
QURILAYOTGANDA, ya'ni ISH VAQTIDA rad etadi, va o'sha kod yo'li bo'sh
ro'yxatda erta qaytgani uchun barcha testlar yashil qolardi. Xato faqat
haqiqiy ma'lumotli foydalanuvchida ko'rinardi: `/v1/me/analysis` 500.

Test AST bo'ylab yuradi, `Model.attr` shaklidagi har bir havolani topadi va
uni mapper bilgan atributlar bilan solishtiradi. Sekin emas (~50 ms) va
noto'g'ri ogohlantirish bermaydi: sinf nomi model emas bo'lsa, tashlab
ketiladi.
"""
from __future__ import annotations

import ast
import pathlib

import app.models as models

_APP_DIR = pathlib.Path(__file__).resolve().parent.parent / "app"


def _mapped_classes() -> dict[str, type]:
    return {
        name: obj
        for name, obj in vars(models).items()
        if isinstance(obj, type) and hasattr(obj, "__tablename__")
    }


def test_no_phantom_model_attributes():
    classes = _mapped_classes()
    known = {n: set(c.__mapper__.attrs.keys()) for n, c in classes.items()}

    bad: list[str] = []
    for path in _APP_DIR.rglob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if not (isinstance(node, ast.Attribute)
                    and isinstance(node.value, ast.Name)):
                continue
            cls = node.value.id
            if cls not in known or node.attr.startswith("_"):
                continue
            # Ustun emas, lekin sinfda bor (masalan `Model.__table__`,
            # klass metodi) — bular to'g'ri.
            if node.attr in known[cls] or hasattr(classes[cls], node.attr):
                continue
            bad.append(f"{path.relative_to(_APP_DIR.parent)}:{node.lineno} "
                       f"-> {cls}.{node.attr}")

    assert not bad, (
        "Modelda mavjud bo'lmagan atributga havola (ish vaqtida "
        "AttributeError beradi):\n  " + "\n  ".join(sorted(set(bad))))
