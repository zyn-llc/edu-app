from __future__ import annotations
import asyncio, json, os, re, sys
from dataclasses import dataclass, field
from collections import defaultdict

SEEDED_SUBJECT_CODES = {
    "matematika","geometriya","fizika","kimyo","biologiya",
    "geografiya","ona_tili","jahon_tarixi","ozbekiston_tarixi","huquq",
}
SEEDED_LANGS = {"uz-Latn","ru"}
LANG_MAP = {"uz":"uz-Latn","uz-cyrl":"uz-Cyrl","ru":"ru","en":"en"}
PREFIX_SUBJECT_MAP = {
    "bio":"biologiya","geo":"geografiya","phy":"fizika","phys":"fizika",
    "math":"matematika","mat":"matematika","geom":"geometriya","chem":"kimyo",
    "hist":"ozbekiston_tarixi","wh":"jahon_tarixi","eng":"ingliz_tili","onatili":"ona_tili","law":"huquq",
}
LOADABLE_TYPES = {"mcq", "text_open"}



from app.services.grading import _parse_student_number  # noqa: E402
from app.services.normalizer import normalize as _normalize  # noqa: E402

NUMERIC_REL_TOLERANCE = 1e-3


ROUNDING_SPREAD = 5e-3

RISKY_KEYWORD_AS_DRAFT = True
_RISKY_ANSWER_RE = re.compile(r"[ ,;=()\[\]{}/]")


_TOPIC_NUMBER_RE = re.compile(r"^\d+(\.\d+)*\s*-\s*(§|bo['‘’ʻʼ]lim)\.?\s*")
_WRAPPED_RE = re.compile(r"^\(([^()]*)\)$")

def topic_title(code: str) -> str:
    t = code.replace("_", " ").strip()
    t = _TOPIC_NUMBER_RE.sub("", t).strip()
    m = _WRAPPED_RE.match(t)
    if m:
        t = m.group(1).strip()
    return t[:1].upper() + t[1:] if t else t

def parse_prefix(prefix):
    m = re.match(r"(.+?)_g(\d+)$", prefix)
    if m:
        tok, grade = m.group(1).lower(), int(m.group(2))
    else:
        tok, grade = prefix.lower(), None
    if tok in SEEDED_SUBJECT_CODES:
        return tok, grade
    subj = PREFIX_SUBJECT_MAP.get(tok) or PREFIX_SUBJECT_MAP.get(tok.split("_")[0])
    return subj, grade

def uz_join_key(row): return row.get("id", row.get("question_id"))
def stem_of(row): return (row.get("text") or row.get("question_text") or "").strip()

def answer_key(c, opt_ids):
    coid = c.get("correct_option_id")
    norm = coid[4:] if isinstance(coid, str) and coid.startswith("opt_") else coid
    ans = c.get("answer")
    cands = {str(x).strip().lower() for x in (norm, ans) if x is not None and str(x).strip()}
    if not cands: return None, "no answer key (correct_option_id/answer both empty)"
    if len(cands) > 1: return None, f"answer key disagreement: correct_option_id->{norm!r} vs answer->{ans!r}"
    key_lc = cands.pop()
    match = [oid for oid in opt_ids if str(oid).strip().lower() == key_lc]
    if not match: return None, f"answer key {key_lc!r} not in options {opt_ids}"
    return match[0], None

def join_layers(core, langs):
    by = defaultdict(dict)
    for arr in langs:
        for row in arr:
            qid = uz_join_key(row)
            lang = LANG_MAP.get(row.get("lang","uz"), row.get("lang","uz"))
            if qid is not None: by[qid][lang] = row
    for c in core: yield c, by.get(c.get("id"), {})

@dataclass
class IngestOption:
    option_key: str; position: int; texts: dict

@dataclass
class IngestQuestion:
    source_id: str; subject_code: str; topic_code: str | None
    grade: int | None; difficulty: int; status: str
    exam_context: list; media: dict | None; tags: dict
    grading_spec: dict; stems: dict; explanations: dict
    options: list = field(default_factory=list)
    # Backend `QuestionType`: mcq | numeric | open_keyword | ...
    qtype: str = "mcq"

