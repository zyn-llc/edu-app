"""
Phase-1 content + submission endpoints — the reference implementation pattern
every other module copies.

Flow:
  GET  /v1/subjects                      -> list subjects (localized)
  GET  /v1/subjects/{id}/catalog         -> metadata-driven nav (grades/topics/
                                            exam_contexts that actually have Qs)
  GET  /v1/questions                     -> PUBLIC projection only (no keys)
  POST /v1/submissions                   -> server grades, stores, returns result

Handlers are thin: they fetch, delegate to services, and serialize. No grading
logic lives here — it lives in services/grading.py.

Abuse controls:
  * /questions   — per-identity burst cap + distinct-question breadth tracking,
                   plus a fixed sample of the bank for anonymous callers.
  * /submissions — flood cap on BOTH paths (guest by IP, user by account id),
                   the answer key released only on a correct answer, and
                   questions frozen into an unfinished challenge refused
                   outright so the key cannot be harvested before the bet.
"""
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
    Option, Question, Submission, Subject, SubjectTranslation, Topic, User,
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

# Guest = a single shared account, so it cannot be limited per user — limit per
# IP. A real student answers maybe 1-2 questions/minute; 120/hour leaves huge
# headroom while stopping a script from farming the bank through the guest path.
_GUEST_SUBMIT_PER_HOUR = 120
# Logged-in users used to have NO submit limit at all — the guest cap sat inside
# an `if current_user is None` branch. That made an authenticated account the
# cheapest way to hammer the grader. A 20-question drill takes ~5 minutes, so
# 300/hour is fifteen back-to-back drills: unreachable by a human, immediate for
# a script.
_USER_SUBMIT_PER_HOUR = 300


def _lang(accept_language: str | None) -> str:
    return accept_language or _settings.default_lang


# --------------------------------------------------------------------------- #
#  Subjects + metadata-driven catalog                                         #
# --------------------------------------------------------------------------- #
@router.get("/subjects")
async def list_subjects(
    db: AsyncSession = Depends(get_db),
    accept_language: str | None = Header(None),
    user: User | None = Depends(get_current_user_optional),
):
    """Fanlar ro'yxati + kartochka uchun kerak bo'ladigan hamma raqam.

    Nega bir endpointda: fan kartochkasida "2 345 ta savol · 12 bo'lim ·
    siz 124 tasini yechgansiz" ko'rsatish uchun klient aks holda har fan
    uchun alohida `/catalog` so'rovi yuborishi kerak bo'lardi — 7 ta fan =
    7 ta qo'shimcha so'rov, mobil tarmoqda sezilarli kechikish.

    `answered`/`correct` DISTINCT savol bo'yicha hisoblanadi: bitta savolni
    o'n marta yechish progressni o'nga ko'paytirmaydi.

    Login qilmagan foydalanuvchi uchun shaxsiy maydonlar 0 bo'ladi —
    endpoint mehmonga ham ochiq, chunki fanlar ro'yxati kirishdan oldin ham
    ko'rinishi kerak.
    """
    lang = _lang(accept_language)
    rows = (await db.execute(
        select(Subject).where(Subject.is_active.is_(True))
        .options(selectinload(Subject.translations))
        .order_by(Subject.sort_order)
    )).scalars().all()

    # --- bank hajmi: aktiv savol va (savoli bor) bo'lim soni --------------
    # `count(DISTINCT topic_id)` NULL larni sanamaydi — bo'limi belgilanmagan
    # savollar bo'lim sifatida ko'rinmaydi, bu to'g'ri.
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

    # --- shaxsiy progress -------------------------------------------------
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
            "topic_count": t_count,
            "answered": answered,
            "correct": correct,
            # 0..1. ATAYLAB aniqlik (correct/answered), bank qamrovi emas:
            # 5 700 savolli bankda 50 ta yechgan o'quvchi 0.9% ko'rsatardi va
            # bu ilova buzuq degan taassurot qoldirardi.
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
    """Returns the grades / topics / exam_contexts that actually have active
    questions for this subject, each with a count. The client renders a
    responsive grid from this — no hardcoded screens. Math (many topics) and a
    sparse subject use the same screen.

    `grade` BERILGANDA bo'limlar va imtihon konteksti SHU SINF bo'yicha
    filtrlanadi.

    NEGA QO'SHILDI (2026-08-06, sinovda topilgan xato). Ilgari bo'limlar
    butun fan bo'yicha qaytarilardi. Klientda esa sinf va bo'lim ketma-ket,
    lekin MUSTAQIL tanlanardi. Natijada foydalanuvchi «11-sinf» ni tanlab,
    ro'yxatdan 5-sinf bo'limini tanlashi mumkin edi — server esa
    `grade=11 AND topic=<5-sinf bo'limi>` bo'yicha NOL savol topardi va
    ekranda «Bu bo'lim uchun savollar topilmadi» chiqardi. Foydalanuvchi
    buni ilova buzuq deb tushunardi, aslida shunchaki mos savol yo'q edi.

    `grades` ATAYLAB filtrlanmaydi: u tanlash ro'yxatining o'zi, ya'ni har
    doim to'liq bo'lishi kerak.
    """
    active = (Question.subject_id == subject_id) & (Question.status == "active")

    # Sinf ro'yxati — har doim to'liq, filtrsiz.
    grade_rows = (await db.execute(
        select(Question.grade, func.count()).where(active)
        .where(Question.grade.isnot(None)).group_by(Question.grade)
        .order_by(Question.grade)
    )).all()

    # Bo'lim va kontekst — tanlangan sinf doirasida.
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


