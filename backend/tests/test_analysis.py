"""
Topic mastery — the path that only runs when a student HAS data.

`topic_mastery` returns [] early when nothing has been answered, so every test
in this repo used to sail past the second half of the function. That is exactly
where `TopicTranslation.name` (the column is `title`) sat and 500ed
`/v1/me/analysis` for every real user. These tests drive the non-empty branch.
"""
import asyncio
import uuid
from types import SimpleNamespace

from app.services import analysis

class _Rows:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows

class FakeDB:
    """Yields queued result sets in call order."""

    def __init__(self, *result_sets):
        self._queue = list(result_sets)

    async def execute(self, *_a, **_kw):
        return _Rows(self._queue.pop(0))

def _mastery(db, lang="uz-Latn"):
    return asyncio.run(analysis.topic_mastery(db, uuid.uuid4(), lang))

def test_empty_history_returns_empty_list():
    assert _mastery(FakeDB([])) == []

def test_resolves_topic_title_in_requested_language():
    tid = uuid.uuid4()
    rows = [SimpleNamespace(topic_id=tid, code="geo_atmosfera",
                            answered=10, correct=7)]
    names = [(tid, "uz-Latn", "Atmosfera"), (tid, "ru", "Атмосфера")]

    out = _mastery(FakeDB(rows, names))
    assert len(out) == 1
    assert out[0]["name"] == "Atmosfera"
    assert out[0]["answered"] == 10 and out[0]["correct"] == 7
    assert out[0]["accuracy"] == 0.7

    out_ru = _mastery(FakeDB(rows, names), lang="ru")
    assert out_ru[0]["name"] == "Атмосфера"

def test_falls_back_to_any_translation_then_to_code():
    tid = uuid.uuid4()
    rows = [SimpleNamespace(topic_id=tid, code="geo_relef",
                            answered=3, correct=0)]

    assert _mastery(FakeDB(rows, [(tid, "ru", "Рельеф")]))[0]["name"] == "Рельеф"
    assert _mastery(FakeDB(rows, []))[0]["name"] == "geo_relef"

def test_zero_answered_does_not_divide_by_zero():
    tid = uuid.uuid4()
    rows = [SimpleNamespace(topic_id=tid, code="x", answered=0, correct=0)]
    assert _mastery(FakeDB(rows, []))[0]["accuracy"] == 0.0