def _media_of(c, langrows):
    
    media = c.get("media")
    if media:
        return media
    for r in langrows.values():
        ref = r.get("image_ref")
        if ref:
            return {"type": "image", "ref": ref}
    return None

def text_open_spec(c):
    

   
    spec = c.get("grading_spec") or {}
    forms = spec.get("accepted_forms") or spec.get("accepted") or []
    if isinstance(forms, str):
        forms = [forms]
    forms = [str(f).strip() for f in forms if str(f).strip()]
    if not forms:
        return None, None, False, "text_open: accepted_forms bo'sh — baholab bo'lmaydi"

    nums, unparsed = [], False
    for f in forms:
        try:
            nums.append(_parse_student_number(f))
        except Exception:
            unparsed = True

    if nums and not unparsed:
        lo, hi = min(nums), max(nums)
        spread = hi - lo
        scale = max(abs(lo), abs(hi))

        if spread <= 1e-9:
            v = nums[0]
            tol = 0.0 if float(v).is_integer() else abs(v) * NUMERIC_REL_TOLERANCE
            return "numeric", {"value": v, "tolerance": tol}, False, None

       
        if scale > 0 and spread <= scale * ROUNDING_SPREAD:
            v = (lo + hi) / 2.0
            tol = max(spread / 2.0, abs(v) * NUMERIC_REL_TOLERANCE)
            return "numeric", {"value": v, "tolerance": tol}, False, None

        norm = [_normalize(f) for f in forms]
        risky = any(_RISKY_ANSWER_RE.search(n) for n in norm)
        return "open_keyword", {"accepted": forms}, risky, None

    norm = [_normalize(f) for f in forms]
    risky = any(_RISKY_ANSWER_RE.search(n) for n in norm) or any(len(n) > 40 for n in norm)
    return "open_keyword", {"accepted": forms}, risky, None

def build(c, langrows, bank_subject, bank_grade):
    """Return (verdict, obj_or_reason). verdict in OK/WARN/SKIP/ERROR."""
    cid = c.get("id")
    if not cid: return "ERROR","core row missing 'id'"
    if ("active" in c and not c["active"]) or (c.get("status","active") != "active"):
        return "SKIP", f"inactive (active={c.get('active')}, status={c.get('status')})"
    src_type = c.get("type", "mcq")
    if src_type not in LOADABLE_TYPES:
        return "SKIP", f"qo'llab-quvvatlanmaydigan tur '{src_type}'"
    if not langrows: return "ERROR","no uz/lang content joined"
    bad = [l for l in langrows if l not in SEEDED_LANGS]
    if bad: return "ERROR", f"lang(s) not seeded: {bad}"
    empty = [l for l,r in langrows.items() if not stem_of(r)]
    if empty: return "ERROR", f"empty stem for lang(s) {empty}"
    if bank_subject is None: return "ERROR","unknown bank prefix -> subject"
    if bank_subject not in SEEDED_SUBJECT_CODES: return "ERROR", f"subject '{bank_subject}' not seeded"

    verdict = "OK"
    options = []
    risky_answer = False

    if src_type == "mcq":
        any_lang = next(iter(langrows))
        opts = langrows[any_lang].get("options") or []
        opt_ids = [o.get("id") for o in opts]
        if len(opt_ids) < 2: return "ERROR", f"only {len(opt_ids)} option(s)"
        if None in opt_ids: return "ERROR","option missing 'id'"
        if len(set(opt_ids)) != len(opt_ids):
            d = sorted({x for x in opt_ids if opt_ids.count(x) > 1})
            return "ERROR", f"duplicate option id(s) {d}"
        key, kerr = answer_key(c, opt_ids)
        if kerr: return "ERROR", kerr
        qtype, grading_spec = "mcq", {"correct_option_ids": [key]}
        for pos, oid in enumerate(opt_ids):
            texts = {}
            for lang, row in langrows.items():
                o = next((o for o in (row.get("options") or []) if o.get("id") == oid), None)
                if o: texts[lang] = o.get("text","")
            options.append(IngestOption(oid, pos, texts))
    else:
        qtype, grading_spec, risky_answer, terr = text_open_spec(c)
        if terr: return "ERROR", terr

    
    has_image = bool(c.get("media")) or any(
        r.get("has_image") or r.get("image_ref") for r in langrows.values())
    status = c.get("status", "active")
    if has_image and IMAGE_QUESTIONS_AS_DRAFT and status == "active":
        status = "draft"
        verdict = "WARN"
    if risky_answer and RISKY_KEYWORD_AS_DRAFT and status == "active":
        status = "draft"
        verdict = "WARN"

    diff = c.get("difficulty", 2)
    if not isinstance(diff, int) or not (1 <= diff <= 5):
        diff, verdict = 2, "WARN"
    if "ru" not in langrows: verdict = "WARN"

    obj = IngestQuestion(
        source_id=cid, subject_code=bank_subject, topic_code=c.get("topic"),
        grade=c.get("grade") if c.get("grade") is not None else bank_grade,
        difficulty=diff,
        status=status,
        exam_context=c.get("exam_context") or [],
        media=_media_of(c, langrows),
        tags={"subtopic": c.get("subtopic"), "skill_tags": c.get("skill_tags",[]),
              "concept_tags": c.get("concept_tags",[]), "legacy_id": c.get("legacy_id"),
              "risky_answer": risky_answer or None,
              "source_type": src_type if src_type != "mcq" else None},
        grading_spec=grading_spec,
        stems={l: stem_of(r) for l, r in langrows.items()},
        explanations={l: r.get("explanation","") for l, r in langrows.items()},
        options=options,
        qtype=qtype,
    )
    return verdict, obj

