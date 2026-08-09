"""
Telegram kirish endpointlari.

  POST /v1/auth/telegram/start   {}          -> {nonce, deep_link, expires_in_seconds}
  POST /v1/auth/telegram/poll    {nonce}     -> {status: pending} yoki TokenPair
  POST /v1/telegram/webhook                  -> Telegram chaqiradi (odam emas)

Kirish IKKI QADAMLI: `start` tasdiq kodini ham beradi, bot esa aynan o'sha
kodni ko'rsatib tugma so'raydi. Sabab va hujum stsenariysi —
`app/services/telegram.py` bosh izohida.

Webhook himoyasi: Telegram har so'rovga `X-Telegram-Bot-Api-Secret-Token`
header'ini qo'yadi (setWebhook'da berilgan qiymat). Mos kelmasa 404 — URL'ni
topgan odam soxta login yasay olmaydi.

Webhook HAR DOIM 200 qaytaradi (ichkarida xato bo'lsa ham). Telegram 200 dan
boshqa javobga o'sha update'ni qayta-qayta yuboraveradi va navbat tiqilib qoladi.
"""
from __future__ import annotations

import hmac
import logging
import uuid as uuidlib

from fastapi import APIRouter, Depends, Header, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.ratelimit import client_ip, hit as ratelimit_hit
from app.core.redis import get_redis
from app.models import User
from app.schemas.auth import TokenPair
from app.services import auth as auth_service
from app.services import telegram as tg

router = APIRouter(tags=["auth"])
_settings = get_settings()
_log = logging.getLogger("bilim.telegram")


def _require_enabled() -> None:
    if not _settings.telegram_login_enabled:
        raise AppError(404, "Not Found")


class StartOut(BaseModel):
    nonce: str
    deep_link: str
    expires_in_seconds: int
    #: Ilova buni EKRANDA ko'rsatishi shart. Bot xuddi shu kodni tasdiqlash
    #: tugmasida chizadi — foydalanuvchi ikkalasini solishtiradi. Usiz oqim
    #: bir bosishda hisob o'g'irlashga aylanadi (services/telegram.py izohi).
    confirm_code: str


class PollIn(BaseModel):
    nonce: str = Field(min_length=8, max_length=128)


@router.post("/v1/auth/telegram/start", response_model=StartOut)
async def telegram_start(request: Request):
    _require_enabled()
    ip = client_ip(request)
    # 20 → 120 (soatiga, bitta IP uchun).
    #
    # NEGA: O'zbekistonda maktab Wi-Fi'si va uyali internet NAT ortida —
    # o'nlab foydalanuvchi serverga BITTA IP bilan ko'rinadi. 30 ta sinovchi
    # bir dars davomida ro'yxatdan o'tsa, 20 chegarasi 21-chi odamdan
    # boshlab 429 beradi va u buni "ilova ishlamayapti" deb tushunadi.
    #
    # 120 hali ham abuse'ga qarshi: nonce yaratish arzon, lekin har bir
    # nonce alohida Redis kaliti va 10 daqiqada o'chadi.
    allowed, _ = await ratelimit_hit("tg_start", ip, 120, 3600,
                                     fail_closed=True)
    if not allowed:
        raise AppError(429, "Too many attempts")

    nonce = tg.new_nonce()
    code = tg.new_confirm_code()
    ttl = _settings.telegram_login_ttl_seconds
    await get_redis().set(tg.nonce_key(nonce), tg.pending_value(code), ex=ttl)
    return StartOut(nonce=nonce, deep_link=tg.deep_link(nonce),
                    expires_in_seconds=ttl, confirm_code=code)


