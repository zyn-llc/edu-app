#!/usr/bin/env python3
"""
preflight.py — deploy'dan OLDINGI tekshiruv.

    PYTHONPATH=. python scripts/preflight.py            # lokal
    docker compose -f docker-compose.prod.yml exec api python scripts/preflight.py

Nima uchun kerak: deploy paytida yiqiladigan narsalarning aksariyati kod emas,
KONFIGURATSIYA va MA'LUMOT. Ular `pytest` da ko'rinmaydi, chunki testlar soxta
baza bilan ishlaydi. Bu skript haqiqiy muhitga qarab, ishga tushirishdan oldin
"bularning hammasi joyidami?" degan savolga javob beradi.

Chiqish kodi:
    0 — hammasi joyida (ogohlantirish bo'lishi mumkin)
    1 — kamida bitta FATAL muammo, deploy qilma

HECH QANDAY SIRNI CHOP ETMAYDI. Tokenlar va parollar faqat "bor / yo'q" va
uzunlik sifatida ko'rsatiladi.
"""
from __future__ import annotations

import asyncio
import os
import re
import sys
from pathlib import Path

# Skript `scripts/` ichida yotadi, `app` paketi esa bir daraja yuqorida.
# Python `sys.path[0]` ga skriptning O'Z papkasini qo'yadi, shuning uchun
# `python scripts/preflight.py` da `import app` topilmaydi
# (ModuleNotFoundError: No module named 'app'). Loyiha ildizini qo'lda
# qo'shamiz — shunda `PYTHONPATH` ni eslash shart emas, konteynerda ham,
# hostda ham ishlaydi.
_ROOT = Path(__file__).resolve().parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

OK = "  OK   "
WARN = " OGOH  "
FAIL = " XATO  "

_fatal = 0
_warn = 0


def say(level: str, text: str, detail: str = "") -> None:
    global _fatal, _warn
    if level is FAIL:
        _fatal += 1
    elif level is WARN:
        _warn += 1
    print(f"[{level}] {text}" + (f"\n         {detail}" if detail else ""))


def head(title: str) -> None:
    print(f"\n--- {title} " + "-" * max(0, 58 - len(title)))


def resolve_url(url: str) -> str:
    """DSN'ni ishlayotgan muhitga moslaydi.

    HOSTDA: `db:5432` hal bo'lmaydi -> `127.0.0.1`. KONTEYNERDA: o'zgarishsiz,
    chunki u yerda `127.0.0.1` — api konteynerining o'zi, Postgres emas.
    Ilgari almashtirish shartsiz edi va aynan prodda (`docker compose exec api
    python scripts/preflight.py`) "Postgres ULANMADI" degan YOLG'ON fatal
    xato berardi. Mantiq `app/ingest/dsn.py` da, bitta joyda.
    """
    from app.ingest.dsn import resolve_url as _resolve
    return _resolve(url)


# --------------------------------------------------------------------------- #
#  1. Konfiguratsiya                                                          #
# --------------------------------------------------------------------------- #
def check_config():
    from app.core.config import get_settings
    s = get_settings()

    head("KONFIGURATSIYA")
    print(f"         environment = {s.environment}   app_name = {s.app_name}")

    problems = s.validate_runtime()
    if problems:
        for p in problems:
            say(FAIL if s.is_prod else WARN, "guard qanoatlanmadi", p)
    else:
        say(OK, "prod guard'lari qanoatlantirildi" if s.is_prod
                else "dev rejimi — prod guard'lari tekshirilmadi")

    # Sirlar: faqat mavjudligi va uzunligi.
    for name, val in (("JWT_SECRET", s.jwt_secret),
                      ("ADMIN_API_KEY", s.admin_api_key),
                      ("TELEGRAM_BOT_TOKEN", s.telegram_bot_token),
                      ("TELEGRAM_WEBHOOK_SECRET", s.telegram_webhook_secret)):
        state = f"bor ({len(val)} belgi)" if val else "yo'q"
        print(f"         {name:<24} {state}")

    if s.is_prod and not s.admin_api_key:
        say(WARN, "ADMIN_API_KEY bo'sh — /v1/admin/* butunlay o'chiq",
            "retention va suspect_questions'ni ko'ra olmaysan")
    if s.is_prod and not s.trust_proxy_headers:
        say(WARN, "TRUST_PROXY_HEADERS=false, lekin nginx orqasidasan",
            "hamma so'rov bitta IP'dan ko'rinadi — IP bo'yicha cheklovlar ishlamaydi")

    # Kirish yo'llaridan kamida bittasi ochiq bo'lishi kerak.
    ways = []
    if s.sms_provider not in ("disabled",):
        ways.append(f"SMS ({s.sms_provider})")
    if s.invite_login_enabled:
        ways.append("taklif kodi")
    if s.telegram_login_enabled:
        ways.append("Telegram")
    if ways:
        say(OK, "kirish yo'llari: " + ", ".join(ways))
    else:
        say(FAIL, "hech qanday kirish yo'li yoq — foydalanuvchi tizimga kira olmaydi")

    return s