def discover_banks(paths):
    root = paths[0]
    if os.path.isdir(root) and os.path.exists(os.path.join(root,"core.json")): dirs=[root]
    else: dirs = sorted(os.path.join(root,d) for d in os.listdir(root)
                        if os.path.exists(os.path.join(root,d,"core.json")))
    for bd in dirs:
    
        prefix = os.path.basename(os.path.normpath(bd))
        subj, grade = parse_prefix(prefix)
        core = json.load(open(os.path.join(bd,"core.json"), encoding="utf-8"))
        langs = [json.load(open(os.path.join(bd,lf), encoding="utf-8"))
                 for lf in ("uz.json","ru.json") if os.path.exists(os.path.join(bd,lf))]
        yield prefix, core, langs, subj, grade

def plan(paths):
   
    records, report = [], []
    grand = defaultdict(int)
    for label, core, langs, subj, grade in discover_banks(paths):
        b = defaultdict(int); errs=[]; skips=defaultdict(int)
        for c, lr in join_layers(core, langs):
            v, o = build(c, lr, subj, grade)
            b[v]+=1; grand[v]+=1
            if v in ("OK","WARN"): records.append(o)
            elif v == "ERROR": errs.append(f"    ERROR {c.get('id')}: {o}")
            else: skips[o]+=1
        load = b["OK"]+b["WARN"]
        report.append((label, subj, len(core), load, b["SKIP"], b["ERROR"], skips, errs))
    return records, report, grand

def print_report(report, grand):
    for label, subj, rows, load, skip, err, skips, errs in report:
        print(f"[{label:<14}] rows={rows:>5}  load={load:>5}  skip={skip:>4}  ERROR={err:>4}"
              + (f"  subj={subj}" if subj else "  subj=?"))
        for r,n in sorted(skips.items(), key=lambda kv:-kv[1]): print(f"        skip {n:>5}: {r}")
        for line in errs[:15]: print(line)
        if len(errs)>15: print(f"        ... +{len(errs)-15} more")
    print("="*60)
    print(f"GRAND  load={grand['OK']+grand['WARN']}  skip={grand['SKIP']}  errors={grand['ERROR']}")

