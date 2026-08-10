"""ORM models.

Every table the API actually reads or writes is mapped here. Tables that exist in
sql/ but have no model are not "not mapped yet" — they were dropped (see
sql/027_drop_unused_tables.sql) precisely so that this file and the schema stay
the same shape.
"""
from __future__ import annotations
import uuid
from datetime import date, datetime

from sqlalchemy import (
    BigInteger, Boolean, Date, DateTime, ForeignKey, Integer, SmallInteger,
    String, Text, func,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base

def _uuid_pk():
    return mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

class Subject(Base):
    __tablename__ = "subjects"
    id: Mapped[uuid.UUID] = _uuid_pk()
    code: Mapped[str] = mapped_column(String, unique=True)
    icon: Mapped[str | None] = mapped_column(String, nullable=True)
    image_url: Mapped[str | None] = mapped_column(String, nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    translations: Mapped[list["SubjectTranslation"]] = relationship(
        back_populates="subject", lazy="selectin")

class SubjectTranslation(Base):
    __tablename__ = "subject_translations"
    subject_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("subjects.id", ondelete="CASCADE"), primary_key=True)
    lang: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String)
    subject: Mapped[Subject] = relationship(back_populates="translations")

class Topic(Base):
    __tablename__ = "topics"
    id: Mapped[uuid.UUID] = _uuid_pk()
    subject_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("subjects.id"))
    parent_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("topics.id"), nullable=True)
    code: Mapped[str] = mapped_column(String)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    translations: Mapped[list["TopicTranslation"]] = relationship(lazy="selectin")

class TopicTranslation(Base):
    __tablename__ = "topic_translations"
    topic_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("topics.id", ondelete="CASCADE"), primary_key=True)
    lang: Mapped[str] = mapped_column(String, primary_key=True)
    title: Mapped[str] = mapped_column(Text)

class Question(Base):
    __tablename__ = "questions"
    id: Mapped[uuid.UUID] = _uuid_pk()
    subject_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("subjects.id"))
    topic_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("topics.id"), nullable=True)
    grade: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    exam_context: Mapped[list[str] | None] = mapped_column(ARRAY(String), nullable=True)
    type: Mapped[str] = mapped_column(String, default="mcq")
    difficulty: Mapped[int] = mapped_column(SmallInteger, default=2)
    max_score: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String, default="active")
    schema_version: Mapped[int] = mapped_column(Integer, default=1)
    grading_spec: Mapped[dict] = mapped_column(JSONB)        # *** server only ***
    media: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    tags: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    source_ref: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())
    translations: Mapped[list["QuestionTranslation"]] = relationship(
        lazy="selectin")
    options: Mapped[list["Option"]] = relationship(lazy="selectin")

class QuestionTranslation(Base):
    __tablename__ = "question_translations"
    question_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("questions.id", ondelete="CASCADE"), primary_key=True)
    lang: Mapped[str] = mapped_column(String, primary_key=True)
    stem: Mapped[str] = mapped_column(Text)
    explanation: Mapped[str | None] = mapped_column(Text, nullable=True)

class Option(Base):
    __tablename__ = "options"
    id: Mapped[uuid.UUID] = _uuid_pk()
    question_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("questions.id", ondelete="CASCADE"))
    option_key: Mapped[str] = mapped_column(String)
    position: Mapped[int] = mapped_column(Integer, default=0)
    side: Mapped[str | None] = mapped_column(String, nullable=True)
    media_url: Mapped[str | None] = mapped_column(String, nullable=True)
    # NO is_correct column — by design.
    translations: Mapped[list["OptionTranslation"]] = relationship(lazy="selectin")

class OptionTranslation(Base):
    __tablename__ = "option_translations"
    option_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("options.id", ondelete="CASCADE"), primary_key=True)
    lang: Mapped[str] = mapped_column(String, primary_key=True)
    text: Mapped[str] = mapped_column(Text)

class Submission(Base):
    __tablename__ = "submissions"
    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    question_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("questions.id"))
    payload: Mapped[dict] = mapped_column(JSONB)
    score: Mapped[int] = mapped_column(Integer)
    max_score: Mapped[int] = mapped_column(Integer)
    is_correct: Mapped[bool] = mapped_column(Boolean)
    response_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())