@router.post("/v1/auth/telegram/poll")
async def telegram_poll(
    body: PollIn,
    db: AsyncSession = Depends(get_db),
):
    # `request` endi kerak emas: chegara IP'dan emas, nonce'dan olinadi.
    _require_enabled()
    # Chegara IP bo'yicha EMAS, NONCE bo'yicha.
    #
    # MUAMMO (topilgan 2026-08-06): ilova har 2 soniyada so'raydi, nonce esa
    # 10 daqiqa yashaydi → bitta kirish urinishi 300 tagacha so'rov. Eski
    # chegara IP uchun 500 edi, ya'ni BITTA IP ortida ikkitadan ko'p odam
    # bo'lsa (maktab Wi-Fi'si, uyali NAT) uchinchisi 429 olardi va Telegram
    # orqali kira olmasdi. 30 sinovchili beta uchun bu to'sqinlik.
    #
    # Nonce bo'yicha cheklash to'g'riroq: u `secrets.token_urlsafe(24)` —
    # taxmin qilib bo'lmaydi, ya'ni birov boshqasining nonce'sini "yeb"
    # qo'ya olmaydi. Nonce yaratishning o'zi esa `tg_start` da IP bo'yicha
    # cheklangan — abuse yo'li o'sha yerda yopiq.
    #
    # 400 = 2 soniyalik so'rov bilan ~13 daqiqa; nonce TTL 10 daqiqa,
    # demak normal oqim hech qachon chegaraga yetmaydi.
    allowed, _ = await ratelimit_hit("tg_poll", body.nonce, 400, 3600)
    if not allowed:
        raise AppError(429, "Too many attempts")

    redis = get_redis()
    key = tg.nonce_key(body.nonce)
    value = await redis.get(key)

    if value is None:
        raise AppError(410, "Expired", "havola muddati tugagan, qaytadan boshlang")
    if tg.pending_code(value) is not None:
        # Hali tasdiqlanmagan: foydalanuvchi botga bormagan, yoki borgan-u
        # tasdiqlash tugmasini bosmagan. Klient uchun ikkalasi ham bir xil —
        # u kutishda davom etadi va ekranda tasdiq kodini ko'rsatib turadi.
        return {"status": "pending"}

    try:
        user_id = uuidlib.UUID(value)
    except ValueError:
        await redis.delete(key)
        raise AppError(410, "Expired")

    user = (await db.execute(
        select(User).where(User.id == user_id)
    )).scalar_one_or_none()
    if user is None:
        await redis.delete(key)
        raise AppError(410, "Expired")

    # Bir martalik: token berilgach nonce yo'q qilinadi.
    await redis.delete(key)
    pair = await auth_service.issue_token_pair(db, user)
    await db.commit()
    return {
        "status": "ok",
        "access_token": pair.access_token,
        "refresh_token": pair.refresh_token,
        "expires_in": pair.expires_in,
    }


@router.post("/v1/telegram/webhook", include_in_schema=False)
async def telegram_webhook(
    request: Request,
    x_telegram_bot_api_secret_token: str | None = Header(None),
    db: AsyncSession = Depends(get_db),
):
    if not _settings.telegram_login_enabled:
        raise AppError(404, "Not Found")
    # `compare_digest` — sekret bilan oddiy `!=` javob vaqti orqali uning
    # boshlanishini oshkor qiladi.
    if (not _settings.telegram_webhook_secret
            or not hmac.compare_digest(x_telegram_bot_api_secret_token or "",
                                       _settings.telegram_webhook_secret)):
        raise AppError(404, "Not Found")

    try:
        update = await request.json()
    except Exception:
        return {"ok": True}

    try:
        await tg.handle_update(db, update)
    except Exception:
        # 200 qaytarish shart — aks holda Telegram shu update'ni qayta yuboraveradi.
        await db.rollback()
        _log.exception("telegram update failed")
    return {"ok": True}


# Yuqoridagi TokenPair importi javob sxemasi sifatida ishlatilmaydi (poll ikki
# xil shakl qaytaradi), lekin auth_service qaytaradigan tipni ko'rsatib turadi.
__all__ = ["router", "TokenPair"]
