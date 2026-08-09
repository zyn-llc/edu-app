"""
Foydalanuvchi nomi + parol bilan kirish.

  POST /v1/auth/register   {username, password, ...}  -> yangi hisob + token
  POST /v1/auth/login      {username, password}       -> token
  POST /v1/auth/password   {username?, password}      -> mavjud hisobga parol qo'shish
  GET  /v1/auth/username-free?username=...            -> nom bo'shmi

NEGA ALOHIDA FAYL. `auth.py` telefon+OTP oqimiga bag'ishlangan va u yerda
`_require_phone_login()` kabi SMS'ga bog'liq mantiq bor. Parol yo'li SMS'dan
mutlaqo mustaqil — aralashtirsak, Eskiz yoqilganda ikkalasi bir-biriga
xalaqit beradi.

XAVFSIZLIK QARORLARI

1. **Parol uzunligi 6 dan boshlanadi, murakkablik talab qilinmaydi.**
   Foydalanuvchi — 5–11-sinf o'quvchisi. "Kamida bitta katta harf va belgi"
   talabi amalda ikki narsaga olib keladi: `Parol1!` yoki umuman voz kechish.
   Kuchni parolga emas, **urinishlar soniga** qo'yamiz (3-band).

2. **Parol tiklash YO'Q.** Elektron pochta ham, SMS ham yo'q — ya'ni
   "parolni unutdim" oqimini xavfsiz qurishning iloji yo'q. Buning o'rniga
   klient parol o'rnatgan foydalanuvchini Telegram'ni ham ulashga undaydi:
   Telegram tiklash yo'li bo'lib xizmat qiladi (`POST /v1/auth/password`
   bilan yangi parol qo'yiladi).

3. **Urinishlar cheklovi ikki o'lchamda.** IP bo'yicha soatiga 40 ta va
   FOYDALANUVCHI NOMI bo'yicha soatiga 10 ta. Faqat IP bo'yicha cheklash
   O'zbekistonda ishlamaydi: maktab Wi-Fi'si va uyali internet NAT ortida,
   bitta IP ortida o'nlab o'quvchi bo'ladi. Faqat nom bo'yicha cheklash esa
   nomlarni ketma-ket sinab ko'rishga yo'l ochadi. Ikkalasi birga kerak.

4. **Xato sababi oshkor qilinmaydi.** "Bunday foydalanuvchi yo'q" va "parol
   noto'g'ri" bir xil javob beradi — aks holda ro'yxatdan o'tganlar ro'yxatini
   yig'ib olish mumkin bo'lardi. Ro'yxatdan o'tishda esa aksincha: nom band
   ekani ochiq aytiladi, chunki usiz ro'yxatdan o'tib bo'lmaydi.

5. **Ro'yxatdan o'tish (2026-08-07) taklif kodi talab qiladi** —
   `settings.require_invite_for_password_register` orqali yoqilgan/
   o'chirilgan. SABAB: bu yo'l SMS'ga ham, Telegram'ga ham bog'liq emas,
   ya'ni "haqiqiy odam" ekanini tasdiqlaydigan tashqi qatlam yo'q edi.
   Yagona to'siq — IP bo'yicha soatiga 40 so'rov — bot uchun jiddiy
   to'siq emas (proksi bilan aylanib o'tiladi). Yopiq beta davrida kod
   `invites.py` bilan BIR XIL jadvaldan (`invite_codes`) o'qiladi va
   xuddi shunday atomik tarzda sarflanadi — ikkita alohida "kirish
   eshigi" emas, bitta havzaning ikki fasadi. Kirish (LOGIN) bunga
   bog'liq emas: mavjud hisob doim parol bilan kira oladi.
"""
from __future__ import annotations

import logging
import re
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import func, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.v1.invites import normalize_code
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.ratelimit import client_ip, hit as ratelimit_hit
from app.core import names
from app.core.regions import REGION_CODES
from app.core.security import hash_password, verify_password
from app.models import InviteRedemption, RefreshToken, User, UserProgress
from app.schemas.auth import TokenPair
from app.services import auth as auth_service

router = APIRouter(prefix="/v1/auth", tags=["auth"])
_settings = get_settings()
_log = logging.getLogger("bilim.password")

USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,20}$")

# Xizmat yo'llari bilan chalkashmasin va boshqa foydalanuvchini aldash uchun
# ishlatilmasin ("admin" nomi bilan yozib, boshqalarga xabar yozish).
RESERVED = {
    "admin", "administrator", "root", "topagon", "support", "help",
    "moderator", "system", "bot", "official", "rasmiy", "api", "me",
    "null", "undefined", "guest", "mehmon",
}

_IP_HOURLY = 40
_NAME_HOURLY = 10


def _norm(raw: str | None) -> str:
    """Bo'sh joylarni kesadi. Katta-kichik harf SAQLANADI — foydalanuvchi
    o'zi yozgan shakl profilda ko'rinadi; solishtirish `lower()` bilan."""
    return (raw or "").strip()


def _validate_username(raw: str) -> str:
    name = _norm(raw)
    if not USERNAME_RE.match(name):
        raise AppError(
            400, "Invalid username",
            "foydalanuvchi nomi 3–20 belgidan iborat bo'lsin: lotin harflari, "
            "raqamlar va pastki chiziq",
            type_="urn:bilim:auth:bad_username")
    if name.lower() in RESERVED:
        raise AppError(409, "Username taken", "bu nom band",
                       type_="urn:bilim:auth:username_taken")
    return name


def _validate_password(raw: str) -> str:
    pw = raw or ""
    if len(pw) < 6:
        raise AppError(400, "Weak password",
                       "parol kamida 6 belgidan iborat bo'lsin",
                       type_="urn:bilim:auth:weak_password")
    if len(pw) > 128:
        # argon2 uzun satrni ham hazm qiladi, lekin chegara qo'yilmasa
        # megabaytlik "parol" CPU'ni band qiladi.
        raise AppError(400, "Password too long", "parol juda uzun")
    return pw


async def _find_by_username(db: AsyncSession, name: str) -> User | None:
    return (await db.execute(
        select(User).where(func.lower(User.username) == name.lower())
    )).scalar_one_or_none()


async def _guard(request: Request, bucket: str, name: str) -> None:
    """IP + foydalanuvchi nomi bo'yicha ikki qatlamli cheklov."""
    # `fail_closed`: Redis uzilganda bu chegara YO'QOLSA, 6 belgilik minimal
    # parolga qarshi hech narsa qolmaydi. Uzilish paytida qisqa 429 —
    # taxmin qilib kirilgan hisobdan arzonroq.
    ip = client_ip(request)
    ok_ip, _ = await ratelimit_hit(f"{bucket}_ip", ip, _IP_HOURLY, 3600,
                                   fail_closed=True)
    ok_name, _ = await ratelimit_hit(f"{bucket}_name", name.lower(),
                                     _NAME_HOURLY, 3600, fail_closed=True)
    if not (ok_ip and ok_name):
        raise AppError(429, "Too many attempts",
                       "juda ko'p urinish — bir oz kutib qayta urining")


# --------------------------------------------------------------------------- #
class RegisterIn(BaseModel):
    username: str = Field(min_length=3, max_length=20)
    password: str = Field(min_length=6, max_length=128)
    display_name: str | None = Field(default=None, max_length=40)
    grade: int | None = Field(default=None, ge=1, le=11)
    region_code: str | None = None
    # Faqat `require_invite_for_password_register=true` bo'lganda majburiy
    # (yopiq beta). `invites.py` dagi kodlar bilan bir xil jadval.
    invite_code: str | None = Field(default=None, min_length=4, max_length=32)
    # "Do'stlaringizni taklif qiling" havolasidan (`?ref=<username>`)
    # kelgan bo'lsa. Ixtiyoriy, mukofotsiz — faqat statistika.
    referred_by: str | None = Field(default=None, max_length=20)


class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=20)
    password: str = Field(min_length=1, max_length=128)


class SetPasswordIn(BaseModel):
    """Mavjud hisobga (Telegram yoki taklif kodi bilan yaratilgan) parol
    qo'shish. `username` faqat hisobda hali nom bo'lmaganda talab qilinadi."""
    username: str | None = Field(default=None, max_length=20)
    password: str = Field(min_length=6, max_length=128)


