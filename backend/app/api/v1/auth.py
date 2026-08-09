"""
Auth endpoints — phone + OTP -> JWT.

  POST /v1/auth/otp/request   {phone, role}        -> sends (or dev-returns) a code
  POST /v1/auth/otp/verify    {phone, code, ...}   -> creates/loads user, token pair
  POST /v1/auth/refresh       {refresh_token}      -> rotates, new token pair
  POST /v1/auth/logout        {refresh_token}      -> revokes the refresh token
  GET  /v1/auth/me                                 -> current user profile
  PATCH/v1/auth/me            {display_name,...}    -> update own profile

Handlers stay thin: OTP logic in services/otp.py, user+token logic in
services/auth.py. The endpoint only decides dev-vs-prod code delivery.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.ratelimit import client_ip, hit as ratelimit_hit
from app.core.redis import get_redis
from app.core import names
from app.core.regions import REGION_CODES
from app.models import User
from app.schemas.auth import (
    OtpRequestIn, OtpRequestOut, OtpVerifyIn, ProfileUpdateIn, RefreshIn,
    TokenPair, UserOut,
)
from app.services import auth as auth_service
from app.services import otp as otp_service
from app.services import sms

router = APIRouter(prefix="/v1/auth", tags=["auth"])
_settings = get_settings()
_log = logging.getLogger("bilim.auth")

#: `users.locale` — `languages(code)` ga FK, va `sql/002_seed.sql` faqat
#: SHU IKKITASINI kiritadi. Ro'yxatga uchinchi til qo'shishdan oldin uni
#: `languages` ga ham kirit, aks holda FK buzilib 500 qaytadi. Ilova
#: lokalizatsiyasi ham aynan shu ikkisi (`lib/l10n/app_{uz,ru}.arb`).
_SUPPORTED_LOCALES = {"uz-Latn", "ru"}


def _user_out(u: User) -> UserOut:
    return UserOut(
        id=str(u.id), role=u.role, phone=u.phone, username=u.username,
        display_name=u.display_name,
        region_code=u.region_code, grade=u.grade, locale=u.locale,
        avatar_color=u.avatar_color, tg_notifications=u.tg_notifications,
    )


def _require_phone_login() -> None:
    """SMS_PROVIDER=disabled bo'lganda telefon+OTP yo'li yopiq.

    Bu Eskiz moderatsiyasi tugamaganda ishlatiladi: klient 503 ni ko'rib
    foydalanuvchiga darhol taklif kodi / Telegram tugmasini ko'rsatadi, kod
    kutib ovora qilmaydi."""
    if _settings.sms_provider == "disabled":
        raise AppError(503, "Phone login unavailable",
                       "hozircha telefon orqali kirish yopiq — taklif kodi "
                       "yoki Telegram orqali kiring",
                       type_="urn:bilim:auth:phone_disabled")


@router.get("/methods")
async def auth_methods():
    """Qaysi kirish yo'llari ochiq — klient shuni oldindan so'raydi.

    Nega kerak: prodda `SMS_PROVIDER=disabled`, ya'ni telefon+OTP 503 qaytaradi.
    Klient buni bilmagani uchun kirish ekrani ENG BIRINCHI o'rinda telefon
    maydonini ko'rsatardi; foydalanuvchi raqamini kiritib, "Kod yuborish" ni
    bosib, xato olardi. Ro'yxatdan o'tishdagi eng katta yo'qotish shu yerda edi.
    Endi ekran ishlaydigan yo'lni birinchi qilib chizadi.

    Autentifikatsiya talab qilinmaydi (kirishdan OLDIN chaqiriladi) va hech
    qanday sir oshkor bo'lmaydi — faqat yoqilgan/o'chirilgan bayroqlar.
    """
    return {
        # 022: parol yo'li hech qanday tashqi xizmatga bog'liq emas (SMS ham,
        # Telegram ham kerak emas), shuning uchun u doim ochiq. Klient uni
        # birinchi o'ringa qo'yadi.
        "password": True,
        "phone": _settings.sms_provider != "disabled",
        "telegram": _settings.telegram_login_enabled,
        "invite": _settings.invite_login_enabled,
        # Kirish (login) emas — parol bilan YANGI hisob ochish taklif kodi
        # so'raydimi. Klient shu bayroqqa qarab ro'yxatdan o'tish formasida
        # kod maydonini ko'rsatadi/yashiradi.
        "password_register_requires_invite":
            _settings.require_invite_for_password_register,
        "telegram_bot_username": _settings.telegram_bot_username or None,
    }


@router.post("/otp/request", response_model=OtpRequestOut)
async def request_otp(body: OtpRequestIn, request: Request):
    _require_phone_login()
    # PER-IP CAP. The per-phone cooldown + daily cap below bound one number;
    # they do nothing against a script that rotates numbers, and every accepted
    # request costs real money at the SMS gateway. nginx has its own 6r/m zone,
    # but that is per connection source and this is the cap the config file has
    # always advertised (OTP_IP_HOURLY_CAP / OTP_IP_DAILY_CAP) — for a long time
    # it advertised a limit no code enforced.
    ip = client_ip(request)
    ok_hour, _ = await ratelimit_hit("otp_ip_h", ip,
                                     _settings.otp_ip_hourly_cap, 3600,
                                     fail_closed=True)
    ok_day, _ = await ratelimit_hit("otp_ip_d", ip,
                                    _settings.otp_ip_daily_cap, 24 * 3600,
                                    fail_closed=True)
    if not (ok_hour and ok_day):
        _log.warning("otp ip cap hit ip=%s", ip)
        raise AppError(429, "Too many requests",
                       "bu tarmoqdan juda ko'p kod so'raldi — keyinroq urining",
                       type_="urn:bilim:otp:ip_cap")

    redis = get_redis()
    try:
        code, ttl = await otp_service.issue(redis, body.phone, role=body.role)
    except otp_service.OtpError as e:
        raise AppError(429, "Too many requests", e.message,
                       type_=f"urn:bilim:otp:{e.code}")

    # Deliver the code. Dev uses the console provider (logs only) and also returns
    # the code in the response; prod uses a real gateway and returns nothing.
    try:
        await sms.get_sms_provider().send(body.phone, sms.render_otp_message(code))
    except sms.SmsError:
        _log.exception("SMS delivery failed for %s", body.phone)
        if not _settings.otp_debug_return:
            # Prod: the user will never get the code — surface it, don't pretend.
            raise AppError(502, "SMS delivery failed",
                           "could not send the verification code, try again")
    if _settings.otp_debug_return:
        _log.info("OTP for %s = %s", body.phone, code)
    return OtpRequestOut(
        retry_after_seconds=_settings.otp_request_cooldown_seconds,
        expires_in_seconds=ttl,
        debug_code=code if _settings.otp_debug_return else None,
    )


@router.post("/otp/verify", response_model=TokenPair)
async def verify_otp(body: OtpVerifyIn, db: AsyncSession = Depends(get_db)):
    _require_phone_login()
    redis = get_redis()
    ok = await otp_service.verify(redis, body.phone, body.code)
    if not ok:
        raise AppError(401, "Invalid or expired code")

    # Role comes from the request-time intent stashed in Redis, not from the client
    # on this call. A new parent gets role=parent; everyone else, student.
    role = await otp_service.pop_role(redis, body.phone)
    user = await auth_service.get_or_create_user(
        db, body.phone, role=role,
        display_name=body.display_name, region_code=body.region_code,
        grade=body.grade,
    )
    pair = await auth_service.issue_token_pair(db, user)
    await db.commit()
    return pair


@router.post("/refresh", response_model=TokenPair)
async def refresh(body: RefreshIn, db: AsyncSession = Depends(get_db)):
    try:
        pair = await auth_service.rotate_refresh_token(db, body.refresh_token)
    except auth_service.AuthError as e:
        await db.rollback()
        raise AppError(401, "Invalid refresh token", str(e))
    await db.commit()
    return pair


@router.post("/logout")
async def logout(body: RefreshIn, db: AsyncSession = Depends(get_db)):
    await auth_service.revoke_refresh_token(db, body.refresh_token)
    await db.commit()
    return {"status": "ok"}


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(get_current_user)):
    return _user_out(user)


@router.patch("/me", response_model=UserOut)
async def update_me(
    body: ProfileUpdateIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if body.display_name is not None:
        # Uzunlik YETARLI EMAS. `display_name` reytingda, bellashuvda va
        # ota-ona ekranida BOSHQA odamlarga ko'rinadi — sinovda `火` ismli
        # hisob shu tekshiruvdan o'tib ketgan edi. `core/names.py` emoji,
        # CJK, RTL va ko'rinmas belgilarni rad etadi.
        try:
            user.display_name = names.validate_name(body.display_name)
        except names.NameError_ as e:
            raise AppError(400, "Invalid name", str(e),
                           type_="urn:bilim:auth:bad_name") from e
    if body.region_code is not None:
        if body.region_code not in REGION_CODES:
            raise AppError(400, "Invalid region", "unknown region_code")
        user.region_code = body.region_code
    if body.grade is not None:
        if not (1 <= body.grade <= 11):
            raise AppError(400, "Invalid grade", "grade must be 1–11")
        user.grade = body.grade
    if body.locale is not None:
        # `users.locale` — `languages(code)` ga FK. Tekshiruvsiz noma'lum
        # qiymat FK buzilishi bilan 500 berardi va tranzaksiyani "aborted"
        # holatiga tashlardi. Bu yerdagi ro'yxat `sql/001_init.sql` dagi
        # `languages` seed'i bilan mos.
        if body.locale not in _SUPPORTED_LOCALES:
            raise AppError(400, "Invalid locale",
                           f"locale must be one of: "
                           f"{', '.join(sorted(_SUPPORTED_LOCALES))}")
        user.locale = body.locale
    if body.avatar_color is not None:
        # Palitra indeksi — chegara bazadagi CHECK bilan bir xil (021).
        # Bu yerda ham tekshiramiz: 400 xatosi 500 dan ancha foydaliroq.
        if not (0 <= body.avatar_color <= 11):
            raise AppError(400, "Invalid avatar", "avatar_color must be 0–11")
        user.avatar_color = body.avatar_color
    if body.tg_notifications is not None:
        # Telegram xabarlarini butunlay o'chirish. Bu tugma BO'LISHI SHART:
        # xabar yuborish huquqi faqat uni to'xtatish oson bo'lgandagina
        # halol bo'ladi, va to'xtata olmaydigan odam botni bloklaydi —
        # o'shanda kirish yo'li ham yo'qoladi.
        user.tg_notifications = body.tg_notifications
    await db.commit()
    return _user_out(user)
