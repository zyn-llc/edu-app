"""Phone normalization and the pure gamification arithmetic."""
from datetime import date

import pytest

from app.schemas.auth import normalize_uz_phone
from app.services import progress


@pytest.mark.parametrize("raw", [
    "+998 90 123 45 67",
    "998901234567",
    "901234567",
    "0901234567",
    "+998901234567",
])
def test_phone_normalizes_to_e164(raw):
    assert normalize_uz_phone(raw) == "+998901234567"


@pytest.mark.parametrize("bad", ["12345", "", "+1 555 123 4567", "9012345678901"])
def test_bad_phone_rejected(bad):
    with pytest.raises(ValueError):
        normalize_uz_phone(bad)


def test_level_and_xp():
    assert progress.xp_for_score(1) == 10        # default xp_per_point
    assert progress.level_for_xp(0) == 1
    assert progress.level_for_xp(99) == 1
    assert progress.level_for_xp(100) == 2
    assert progress.level_for_xp(250) == 3


def test_streak_first_day():
    assert progress.next_streak(0, None, date(2026, 1, 10)) == 1


def test_streak_same_day_no_double_count():
    assert progress.next_streak(5, date(2026, 1, 10), date(2026, 1, 10)) == 5


def test_streak_consecutive_day_increments():
    assert progress.next_streak(5, date(2026, 1, 9), date(2026, 1, 10)) == 6


def test_streak_gap_resets():
    assert progress.next_streak(5, date(2026, 1, 1), date(2026, 1, 10)) == 1
