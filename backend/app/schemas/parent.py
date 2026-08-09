"""Parent / guardianship DTOs."""
from __future__ import annotations

from pydantic import BaseModel

from app.schemas.leaderboard import ProgressOut


class LinkCodeOut(BaseModel):
    """A student generates this and reads it to a parent (or shares it). The
    parent enters it to establish guardianship. Short-lived, single-use."""
    code: str
    expires_in_seconds: int


class LinkIn(BaseModel):
    code: str


class ChildSummary(BaseModel):
    student_id: str
    display_name: str | None = None
    grade: int | None = None
    region_code: str | None = None
    avatar_color: int | None = None
    progress: ProgressOut

    # Ota-onaga xos signallar. Bola o'z ekranida bularni ko'rmaydi —
    # aynan shu farq ota-ona panelini ma'noli qiladi.
    answered_7d: int = 0
    accuracy_7d: float = 0.0
    active_days_7d: int = 0
    last_practiced_at: str | None = None


class ChildrenOut(BaseModel):
    children: list[ChildSummary] = []
