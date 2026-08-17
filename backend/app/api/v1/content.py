from __future__ import annotations
import logging
import random
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, Query, Request
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user_optional
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core import antiabuse
from app.core.ratelimit import client_ip, hit as ratelimit_hit
from app.core.redis import get_redis
from app.models import (
    Option, Question, QuestionTranslation, Submission, Subject,
    SubjectTranslation, Topic, User,
)
from app.schemas.question import GradeResult, SubmissionIn
from app.services import grading
from app.services import coins
from app.services import progress as progress_service
from app.services import ranking
from app.services.projection import to_grading, to_public

_log = logging.getLogger("bilim.submissions")

router = APIRouter(prefix="/v1")
_settings = get_settings()


_USER_SUBMIT_PER_HOUR = 300

def _lang(accept_language: str | None) -> str:
    return accept_language or _settings.default_lang

@router.get("/subjects")
async def list_subjects(
    db: AsyncSession = Depends(get_db),
    accept_language: str | None = Header(None),
    user: User | None = Depends(get_current_user_optional),
):
   
    lang = _lang(accept_language)
    rows = (await db.execute(
        select(Subject).where(Subject.is_active.is_(True))
        .options(selectinload(Subject.translations))
        .order_by(Subject.sort_order)
    )).scalars().all()

    bank = {
        sid: (int(qn or 0), int(tn or 0))
        for sid, qn, tn in (await db.execute(
            select(
                Question.subject_id,
                func.count(Question.id),
                func.count(func.distinct(Question.topic_id)),
            )
            .where(Question.status == "active")
            .group_by(Question.subject_id)
        )).all()
    }

    if lang == _settings.default_lang:
        translated = None
    else:
        translated = {
            sid: int(n or 0)
            for sid, n in (await db.execute(
                select(Question.subject_id, func.count(Question.id))
                .join(QuestionTranslation,
                      QuestionTranslation.question_id == Question.id)
                .where(Question.status == "active",
                       QuestionTranslation.lang == lang)
                .group_by(Question.subject_id)
            )).all()
        }

    # progress
    mine: dict = {}
    if user is not None and str(user.id) != _settings.guest_user_id:
        mine = {
            sid: (int(a or 0), int(c or 0), last)
            for sid, a, c, last in (await db.execute(
                select(
                    Question.subject_id,
                    func.count(func.distinct(Submission.question_id)),
                    func.count(func.distinct(Submission.question_id))
                        .filter(Submission.is_correct.is_(True)),
                    func.max(Submission.created_at),
                )
                .join(Question, Question.id == Submission.question_id)
                .where(Submission.user_id == user.id)
                .group_by(Question.subject_id)
            )).all()
        }

    out = []
    for s in rows:
        names = {t.lang: t.name for t in s.translations}
        q_count, t_count = bank.get(s.id, (0, 0))
        answered, correct, last_at = mine.get(s.id, (0, 0, None))
        out.append({
            "id": str(s.id),
            "code": s.code,
            "icon": s.icon,
            "image_url": s.image_url,
            "name": names.get(lang) or names.get(_settings.default_lang)
                    or next(iter(names.values()), s.code),
            "question_count": q_count,
            # o'quvchini ogohlantiradi.
            "translated_count": q_count if translated is None
                                else translated.get(s.id, 0),
            "topic_count": t_count,
            "answered": answered,
            "correct": correct,
            "accuracy": (correct / answered) if answered else 0.0,
            "last_practiced_at": last_at.isoformat() if last_at else None,
        })
    return {"items": out}

@router.get("/subjects/{subject_id}/catalog")
async def subject_catalog(
    subject_id: uuid.UUID,
    grade: int | None = Query(None, ge=1, le=11),
    db: AsyncSession = Depends(get_db),
    accept_language: str | None = Header(None),
):
   
    active = (Question.subject_id == subject_id) & (Question.status == "active")

    grade_rows = (await db.execute(
        select(Question.grade, func.count()).where(active)
        .where(Question.grade.isnot(None)).group_by(Question.grade)
        .order_by(Question.grade)
    )).all()

    scoped = active if grade is None else (active & (Question.grade == grade))

    # exam_context is text[]; unnest to count per context value.
    ctx = func.unnest(Question.exam_context).label("ctx")
    ctx_rows = (await db.execute(
        select(ctx, func.count()).where(scoped).group_by(ctx)
    )).all()

    topic_rows = (await db.execute(
        select(Question.topic_id, func.count()).where(scoped)
        .where(Question.topic_id.isnot(None)).group_by(Question.topic_id)
    )).all()

    topics = []
    if topic_rows:
        lang = _lang(accept_language)
        tmap = {tid: n for tid, n in topic_rows}
        trows = (await db.execute(
            select(Topic).where(Topic.id.in_(list(tmap.keys())))
            .options(selectinload(Topic.translations))
            .order_by(Topic.sort_order)
        )).scalars().all()
        for t in trows:
            titles = {tr.lang: tr.title for tr in t.translations}
            topics.append({
                "id": str(t.id),
                "code": t.code,
                "title": titles.get(lang) or titles.get(_settings.default_lang)
                         or next(iter(titles.values()), t.code),
                "count": tmap[t.id],
            })

    return {
        "grades": [{"grade": g, "count": n} for g, n in grade_rows],
        "exam_contexts": [{"code": c, "count": n} for c, n in ctx_rows],
        "topics": topics,
    }