async def load(records, batch=200):
    from sqlalchemy import select, text
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
    from app.core.config import get_settings
    from app.models import (Option, OptionTranslation, Question, QuestionTranslation,
                            Subject, Topic, TopicTranslation)

  
    from app.ingest.dsn import resolve_url
    url = resolve_url()

    engine = create_async_engine(url, pool_pre_ping=True)
    Session = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with engine.connect() as c:
            before = (await c.execute(text("SELECT count(*) FROM questions"))).scalar()
        print()
        print("DB ulanish OK. Hozirgi questions soni:", before)
    except Exception as e:
        print()
        print("!! DB ULANMADI:", type(e).__name__, str(e)[:200])
        print("   Diagnostika:  python -m app.ingest.db_check")
        await engine.dispose()
        return 1

    inserted = skipped = failed = 0
    subj_ids, topic_cache = {}, {}
    total = len(records)
    print("Yuklanmoqda:", total, "savol (batch =", str(batch) + ")")

    try:
        for start in range(0, total, batch):
            chunk = records[start:start + batch]
            async with Session() as db:
                for it in chunk:
                    try:
                        if it.subject_code not in subj_ids:
                            sid = (await db.execute(select(Subject.id).where(
                                Subject.code == it.subject_code))).scalar_one_or_none()
                            if sid is None:
                                print("  !! subject not seeded:", it.subject_code)
                                failed += 1
                                continue
                            subj_ids[it.subject_code] = sid
                        sid = subj_ids[it.subject_code]

                        exists = (await db.execute(select(Question.id).where(
                            Question.source_ref == it.source_id))).scalar_one_or_none()
                        if exists:
                            skipped += 1
                            continue

                        tid = None
                        if it.topic_code:
                            ck = (sid, it.topic_code)
                            if ck in topic_cache:
                                tid = topic_cache[ck]
                            else:
                                tid = (await db.execute(select(Topic.id).where(
                                    Topic.subject_id == sid,
                                    Topic.code == it.topic_code))).scalar_one_or_none()
                                if tid is None:
                                    t = Topic(subject_id=sid, code=it.topic_code)
                                    db.add(t)
                                    await db.flush()
                                    tid = t.id
                                    db.add(TopicTranslation(
                                        topic_id=tid, lang="uz-Latn",
                                        title=topic_title(it.topic_code)))
                                topic_cache[ck] = tid

                        q = Question(subject_id=sid, topic_id=tid, grade=it.grade,
                                     exam_context=it.exam_context or None, type=it.qtype,
                                     difficulty=it.difficulty, status=it.status,
                                     grading_spec=it.grading_spec, media=it.media,
                                     tags=it.tags, source_ref=it.source_id)
                        db.add(q)
                        await db.flush()
                        for lang, stem in it.stems.items():
                            db.add(QuestionTranslation(question_id=q.id, lang=lang, stem=stem,
                                                       explanation=it.explanations.get(lang)))
                        for opt in it.options:
                            o = Option(question_id=q.id, option_key=opt.option_key,
                                       position=opt.position)
                            db.add(o)
                            await db.flush()
                            for lang, txt in opt.texts.items():
                                db.add(OptionTranslation(option_id=o.id, lang=lang, text=txt))
                        inserted += 1
                    except Exception as e:
                        failed += 1
                        print("  !!", it.source_id, type(e).__name__, str(e)[:120])
                        await db.rollback()
                await db.commit()
            done = min(start + batch, total)
            print("  ", done, "/", total, " inserted=", inserted,
                  " skipped=", skipped, " failed=", failed, sep="")
    finally:
        try:
            async with engine.connect() as c:
                after = (await c.execute(text("SELECT count(*) FROM questions"))).scalar()
            print()
            print("LOAD done: inserted=", inserted, " skipped(existing)=", skipped,
                  " failed=", failed, sep="")
            print("questions jadvalida endi:", after)
        except Exception:
            pass
        await engine.dispose()
    return 0

def main(argv):
    dry = "--dry-run" in argv
    paths = [a for a in argv if a != "--dry-run"]
    if not paths: print(__doc__); return 2
    records, report, grand = plan(paths)
    print_report(report, grand)
    if dry:
        print(f"DRY-RUN: {len(records)} question(s) would be inserted, "
              f"{grand['ERROR']} error-row(s) skipped. Nothing written.")
        return 1 if grand["ERROR"] else 0
    if grand["ERROR"]:
        print(f"NOTE: {grand['ERROR']} error-row(s) excluded from load (see above).")
    return asyncio.run(load(records))

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