# --------------------------------------------------------------------------- #
#  Public questions (no answer keys, ever)                                    #
# --------------------------------------------------------------------------- #
def _mix_by_difficulty(pool: list[Question], limit: int) -> list[Question]:
    """Qiyinlik bo'yicha aralash to'plam qaytaradi.

    NEGA KERAK. `ORDER BY random()` bankning qiyinlik taqsimotini
    ko'chiradi: geografiyada 1-daraja savollar ko'p, ya'ni tasodifiy 20 ta
    savolning 15 tasi oson chiqadi. O'quvchi "juda oson" deb qiziqishini
    yo'qotadi; teskarisi ham xuddi shunday zararli.

    QANDAY. Pool qiyinlik bo'yicha guruhlanadi, keyin guruhlardan NAVBAT
    BILAN olinadi (1, 2, 3, 1, 2, 3, ...). Guruh tugasa navbatdan chiqadi —
    ya'ni faqat oson savoli bor bo'limda ham `limit` ta savol qaytadi.

    Oxirida tartib ARALASHTIRILADI: aks holda har uchinchi savol qiyin
    bo'lib, o'quvchi naqshni sezib qolardi.

    Qiyinligi ko'rsatilmagan savol (`None`) alohida guruh emas — u o'rta
    (2) deb hisoblanadi, aks holda `NULL` li fanlar bitta guruhga tushib
    aralashtirish ma'nosiz bo'lardi.
    """
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
    # `ge=1` MAJBURIY: usiz `limit=-1` `pool_size` ni manfiy qilib,
    # `SELECT ... LIMIT -4` bilan Postgres xatosiga (500) olib borardi.
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

    # ---- 1) Ko'rilmagan savollar birinchi ---------------------------------
    #
    # NEGA. Ilgari tanlov shunchaki `ORDER BY random() LIMIT n` edi. Kichik
    # bo'limda (masalan 9 ta savol) o'quvchi ikkinchi mashqda deyarli o'sha
    # savollarni oldi — takroriy savol esa XP bermaydi, ya'ni u ishlab
    # turgan ilovani "buzuq" deb qabul qildi.
    #
    # Endi avval JAVOB BERILMAGANLARI olinadi. Yetmasa — qolgani eskilardan
    # to'ldiriladi (savolsiz qolgandan ko'ra takror yaxshi).
    #
    # Mehmonda `submissions` bo'ylab filtr yo'q: mehmon bitta umumiy hisob,
    # ya'ni "u ko'rgan" degan tushuncha ma'nosiz.
    #
    # `POOL_FACTOR` — qiyinlik aralashtirish uchun keragidan ko'p olinadi,
    # keyin Python'da saralanadi. 200 chegarasi: bitta so'rov bankning
    # katta qismini tortib olmasin (anti-scraping bilan bir mantiqda).
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


