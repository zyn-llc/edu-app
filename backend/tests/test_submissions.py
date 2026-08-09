"""
Submit endpoint — the answer key must never leave the server on a wrong answer.

This is the test that was missing when the leak shipped. `test_grading.py`
already proved the GRADER never reveals the key; nothing proved the HANDLER
doesn't add it back afterwards, and that is exactly what happened: one line in
`content.submit` attached `correct_option_ids` unconditionally, which turned
"answer wrong, read the key, resubmit" into free XP, coins and leaderboard
points on all 17k questions.

The handler is exercised directly with fakes rather than through a live app:
these assertions are about branch behaviour, not about SQL, and the repo has no
DB-backed test harness (see test_challenges.py for the same approach).
"""
import asyncio
import uuid
from types import SimpleNamespace

import pytest

from app.api.v1 import content
from app.core.errors import AppError
from app.schemas.question import SubmissionIn


# --------------------------------------------------------------------------- #
#  Fakes                                                                       #
# --------------------------------------------------------------------------- #
class _Result:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


class _Savepoint:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class FakeDB:
    """Returns queued results in order; records what was added."""

    def __init__(self, results):
        self._results = list(results)
        self.added = []
        self.committed = False
        self.scalar_value = None          # answer for the challenge-lock probe

    async def execute(self, *_a, **_kw):
        return _Result(self._results.pop(0) if self._results else None)

    async def scalar(self, *_a, **_kw):
        return self.scalar_value

    def add(self, obj):
        self.added.append(obj)

    def begin_nested(self):
        return _Savepoint()

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


def _question(correct="c", explanation="To'g'ri javob C, chunki ..."):
    qid = uuid.uuid4()
    return SimpleNamespace(
        id=qid,
        subject_id=uuid.uuid4(),
        status="active",
        type="mcq",
        max_score=1,
        grading_spec={"correct_option_ids": [correct]},
        translations=[SimpleNamespace(lang="uz-Latn", explanation=explanation)],
    )


def _user():
    return SimpleNamespace(id=uuid.uuid4(), region_code="tashkent")


def _request():
    return SimpleNamespace(client=SimpleNamespace(host="10.0.0.1"), headers={})


@pytest.fixture
def wired(monkeypatch):
    """Neutralise everything the handler touches except the logic under test."""
    async def _allow(*_a, **_kw):
        return True, 1

    async def _touch(*_a, **_kw):
        return SimpleNamespace(xp=0, level=1)

    async def _award_quiz(*_a, **_kw):
        return True                      # first correct answer for this question

    async def _daily(*_a, **_kw):
        return False

    async def _penalty(*_a, **_kw):
        return 1

    async def _rank(*_a, **_kw):
        return None

    monkeypatch.setattr(content, "ratelimit_hit", _allow)
    monkeypatch.setattr(content.progress_service, "touch_activity", _touch)
    monkeypatch.setattr(content.progress_service, "award_xp", lambda *a, **k: None)
    monkeypatch.setattr(content.coins, "try_award_quiz", _award_quiz)
    monkeypatch.setattr(content.coins, "try_award_daily_login", _daily)
    monkeypatch.setattr(content.coins, "apply_wrong_penalty", _penalty)
    monkeypatch.setattr(content.ranking, "award", _rank)
    monkeypatch.setattr(content, "get_redis", lambda: None)


def _submit(db, q, user, payload):
    return asyncio.run(content.submit(
        body=SubmissionIn(question_id=str(q.id), payload=payload),
        request=_request(),
        db=db,
        accept_language="uz-Latn",
        current_user=user,
        x_debug_user_id=None,
    ))


# --------------------------------------------------------------------------- #
#  The leak                                                                    #
# --------------------------------------------------------------------------- #
def test_wrong_answer_reveals_neither_key_nor_explanation(wired):
    q = _question(correct="c")
    res = _submit(FakeDB([q, "geografiya"]), q, _user(), {"option_ids": ["a"]})

    assert res.is_correct is False
    assert res.correct_option_ids == []
    assert res.explanation is None
    # Belt and braces: the key must not appear anywhere in the serialized body.
    assert "c" not in res.model_dump(exclude={"question_id"}).get(
        "correct_option_ids", [])
    assert res.xp_awarded == 0 and res.coins_awarded == 0
    assert res.reward_reason == "wrong"


def test_correct_answer_reveals_key_and_explanation(wired):
    q = _question(correct="c")
    res = _submit(FakeDB([q, "geografiya"]), q, _user(), {"option_ids": ["c"]})

    assert res.is_correct is True
    assert res.correct_option_ids == ["c"]
    assert res.explanation.startswith("To'g'ri javob")
    assert res.xp_awarded == 10 and res.coins_awarded == 5
    assert res.reward_reason == "ok"


def test_repeat_correct_answer_pays_nothing(wired, monkeypatch):
    async def _already(*_a, **_kw):
        return False                     # ledger already holds this reward

    monkeypatch.setattr(content.coins, "try_award_quiz", _already)
    q = _question(correct="c")
    res = _submit(FakeDB([q]), q, _user(), {"option_ids": ["c"]})

    assert res.is_correct is True
    assert res.xp_awarded == 0 and res.coins_awarded == 0
    assert res.reward_reason == "repeat"
    # Still correct, so the learner still sees why.
    assert res.correct_option_ids == ["c"]


# --------------------------------------------------------------------------- #
#  Challenge questions cannot be pre-graded as practice                        #
# --------------------------------------------------------------------------- #
def test_question_in_unfinished_challenge_is_refused(wired):
    q = _question()
    db = FakeDB([q])
    db.scalar_value = 1                  # probe found an active challenge

    with pytest.raises(AppError) as e:
        _submit(db, q, _user(), {"option_ids": ["c"]})
    assert e.value.status == 409
    assert e.value.type == "urn:bilim:quiz:challenge_locked"


def test_guest_is_not_challenge_checked(wired):
    """Guests can't hold challenges, so the probe must be skipped entirely —
    otherwise every anonymous answer pays for a pointless query."""
    q = _question()
    db = FakeDB([q])
    db.scalar_value = 1                  # would refuse if the probe ran
    res = _submit(db, q, None, {"option_ids": ["c"]})
    assert res.is_correct is True
    assert res.reward_reason == "guest"


# --------------------------------------------------------------------------- #
#  A broken grading_spec must not 500 the drill                                #
# --------------------------------------------------------------------------- #
def test_broken_grading_spec_grades_wrong_instead_of_crashing(wired):
    q = _question()
    q.grading_spec = {"correct_option_ids": ["a", "b"]}   # mcq needs exactly one
    res = _submit(FakeDB([q]), q, _user(), {"option_ids": ["a"]})

    assert res.is_correct is False
    assert res.score == 0 and res.max_score == 1
    assert res.correct_option_ids == []


def test_rate_limit_applies_to_logged_in_users(wired, monkeypatch):
    async def _deny(bucket, identity, *_a, **_kw):
        assert bucket == "user_submit"          # not the guest bucket
        return False, 999

    monkeypatch.setattr(content, "ratelimit_hit", _deny)
    q = _question()
    with pytest.raises(AppError) as e:
        _submit(FakeDB([q]), q, _user(), {"option_ids": ["c"]})
    assert e.value.status == 429