# --------------------------------------------------------------------------- #
@router.get("/username-free")
async def username_free(
    username: str = Query(min_length=1, max_length=20),
    db: AsyncSession = Depends(get_db),
):
    """Klient yozayotgan paytda tekshiradi — forma yuborilgach "band" degan
    xatoni ko'rish yomon tajriba.

    Ataylab hech qanday cheklovsiz va autentifikatsiyasiz: bu yerda oshkor
    bo'ladigan yagona narsa — nom bandmi yoki yo'q, u esa ro'yxatdan o'tish
    formasida baribir ma'lum bo'ladi.
    """
    name = _norm(username)
    if not USERNAME_RE.match(name):
        return {"username": name, "free": False, "reason": "shape"}
    if name.lower() in RESERVED:
        return {"username": name, "free": False, "reason": "reserved"}
    taken = await _find_by_username(db, name) is not None
    return {"username": name, "free": not taken,
            "reason": "taken" if taken else None}


@router.post("/register", response_model=TokenPair)
async def register(
    body: RegisterIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    name = _validate_username(body.username)
    pw = _validate_password(body.password)
    await _guard(request, "pw_register", name)

    if body.region_code is not None and body.region_code not in REGION_CODES:
        raise AppError(400, "Invalid region", "noma'lum hudud kodi")

    if await _find_by_username(db, name) is not None:
        raise AppError(409, "Username taken",
                       "bu nom allaqachon band — boshqasini tanlang",
                       type_="urn:bilim:auth:username_taken")

    # --- Taklif kodi (botlarga qarshi yagona haqiqiy to'siq) ---------------
    #
    # NEGA SHU YERDA, username tekshiruvidan KEYIN. Kodni band qilish
    # (used_count++) qaytarib bo'lmaydigan amal — avval arzon tekshiruvlar
    # (nom shakli, band-emasligi) o'tsin, keyin qimmat/bir martalik resurs
    # sarflansin. Aks holda "nom band" xatosi kelgan har bir urinish ham
    # birovning taklif kodini behuda yeb qo'yardi.
    invite_row = None
    if _settings.require_invite_for_password_register:
        code = normalize_code(body.invite_code or "")
        if not code:
            raise AppError(400, "Invite code required",
                           "ro'yxatdan o'tish uchun taklif kodi kerak",
                           type_="urn:bilim:auth:invite_required")
        # Atomik: invites.py dagi bilan bir xil SQL, bitta havza.
        invite_row = (await db.execute(text("""
            UPDATE invite_codes
               SET used_count = used_count + 1
             WHERE code = :code
               AND is_active
               AND used_count < max_uses
               AND (expires_at IS NULL OR expires_at > now())
            RETURNING code, grade, region_code
        """), {"code": code})).mappings().first()
        if invite_row is None:
            await db.rollback()
            raise AppError(401, "Invalid code",
                           "kod noto'g'ri, ishlatilib bo'lingan yoki "
                           "muddati o'tgan",
                           type_="urn:bilim:auth:invite_required")

    referred_by = await auth_service.resolve_referrer(db, body.referred_by, name)

    user = User(
        phone=None,
        role="student",
        username=name,
        password_hash=hash_password(pw),
        # Ism boshqalarga ko'rinadi -> `names` filtri. Yaroqsiz bo'lsa
        # foydalanuvchi nomi ishlatiladi (u allaqachon tekshirilgan).
        display_name=(names.safe_name(body.display_name) or name),
        grade=body.grade if body.grade is not None
              else (invite_row["grade"] if invite_row else None),
        region_code=body.region_code or
                    (invite_row["region_code"] if invite_row else None),
        referred_by=referred_by,
        locale=_settings.default_lang,
    )
    db.add(user)
    try:
        await db.flush()
    except Exception:
        # Ikki kishi bir soniyada bir xil nomni yuborsa qismiy noyob indeks
        # ikkinchisini rad etadi. Bu kutilgan holat, 500 emas.
        # Taklif kodi BEHUDA KETMAYDI: `UPDATE invite_codes` va bu `flush()`
        # bitta tranzaksiya ichida, ya'ni `rollback()` ikkalasini ham bekor
        # qiladi — foydalanuvchi kodni qayta, muvaffaqiyatli urinishda
        # ishlata oladi.
        await db.rollback()
        raise AppError(409, "Username taken", "bu nom allaqachon band",
                       type_="urn:bilim:auth:username_taken")

    db.add(UserProgress(user_id=user.id))
    if invite_row is not None:
        db.add(InviteRedemption(code=invite_row["code"], user_id=user.id))
    await db.flush()
    pair = await auth_service.issue_token_pair(db, user)
    await db.commit()
    _log.info("password register: user=%s invite=%s", user.id,
               invite_row["code"] if invite_row else None)
    return pair


@router.post("/login", response_model=TokenPair)
async def login(
    body: LoginIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    name = _norm(body.username)
    await _guard(request, "pw_login", name)

    user = await _find_by_username(db, name) if name else None

    # Vaqt hujumiga qarshi. Foydalanuvchi topilmasa ham argon2 bir marta
    # ishlatiladi: aks holda "nom yo'q" javobi bir necha millisekundda,
    # "parol noto'g'ri" esa ~100 ms da qaytardi va shu farq orqali qaysi
    # nomlar mavjudligini aniqlab olish mumkin bo'lardi.
    stored = user.password_hash if (user and user.password_hash) else None
    if stored:
        ok = verify_password(body.password, stored)
    else:
        hash_password(body.password)   # natijasi kerak emas, vaqti kerak
        ok = False

    if not ok or user is None or not user.is_active:
        raise AppError(401, "Invalid credentials",
                       "foydalanuvchi nomi yoki parol noto'g'ri",
                       type_="urn:bilim:auth:bad_credentials")

    pair = await auth_service.issue_token_pair(db, user)
    await db.commit()
    return pair


@router.post("/password")
async def set_password(
    body: SetPasswordIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Kirgan foydalanuvchi o'ziga parol o'rnatadi yoki almashtiradi.

    Telegram bilan kirgan o'quvchi shu yerda nom+parol qo'yadi va keyingi
    safar Telegram'siz kira oladi. Teskarisi ham to'g'ri: parol bilan
    ro'yxatdan o'tgan o'quvchi Telegram'ni ulab, uni tiklash yo'li sifatida
    ishlatadi.

    Eski parolni so'ramaymiz, chunki bu yerga faqat amaldagi access token
    bilan kirib bo'ladi — ya'ni sessiya allaqachon isbotlangan.
    """
    pw = _validate_password(body.password)

    if not user.username:
        if not body.username:
            raise AppError(400, "Username required",
                           "avval foydalanuvchi nomini tanlang",
                           type_="urn:bilim:auth:username_required")
        name = _validate_username(body.username)
        existing = await _find_by_username(db, name)
        if existing is not None and existing.id != user.id:
            raise AppError(409, "Username taken", "bu nom allaqachon band",
                           type_="urn:bilim:auth:username_taken")
        user.username = name
    elif body.username and body.username.strip().lower() != user.username.lower():
        # Nomni almashtirish ataylab yopiq: reyting, bellashuv havolalari va
        # ota-ona ekranida nom ko'rinadi, uni erkin almashtirish chalkashlik
        # va o'zgani nomiga kirib olish uchun yo'l ochadi.
        raise AppError(409, "Username locked",
                       "foydalanuvchi nomini o'zgartirib bo'lmaydi",
                       type_="urn:bilim:auth:username_locked")

    user.password_hash = hash_password(pw)

    # Parol o'rnatish/almashtirish = "boshqa hamma joydan chiqar". Ilgari eski
    # refresh tokenlar 30 kun yashab qolardi: tokenini o'g'irlatgan odam
    # parolni almashtirib ham hujumchini quva olmasdi, holbuki parolni
    # almashtirish — odamning aynan shu holatdagi birinchi refleksi.
    #
    # Chaqiruvchining o'zi ichkarida qoladi: quyida unga YANGI juftlik
    # beriladi. Klient uni saqlashi SHART, aks holda o'zini chiqarib yuboradi.
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id,
               RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(timezone.utc))
    )
    pair = await auth_service.issue_token_pair(db, user)
    await db.commit()
    return {"ok": True, "username": user.username, **pair.model_dump()}