# --------------------------------------------------------------------------- #
#  Submit + grade (server is the only judge)                                  #
# --------------------------------------------------------------------------- #
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

    # ---- challenge key protection -------------------------------------------
    # /v1/challenges/{id}/questions hands a participant the frozen question ids —
    # it has to, they need to play. But those same ids could be pushed through
    # THIS endpoint as ordinary practice, and the grade response would hand back
    # the key; the player then filled in a perfect challenge sheet. Every staked
    # bet was winnable that way. A question locks only while the caller still
    # owes a result: once their sheet is in, it returns to normal practice.
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
        # A malformed grading_spec (e.g. an mcq with two correct options) or a
        # type with no grader yet must not become a 500 in the middle of a drill.
        # services/challenges.py already made this call for the batch path; both
        # paths now behave identically: graded wrong, logged, never a crash.
        _log.exception("grading failed question_id=%s type=%s", q.id, q.type)
        result = GradeResult(question_id=str(q.id), is_correct=False,
                             score=0, max_score=q.max_score)

    # The key and the explanation are released ONLY on a correct answer.
    #
    # Returning them on a wrong answer opened a free farm: answer anything, read
    # correct_option_ids out of the response, resubmit. That cost one coin and
    # paid 10 XP + 5 coins + leaderboard points, on every question in the bank.
    # The explanation is withheld for the same reason — most of them name the
    # answer outright ("to'g'ri javob C, chunki...").
    if result.is_correct:
        result.correct_option_ids = list(
            (q.grading_spec or {}).get("correct_option_ids", []))
        lang = (accept_language or "uz-Latn").split(",")[0].strip()
        tr = (next((t for t in q.translations if t.lang == lang), None)
              or next((t for t in q.translations), None))
        if tr is not None:
            result.explanation = tr.explanation

    # Who answered: the JWT user if present, else the guest. The guest is a real
    # row so practice still persists, but it is kept off the leaderboards/progress.
    #
    # SECURITY: X-Debug-User-Id is NOT an identity mechanism. Without a valid JWT
    # the only identity an unauthenticated caller can have is the guest user —
    # accepting an arbitrary UUID here would let anyone write submissions, streaks,
    # XP/coins and leaderboard points into any victim's account. So the header is
    # accepted only when it names the guest UUID; anything else is treated as guest.
    if current_user is not None:
        user_id = current_user.id
    else:
        if x_debug_user_id and x_debug_user_id != _settings.guest_user_id:
            _log.warning(
                "rejected X-Debug-User-Id impersonation attempt: %r", x_debug_user_id)
        user_id = uuid.UUID(_settings.guest_user_id)
    is_guest = (str(user_id) == _settings.guest_user_id)

    # Persist BEST-EFFORT for the GUEST practice path only: a missing guest row
    # must never turn a correct answer into a wrong one. For AUTHENTICATED users a
    # persistence failure is a real error — we log it with context (never silently),
    # but still return the already-computed grade so the learner isn't penalized for
    # our storage problem. Submission + derived progress share one transaction so
    # XP/streak can't drift from the submission log.
    persisted = True
    awarded = False   # True only when this is the FIRST correct answer to this q
    # Mukofot hisoboti — javobga qo'shiladi, klient "+10 XP" chipini shundan
    # chizadi va "nega XP o'smadi" degan savol tug'ilmaydi.
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
            # ALL reward bookkeeping lives in a SAVEPOINT: if any of it fails
            # (constraint drift, race, future bug), only the rewards roll back —
            # the student's graded answer still commits and the response is
            # unaffected. Lesson from a live bug: a coin CHECK-constraint
            # violation here used to abort the whole transaction and turn a
            # correct answer into "Yuborilmadi" (HTTP 500).
            try:
                async with db.begin_nested():
                    # Streak advances on every answer (showing up counts).
                    prog = await progress_service.touch_activity(db, user_id)
                    # Daily login bonus rides on the same "first activity today"
                    # moment — a wiped-out balance recovers every day.
                    await coins.try_award_daily_login(
                        db, user_id,
                        datetime.now(timezone.utc).date().isoformat(),
                        _settings.coins_daily_login,
                    )
                    # XP + coins are minted once per question, and only on a
                    # correct answer. The coin ledger's unique guard is the
                    # source of truth for "first time", so re-answering a
                    # question can't farm XP or coins.
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
                        # Gentle penalty: small, floored at 0 (never negative);
                        # coins never gate practice — only challenge stakes.
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
        # Mehmonligi saqlanadi: klient uchun "saqlanmadi" sababi o'zgarmagan.
        reward_reason = "guest" if current_user is None else None
        if is_guest:
            _log.warning("guest submission not persisted question_id=%s", q_id_str)
        else:
            # real user: this is a genuine fault, surface it in logs with context
            _log.exception(
                "submission persist FAILED user_id=%s question_id=%s",
                user_id, q_id_str,
            )

    # Ranking lives in Redis, outside the DB transaction. Credit it only on the
    # first correct answer that actually persisted — same gate as XP, so the board
    # can't be farmed and can't credit an answer we failed to record.
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