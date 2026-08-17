from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query, status
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.errors import AppError
from app.models import Note, User

router = APIRouter(prefix="/v1/notes", tags=["notes"])

MAX_NOTES_PER_USER = 500

class NoteIn(BaseModel):
    body: str = Field(min_length=1, max_length=8000)
    title: str | None = Field(default=None, max_length=200)
    question_id: uuid.UUID | None = None
    subject_id: uuid.UUID | None = None

class NotePatch(BaseModel):
    body: str | None = Field(default=None, min_length=1, max_length=8000)
    title: str | None = Field(default=None, max_length=200)

def _out(n: Note) -> dict:
    return {
        "id": str(n.id),
        "title": n.title,
        "body": n.body,
        "question_id": str(n.question_id) if n.question_id else None,
        "subject_id": str(n.subject_id) if n.subject_id else None,
        "created_at": n.created_at.isoformat() if n.created_at else None,
        "updated_at": n.updated_at.isoformat() if n.updated_at else None,
    }

async def _get_own(db: AsyncSession, user: User, note_id: uuid.UUID) -> Note:
    note = (await db.execute(
        select(Note).where(Note.id == note_id, Note.user_id == user.id)
    )).scalar_one_or_none()
    if note is None:
        raise AppError(404, "Note not found")
    return note

@router.get("")
async def list_notes(
    limit: int = Query(100, ge=1, le=200),
    offset: int = Query(0, ge=0),
    question_id: uuid.UUID | None = None,
    subject_id: uuid.UUID | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(Note).where(Note.user_id == user.id)
    if question_id is not None:
        stmt = stmt.where(Note.question_id == question_id)
    if subject_id is not None:
        stmt = stmt.where(Note.subject_id == subject_id)
    stmt = stmt.order_by(Note.updated_at.desc()).limit(limit).offset(offset)
    rows = (await db.execute(stmt)).scalars().all()
    return {"items": [_out(n) for n in rows]}

@router.post("", status_code=status.HTTP_201_CREATED)
async def create_note(
    payload: NoteIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    count = (await db.execute(
        select(func.count(Note.id)).where(Note.user_id == user.id)
    )).scalar() or 0
    if count >= MAX_NOTES_PER_USER:
        raise AppError(409, "Note limit reached",
                       f"maximum {MAX_NOTES_PER_USER} notes per account")

    note = Note(
        user_id=user.id,
        question_id=payload.question_id,
        subject_id=payload.subject_id,
        title=(payload.title or None),
        body=payload.body.strip(),
    )
    db.add(note)
    try:
        await db.commit()
    except Exception:
        await db.rollback()
        raise AppError(400, "Invalid note", "question_id or subject_id not found")
    await db.refresh(note)
    return _out(note)

@router.patch("/{note_id}")
async def update_note(
    note_id: uuid.UUID,
    payload: NotePatch,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    note = await _get_own(db, user, note_id)
    if payload.body is None and payload.title is None:
        raise AppError(400, "Empty patch", "nothing to update")
    if payload.body is not None:
        note.body = payload.body.strip()
    if payload.title is not None:
        note.title = payload.title or None
    note.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(note)
    return _out(note)

@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_note(
    note_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    note = await _get_own(db, user, note_id)
    await db.delete(note)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