# --------------------------------------------------------------------------- #
#  2. Redis                                                                   #
# --------------------------------------------------------------------------- #
async def check_redis():
    head("REDIS")
    try:
        from app.core.redis import get_redis, close_redis
        r = get_redis()
        pong = await r.ping()
        say(OK if pong else FAIL, f"ping = {pong}")
        try:
            n = await r.zcard("lb:total")
            if n == 0:
                say(WARN, "lb:total bo'sh — reyting ko'rinmaydi",
                    "python -m app.ingest.rebuild_leaderboard")
            else:
                say(OK, f"lb:total = {n} ta yozuv")
        except Exception as e:
            say(WARN, "leaderboard o'qilmadi", f"{type(e).__name__}: {e}")
        await close_redis()
    except Exception as e:
        say(FAIL, "Redis ULANMADI — konteyner ishlayaptimi?",
            f"docker compose up -d redis   ({type(e).__name__})")


# --------------------------------------------------------------------------- #
#  3. Baza + kontent                                                          #
# --------------------------------------------------------------------------- #
async def check_db(settings):
    from sqlalchemy import text
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

    head("BAZA VA KONTENT")
    url = os.environ.get("DATABASE_URL") or settings.database_url
    engine = create_async_engine(resolve_url(url), pool_pre_ping=True)
    Session = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with Session() as db:
            # DIQQAT: `async with Session()` HALI ulanmaydi — SQLAlchemy
            # ulanishni birinchi so'rovgacha kechiktiradi. Shu sababli bu
            # yerda darhol `SELECT 1` qilamiz, aks holda "ulandi" deb yolg'on
            # OK chiqarib, keyin "schema_migrations yo'q" deb noto'g'ri
            # tashxis qo'yamiz (aslida sabab — Docker o'chiq).
            await db.execute(text("SELECT 1"))
            say(OK, "ulandi")

            # --- migratsiyalar ---
            try:
                applied = (await db.execute(text(
                    "SELECT count(*) FROM schema_migrations"))).scalar_one()
                say(OK, f"schema_migrations: {applied} ta qo'llangan")
                pending = [f for f in sorted(os.listdir("sql"))
                           if re.match(r"^\d{3}_.*\.sql$", f)]
                names = {r[0] for r in (await db.execute(
                    text("SELECT filename FROM schema_migrations"))).all()}
                missing = [f for f in pending if f not in names]
                if missing:
                    say(FAIL, f"{len(missing)} ta migratsiya qo'llanmagan",
                        ", ".join(missing) + "  →  ./scripts/migrate.sh")
                else:
                    say(OK, "barcha migratsiyalar qo'llangan")
            except Exception as e:
                if "does not exist" in str(e) or "UndefinedTable" in type(e).__name__:
                    say(FAIL, "schema_migrations jadvali yo'q",
                        "./scripts/migrate.sh hali bir marta ham ishlamagan")
                else:
                    say(FAIL, "migratsiyalar tekshirilmadi",
                        f"{type(e).__name__}: {str(e)[:160]}")

            # --- savollar ---
            rows = (await db.execute(text(
                "SELECT status, count(*) FROM questions GROUP BY status"))).all()
            counts = {s: c for s, c in rows}
            active = counts.get("active", 0)
            print(f"         savollar: " +
                  ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
            if active == 0:
                say(FAIL, "aktiv savol yo'q — ilova bo'sh ishga tushadi")
            elif active < 1000:
                say(WARN, f"faqat {active} ta aktiv savol — kontent to'liq yuklanmagan?")
            else:
                say(OK, f"{active} ta aktiv savol")

            # --- `media` tuzog'i ---
            # Bu ustunda SQL NULL emas, jsonb 'null' yotadi. `media IS NOT NULL`
            # yozgan har qanday UPDATE butun bankka tegadi. Shuni ko'rsatib
            # qo'yamiz — kelajakdagi o'zim uchun ogohlantirish.
            kinds = (await db.execute(text(
                "SELECT jsonb_typeof(media), count(*) FROM questions "
                "GROUP BY 1 ORDER BY 2 DESC"))).all()
            print("         media turlari: " +
                  ", ".join(f"{k or 'SQL NULL'}={c}" for k, c in kinds))
            nulls = sum(c for k, c in kinds if k == "null")
            if nulls:
                say(WARN, f"{nulls} qatorda jsonb 'null' turibdi",
                    "`media IS NOT NULL` ULARGA HAM ROST. To'g'ri shart: media ? 'ref'")

            # --- javob kaliti ---
            no_spec = (await db.execute(text(
                "SELECT count(*) FROM questions "
                "WHERE status='active' AND (grading_spec IS NULL "
                "      OR grading_spec = 'null'::jsonb)"))).scalar_one()
            if no_spec:
                say(FAIL, f"{no_spec} ta aktiv savolda grading_spec yo'q",
                    "ular baholanmaydi — javob har doim noto'g'ri chiqadi")
            else:
                say(OK, "hamma aktiv savolda grading_spec bor")

            # --- variantsiz savollar ---
            # Jadval nomi `options` (models/__init__.py), `question_options`
            # EMAS — eski nom bilan yozilgani uchun bu tekshiruv prodda
            # UndefinedTableError bilan yiqilardi.
            #
            # Tur nomi ham noto'g'ri edi: bazada `mcq`, `numeric`,
            # `open_keyword` bor; `single_choice`/`multi_choice` hech qachon
            # mos kelmagan, ya'ni tekshiruv aslida hech narsani tekshirmagan.
            no_opts = (await db.execute(text(
                "SELECT count(*) FROM questions q WHERE q.status='active' "
                "AND q.type = 'mcq' "
                "AND NOT EXISTS (SELECT 1 FROM options o "
                "                WHERE o.question_id = q.id)"))).scalar_one()
            if no_opts:
                say(FAIL, f"{no_opts} ta aktiv tanlovli savolda variant yo'q")
            else:
                say(OK, "tanlovli savollarning hammasida variant bor")

            # --- mehmon akkaunti ---
            guest = (await db.execute(text(
                "SELECT count(*) FROM users WHERE id = :g"),
                {"g": settings.guest_user_id})).scalar_one()
            if guest:
                say(OK, "mehmon akkaunti mavjud (login'siz mashq ishlaydi)")
            else:
                say(FAIL, "mehmon akkaunti yo'q",
                    "002_seed.sql qo'llanmagan — login'siz mashq 500 beradi")

            # --- fanlar ---
            subj = (await db.execute(text(
                "SELECT s.code, count(q.id) FILTER (WHERE q.status='active') "
                "FROM subjects s LEFT JOIN questions q ON q.subject_id = s.id "
                "GROUP BY s.code ORDER BY 2 DESC"))).all()
            print("         fanlar: " + ", ".join(f"{c}={n}" for c, n in subj))
            empty = [c for c, n in subj if n == 0]
            if empty:
                say(WARN, f"bo'sh fan(lar): {', '.join(empty)}",
                    "katalogda ko'rinadi, ochsang quiz boshlanmaydi")
    except Exception as e:
        name = type(e).__name__
        if name in ("ConnectionRefusedError", "OSError", "TimeoutError",
                    "ConnectionDoesNotExistError", "CannotConnectNowError"):
            say(FAIL, "Postgres ULANMADI — konteyner ishlayaptimi?",
                "docker compose up -d db   (Windows'da `localhost` emas, `127.0.0.1`)")
        else:
            say(FAIL, "baza tekshiruvi yiqildi", f"{name}: {str(e)[:200]}")
    finally:
        await engine.dispose()


# --------------------------------------------------------------------------- #
#  4. Kod invarianti: javob kaliti sizib chiqmaydimi                          #
# --------------------------------------------------------------------------- #
def check_leak_invariant():
    head("INVARIANT: JAVOB KALITI FAQAT SERVERDA")
    try:
        from app.schemas.question import PublicQuestion
        fields = set(PublicQuestion.model_fields)
        leaked = fields & {"grading_spec", "correct_option_ids", "answer",
                           "is_correct", "correct"}
        if leaked:
            say(FAIL, "PublicQuestion javob kalitini ochib qo'ygan",
                f"maydonlar: {', '.join(sorted(leaked))}")
        else:
            say(OK, "PublicQuestion'da javob kaliti yo'q")

        # Variant sxemasida ham bo'lmasin.
        from app.schemas.question import PublicOption
        oleak = set(PublicOption.model_fields) & {"is_correct", "correct", "weight"}
        if oleak:
            say(FAIL, "PublicOption javobni ochib qo'ygan",
                f"maydonlar: {', '.join(sorted(oleak))}")
        else:
            say(OK, "PublicOption'da javob belgisi yo'q")
    except Exception as e:
        say(WARN, "invariant tekshirilmadi", f"{type(e).__name__}: {e}")


# --------------------------------------------------------------------------- #
async def main() -> int:
    print("=" * 66)
    print("  Topag'on — PREFLIGHT")
    print("=" * 66)

    settings = check_config()
    check_leak_invariant()
    await check_redis()
    await check_db(settings)

    print("\n" + "=" * 66)
    if _fatal:
        print(f"  NATIJA: {_fatal} ta FATAL muammo, {_warn} ta ogohlantirish.")
        print("  DEPLOY QILMA — avval yuqoridagilarni tuzat.")
        print("=" * 66)
        return 1
    print(f"  NATIJA: fatal muammo yo'q, {_warn} ta ogohlantirish.")
    print("  Deploy'ga tayyor.")
    print("=" * 66)
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