# --------------------------------------------------------------------------- #
#  Phase 2 — auth, gamification, parent link                                  #
#  (tables already exist in sql/001_init.sql; mapped here as each lands)       #
# --------------------------------------------------------------------------- #
class User(Base):
    __tablename__ = "users"
    id: Mapped[uuid.UUID] = _uuid_pk()
    role: Mapped[str] = mapped_column(String, default="student")  # student|parent|admin
    phone: Mapped[str | None] = mapped_column(String, unique=True, nullable=True)
    telegram_id: Mapped[int | None] = mapped_column(BigInteger, unique=True,
                                                    nullable=True)
    display_name: Mapped[str | None] = mapped_column(String, nullable=True)
    # Telegram/taklif kodi orqali kiradi. Noyoblik `lower(username)` bo'yicha
    username: Mapped[str | None] = mapped_column(String(20), nullable=True)
    avatar_color: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    region_code: Mapped[str | None] = mapped_column(String, nullable=True)
    grade: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    locale: Mapped[str | None] = mapped_column(String, nullable=True, default="uz-Latn")
    password_hash: Mapped[str | None] = mapped_column(String, nullable=True)
    referred_by: Mapped[str | None] = mapped_column(String(20), nullable=True)
    tg_notifications: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())

class RefreshToken(Base):
    __tablename__ = "refresh_tokens"
    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"))
    token_hash: Mapped[str] = mapped_column(String)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())

class Guardianship(Base):
    __tablename__ = "guardianship"
    parent_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    student_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)

class UserProgress(Base):
    __tablename__ = "user_progress"
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    xp: Mapped[int] = mapped_column(Integer, default=0)
    level: Mapped[int] = mapped_column(Integer, default=1)
    streak_days: Mapped[int] = mapped_column(Integer, default=0)
    last_active: Mapped[date | None] = mapped_column(Date, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())

class CoinTransaction(Base):
    __tablename__ = "coin_transactions"
    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"))
    amount: Mapped[int] = mapped_column(Integer)          # +earn / -spend
    reason: Mapped[str] = mapped_column(String)
    source: Mapped[str] = mapped_column(String, default="earned")
    ref_type: Mapped[str | None] = mapped_column(String, nullable=True)
    ref_id: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())

class Challenge(Base):
    __tablename__ = "challenges"
    id: Mapped[uuid.UUID] = _uuid_pk()
    code: Mapped[str] = mapped_column(String, unique=True)
    creator_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"))
    opponent_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    subject_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("subjects.id"))
    grade: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    question_count: Mapped[int] = mapped_column(Integer)
    stake: Mapped[int] = mapped_column(Integer)
    question_ids: Mapped[list[uuid.UUID]] = mapped_column(ARRAY(UUID(as_uuid=True)))
    status: Mapped[str] = mapped_column(String, default="open")
    creator_score: Mapped[int | None] = mapped_column(Integer, nullable=True)
    opponent_score: Mapped[int | None] = mapped_column(Integer, nullable=True)
    winner_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

class ChallengeResult(Base):
    __tablename__ = "challenge_results"
    challenge_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("challenges.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    score: Mapped[int] = mapped_column(Integer)
    max_score: Mapped[int] = mapped_column(Integer)
    detail: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())

class Feedback(Base):
    __tablename__ = "feedback"
    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    message: Mapped[str] = mapped_column(String)
    contact: Mapped[str | None] = mapped_column(String, nullable=True)
    app_version: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[str] = mapped_column(String, default="new")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())

# --------------------------------------------------------------------------- #
#  009 — daftar (notes) + yangiliklar (announcements)                          #
# --------------------------------------------------------------------------- #
class Note(Base):
    __tablename__ = "notes"
    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"))
    question_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("questions.id", ondelete="SET NULL"), nullable=True)
    subject_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("subjects.id", ondelete="SET NULL"), nullable=True)
    title: Mapped[str | None] = mapped_column(Text, nullable=True)
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())

class Announcement(Base):
    __tablename__ = "announcements"
    id: Mapped[uuid.UUID] = _uuid_pk()
    kind: Mapped[str] = mapped_column(String, default="news")
    grade: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    published_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                   server_default=func.now())
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())
    translations: Mapped[list["AnnouncementTranslation"]] = relationship(
        lazy="selectin")

class AnnouncementTranslation(Base):
    __tablename__ = "announcement_translations"
    announcement_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("announcements.id", ondelete="CASCADE"), primary_key=True)
    lang: Mapped[str] = mapped_column(String, primary_key=True)
    title: Mapped[str] = mapped_column(Text)
    body: Mapped[str] = mapped_column(Text)

class InviteCode(Base):
    __tablename__ = "invite_codes"
    code: Mapped[str] = mapped_column(String, primary_key=True)
    label: Mapped[str | None] = mapped_column(String, nullable=True)
    max_uses: Mapped[int] = mapped_column(Integer, default=1)
    used_count: Mapped[int] = mapped_column(Integer, default=0)
    grade: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    region_code: Mapped[str | None] = mapped_column(String, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())

class InviteRedemption(Base):
    __tablename__ = "invite_redemptions"
    code: Mapped[str] = mapped_column(
        ForeignKey("invite_codes.code", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                 server_default=func.now())