def _mix_by_difficulty(pool: list[Question], limit: int) -> list[Question]:
   
    if len(pool) <= limit:
        random.shuffle(pool)
        return pool

    buckets: dict[int, list[Question]] = {}
    for q in pool:
        d = q.difficulty if q.difficulty in (1, 2, 3, 4, 5) else 2
        buckets.setdefault(d, []).append(q)

    order = sorted(buckets)
    out: list[Question] = []
    i = 0
    while len(out) < limit and any(buckets[d] for d in order):
        d = order[i % len(order)]
        if buckets[d]:
            out.append(buckets[d].pop())
        i += 1

    random.shuffle(out)
    return out

@router.get("/questions")
async def list_questions(
    subject_id: uuid.UUID,
    request: Request,
    grade: int | None = None,
    topic_id: uuid.UUID | None = None,
    exam_context: str | None = None,
    limit: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    accept_language: str | None = Header(None),
    user: User | None = Depends(get_current_user_optional),
):
    lang = _lang(accept_language)
    is_guest = user is None
    # Logged-in users are limited per account (an attacker cannot dodge by
    # rotating IPs); anonymous callers per IP, since they have no account.
    identity = f"u:{user.id}" if user else f"ip:{client_ip(request)}"

    await antiabuse.enforce(identity, is_guest)           # burst cap, pre-query

    def _base():
        s = select(Question).where(
            Question.subject_id == subject_id, Question.status == "active"
        )
        if grade is not None:
            s = s.where(Question.grade == grade)
        if topic_id is not None:
            s = s.where(Question.topic_id == topic_id)
        if exam_context is not None:
            s = s.where(Question.exam_context.any(exam_context))
        if is_guest:
            # Anonymous callers only ever reach a fixed ~1/16 slice of the bank.
            s = s.where(antiabuse.guest_pool_clause())
        return s

    POOL_FACTOR = 4
    pool_size = min(limit * POOL_FACTOR, 200)

    picked: list[Question] = []
    seen_ids: set = set()

    if not is_guest:
        unseen = _base().where(
            ~select(Submission.id)
            .where(Submission.question_id == Question.id,
                   Submission.user_id == user.id)
            .exists()
        ).order_by(func.random()).limit(pool_size)
        picked = list((await db.execute(unseen)).scalars().all())
        seen_ids = {q.id for q in picked}

    if len(picked) < pool_size:
        top_up = _base()
        if seen_ids:
            top_up = top_up.where(Question.id.notin_(seen_ids))
        top_up = top_up.order_by(func.random()).limit(pool_size - len(picked))
        picked += list((await db.execute(top_up)).scalars().all())

    rows = _mix_by_difficulty(picked, limit)

    # Breadth check AFTER serving: a scraper is identified by never repeating.
    await antiabuse.observe(identity, [str(q.id) for q in rows], is_guest)

    return {"items": [to_public(q, lang).model_dump() for q in rows]}

@router.post("/submissions", response_model=GradeResult)
async def submit(
    body: SubmissionIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
    accept_language: str | None = Header(None),
    current_user: User | None = Depends(get_current_user_optional),
    # Legacy guest path: used only when there is no Bearer token (pre-login
    # practice). Once the client sends a JWT, this header is ignored.
    x_debug_user_id: str | None = Header(None),
):
    # ---- flood control -------------------------------------------------------
    # Checked FIRST, before any DB work: there is no point grading a request we
    # are going to refuse. Guests all share one row, so they are limited by IP;
    # logged-in users are limited by account id, which — unlike an IP — they
    # cannot rotate. Redis down fails open, see core/ratelimit.py.
    if current_user is None:
        bucket, identity, cap = (
            "guest_submit", client_ip(request), _GUEST_SUBMIT_PER_HOUR)
        detail = "please sign in to continue practising"
    else:
        bucket, identity, cap = (
            "user_submit", str(current_user.id), _USER_SUBMIT_PER_HOUR)
        detail = "biroz sekinroq — bir oz dam oling"
    allowed, n = await ratelimit_hit(bucket, identity, cap, 3600)
    if not allowed:
        _log.warning("submit rate limit hit %s=%s count=%s", bucket, identity, n)
        raise AppError(429, "Too many attempts", detail)

    q = (await db.execute(
        select(Question)
        .where(Question.id == body.question_id)
        .options(selectinload(Question.translations))
    )).scalar_one_or_none()
    if q is None or q.status != "active":
        raise AppError(404, "Question not found")

 
    if current_user is not None:
        locked = await db.scalar(text("""
            SELECT 1 FROM challenges c
             WHERE c.status = 'active'
               AND (c.creator_id = :uid OR c.opponent_id = :uid)
               AND :qid = ANY (c.question_ids)
               AND NOT EXISTS (SELECT 1 FROM challenge_results r
                                WHERE r.challenge_id = c.id AND r.user_id = :uid)
             LIMIT 1
        """), {"uid": str(current_user.id), "qid": str(body.question_id)})
        if locked:
            raise AppError(409, "Question locked",
                           "bu savol hozir bellashuvda — avval bellashuvni "
                           "yakunlang",
                           type_="urn:bilim:quiz:challenge_locked")

    gq = to_grading(q)                       # server-only projection
    try:
        result = grading.grade(gq, body)     # server decides — always trustworthy
    except Exception:
        _log.exception("grading failed question_id=%s type=%s", q.id, q.type)
        result = GradeResult(question_id=str(q.id), is_correct=False,
                             score=0, max_score=q.max_score)
    if result.is_correct:
        result.correct_option_ids = list(
            (q.grading_spec or {}).get("correct_option_ids", []))
        lang = (accept_language or "uz-Latn").split(",")[0].strip()
        tr = (next((t for t in q.translations if t.lang == lang), None)
              or next((t for t in q.translations), None))
        if tr is not None:
            result.explanation = tr.explanation

    
    if current_user is not None:
        user_id = current_user.id
    else:
        if x_debug_user_id and x_debug_user_id != _settings.guest_user_id:
            _log.warning(
                "rejected X-Debug-User-Id impersonation attempt: %r", x_debug_user_id)
        user_id = uuid.UUID(_settings.guest_user_id)
    is_guest = (str(user_id) == _settings.guest_user_id)

 
    persisted = True
    awarded = False   # True only when this is the FIRST correct answer to this q
    xp_awarded = 0
    coins_awarded = 0
    coins_penalty = 0
    reward_reason = "guest" if current_user is None else None
    # Capture the id as a plain string BEFORE the transaction: after a rollback the
    # ORM object `q` is expired, so touching q.id in an except block would trigger
    # a lazy reload on a dead session (a second crash, MissingGreenlet).
    q_id_str = str(q.id)
    try:
        db.add(Submission(
            user_id=user_id,
            question_id=q.id,
            payload=body.payload,
            score=result.score,
            max_score=result.max_score,
            is_correct=result.is_correct,
            response_ms=body.response_ms,
        ))
        if not is_guest:
            try:
                async with db.begin_nested():
                    prog = await progress_service.touch_activity(db, user_id)
                    await coins.try_award_daily_login(
                        db, user_id,
                        datetime.now(timezone.utc).date().isoformat(),
                        _settings.coins_daily_login,
                    )
                    if result.is_correct:
                        awarded = await coins.try_award_quiz(
                            db, user_id, str(q.id), _settings.coins_per_correct)
                        if awarded:
                            progress_service.award_xp(prog, result.score)
                            xp_awarded = progress_service.xp_for_score(
                                result.score)
                            coins_awarded = _settings.coins_per_correct
                            reward_reason = "ok"
                        else:
                            reward_reason = "repeat"
                    else:
                        taken = await coins.apply_wrong_penalty(
                            db, user_id, str(q.id),
                            _settings.coins_per_wrong_penalty)
                        coins_penalty = taken
                        reward_reason = "wrong"
            except Exception:
                awarded = False
                xp_awarded = coins_awarded = coins_penalty = 0
                reward_reason = None
                _log.exception(
                    "reward bookkeeping failed (submission still saved) "
                    "user_id=%s question_id=%s", user_id, q_id_str)
        await db.commit()
    except Exception:
        await db.rollback()
        persisted = False
        awarded = False
        xp_awarded = coins_awarded = coins_penalty = 0
        reward_reason = "guest" if current_user is None else None
        if is_guest:
            _log.warning("guest submission not persisted question_id=%s", q_id_str)
        else:
            # real user: this is a genuine fault, surface it in logs with context
            _log.exception(
                "submission persist FAILED user_id=%s question_id=%s",
                user_id, q_id_str,
            )
    if persisted and awarded and not is_guest:
        try:
            subj = (await db.execute(
                select(Subject.code).where(Subject.id == q.subject_id)
            )).scalar_one_or_none()
            await ranking.award(
                get_redis(), str(user_id), result.score,
                subject_code=subj,
                region_code=current_user.region_code if current_user else None,
            )
        except Exception:
            _log.exception(
                "leaderboard award FAILED user_id=%s question_id=%s score=%s",
                user_id, q.id, result.score,
            )

    result.xp_awarded = xp_awarded
    result.coins_awarded = coins_awarded
    result.coins_delta = coins_awarded - coins_penalty
    result.reward_reason = reward_reason
    return result
