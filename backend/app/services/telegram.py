"""
Telegram orqali kirish — bot mantiqining o'zi.

Oqim:
  1. Ilova  POST /v1/auth/telegram/start  -> nonce + deep link + TASDIQ KODI
     Redis:  tg:login:<nonce> = "pending:<KOD>"  (TTL 10 daqiqa)
     Ilova KODNI EKRANDA ko'rsatadi.
  2. Foydalanuvchi havolani bosadi -> bot ochiladi -> "Start"
     Telegram bizga  /start <nonce>  yuboradi.
  3. Bot HISOBNI HALI BOG'LAMAYDI. U aynan o'sha kodni ko'rsatib so'raydi:
     «Kirishni tasdiqlaysizmi? Kod: A7K2» [Ha] [Bekor qilish]
  4. Foydalanuvchi [Ha] bosadi -> callback_query keladi -> shundagina
     telegram_id bo'yicha foydalanuvchi yaratiladi/topiladi va Redis'ga
     user_id yoziladi.
  5. Ilova  POST /v1/auth/telegram/poll  -> token juftligi.

NEGA 3-QADAM BOR (2026-08-09 auditi). Usiz bu oqim bir bosishda hisob
o'g'irlash edi: hujumchi o'zi `start` chaqirib, `t.me/bot?start=<nonce>`
havolasini qurbonga yuborardi ("bosing, sovg'a bor"). Qurbon «Start» bosgan
zahoti Redis'ga UNING user_id si yozilardi, hujumchining `poll` chaqiruvi esa
qurbon hisobiga to'liq token juftligini olardi. Endi qurbon botda o'zi
so'ramagan kirish so'rovini ko'radi va uni tasdiqlamaydi — kod esa faqat
HAQIQIY kirayotgan odamning ekranida turadi.

Nega SMS emas: shablon moderatsiyasi yo'q, xarajat yo'q, O'zbekistonda
o'quvchilarda Telegram deyarli 100%. Eskiz kelganda ikkalasi yonma-yon turadi.

Nonce `secrets.token_urlsafe(24)` — taxmin qilib bo'lmaydi va bir martalik.
"""
from __future__ import annotations

import logging
import secrets

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import names
from app.core.config import get_settings
from app.core.redis import get_redis
from app.models import User, UserProgress

_log = logging.getLogger("bilim.telegram")
_settings = get_settings()

PENDING = "pending"
_PENDING_PREFIX = PENDING + ":"

_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

_START_HINT = (
    "Salom! Men Topag'on botiman.\n\n"
    "Ilovaga kirish uchun topagon.uz ni oching va «Telegram orqali kirish» "
    "tugmasini bosing.\n\n"
    "Savol yoki taklif bo'lsa — shu yerga yozing, men jamoaga yetkazaman."
)

_SUPPORT_HINT = (
    "Xabaringiz qabul qilindi va jamoaga yuborildi. Rahmat!\n\n"
    "Ilovaga kirish uchun topagon.uz → «Telegram orqali kirish»."
)

async def notify_admin(text: str) -> None:
    """Murojaatni administrator chatiga yuboradi.

    BEST-EFFORT: yuborilmasa hech narsa buzilmaydi — xabar bazada allaqachon
    saqlangan. Shuning uchun chaqiruvchi tomon xatoni ushlamasligi ham mumkin,
    lekin biz baribir ushlaymiz: murojaat yuborish oqimini Telegram uzilishi
    to'xtatib qo'ymasligi kerak.
    """
    chat_id = _settings.telegram_admin_chat_id
    if not chat_id or not _settings.telegram_bot_token:
        return
    try:
        await send_message(chat_id, text)
    except Exception:
        _log.exception("admin notify failed")

def nonce_key(nonce: str) -> str:
    return f"tg:login:{nonce}"

def new_nonce() -> str:
    return secrets.token_urlsafe(24)

def new_confirm_code() -> str:
    """Ilova ekranida ham, bot xabarida ham ko'rinadigan 4 belgili kod."""
    return "".join(secrets.choice(_CODE_ALPHABET) for _ in range(4))

def pending_value(code: str) -> str:
    return _PENDING_PREFIX + code

def pending_code(value: str | None) -> str | None:
    """Redis qiymatidan tasdiq kodini ajratadi; kutish holatida bo'lmasa None."""
    if value and value.startswith(_PENDING_PREFIX):
        return value[len(_PENDING_PREFIX):]
    return None

def deep_link(nonce: str) -> str:
    username = _settings.telegram_bot_username.strip().lstrip("@")
    return f"https://t.me/{username}?start={nonce}"

# --------------------------------------------------------------------------- #
#  Bot API                                                                     #
# --------------------------------------------------------------------------- #
async def _call(method: str, payload: dict) -> None:
    """Bot API chaqiruvi. Xato oqimni to'xtatmaydi — faqat log.

    Token URL YO'LIDA turadi, shuning uchun bu yerda hech qachon `url` ni
    logga yozma (`app/main.py` httpx logini shu sabab WARNING ga tushirgan).
    """
    if not _settings.telegram_bot_token:
        return
    url = (f"{_settings.telegram_api_base}"
           f"/bot{_settings.telegram_bot_token}/{method}")
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            await client.post(url, json=payload)
    except Exception:
        _log.exception("telegram %s failed", method)

async def send_message(chat_id: int, text: str,
                       reply_markup: dict | None = None) -> None:
    """Botdan xabar. Yuborilmasa oqim buzilmaydi — foydalanuvchi baribir
    ilovaga qaytganda ichkarida bo'ladi, shuning uchun faqat log."""
    payload: dict = {"chat_id": chat_id, "text": text}
    if reply_markup is not None:
        payload["reply_markup"] = reply_markup
    await _call("sendMessage", payload)

async def answer_callback(callback_id: str, text: str = "") -> None:
    """Tugma bosilganda Telegram'dagi kutish aylanasini to'xtatadi. Chaqirilmasa
    foydalanuvchi bir necha soniya "yuklanyapti" ni ko'radi va tugmani qayta
    bosadi."""
    await _call("answerCallbackQuery",
                {"callback_query_id": callback_id, "text": text})

async def set_webhook(url: str) -> dict:
    """Bir marta ishlatiladi (deploy'dan keyin). scripts/telegram_setup.py chaqiradi."""
    api = (f"{_settings.telegram_api_base}"
           f"/bot{_settings.telegram_bot_token}/setWebhook")
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.post(api, json={
            "url": url,
            "secret_token": _settings.telegram_webhook_secret,
            "allowed_updates": ["message", "callback_query"],
        })
        return r.json()

async def get_or_create_by_telegram(
    db: AsyncSession,
    telegram_id: int,
    *,
    display_name: str | None = None,
) -> User:
    user = (await db.execute(
        select(User).where(User.telegram_id == telegram_id)
    )).scalar_one_or_none()
    if user is not None:
        if display_name and not user.display_name:
            user.display_name = display_name
        return user

    user = User(
        telegram_id=telegram_id,
        phone=None,
        role="student",
        display_name=display_name,
        locale=_settings.default_lang,
    )
    db.add(user)
    await db.flush()
    db.add(UserProgress(user_id=user.id))
    await db.flush()
    return user

# --------------------------------------------------------------------------- #
#  Update ishlovchisi — webhook ham, dev long-polling ham shuni chaqiradi      #
# --------------------------------------------------------------------------- #
def _display_name(sender: dict) -> str | None:
    """Telegram ismi tashqi manba — emoji ham, CJK ham bo'lishi mumkin.
    `safe_name` xato ko'tarmaydi: ism yaroqsiz bo'lsa shunchaki olinmaydi va
    foydalanuvchi uni profilda o'zi kiritadi. Kirishni bloklash nomutanosib
    javob bo'lardi."""
    raw = " ".join(x for x in [sender.get("first_name"),
                               sender.get("last_name")] if x)
    return names.safe_name(raw) or None

async def _handle_callback(db: AsyncSession, cq: dict) -> None:
    """Kirish tasdiqlash tugmasi. FAQAT shu yerda hisob bog'lanadi."""
    data = (cq.get("data") or "").strip()
    sender = cq.get("from") or {}
    chat_id = ((cq.get("message") or {}).get("chat") or {}).get("id")
    telegram_id = sender.get("id")
    cq_id = cq.get("id")

    if not cq_id or not telegram_id or ":" not in data:
        return
    action, _, nonce = data.partition(":")

    if action == "tgno":
        await answer_callback(cq_id, "Bekor qilindi")
        if chat_id:
            await send_message(chat_id, "Kirish bekor qilindi.")
        return
    if action != "tgok":
        return

    redis = get_redis()
    key = nonce_key(nonce)
    value = await redis.get(key)
    if pending_code(value) is None:
        await answer_callback(cq_id, "Havolaning muddati tugagan")
        if chat_id:
            await send_message(
                chat_id, "Havolaning muddati tugagan. Ilovada qaytadan "
                         "«Telegram orqali kirish» ni bosing.")
        return

    user = await get_or_create_by_telegram(
        db, int(telegram_id), display_name=_display_name(sender))
    await db.commit()

    ttl = await redis.ttl(key)
    await redis.set(key, str(user.id), ex=max(ttl, 60))

    await answer_callback(cq_id, "Tasdiqlandi")
    if chat_id:
        await send_message(chat_id, "Tayyor ✅ Ilovaga qayting.")

async def handle_update(db: AsyncSession, update: dict) -> None:
    if "callback_query" in update:
        await _handle_callback(db, update["callback_query"])
        return

    message = update.get("message") or {}
    text = (message.get("text") or "").strip()
    chat = message.get("chat") or {}
    sender = message.get("from") or {}
    chat_id = chat.get("id")
    telegram_id = sender.get("id")

    if not chat_id or not telegram_id:
        return

    if not text.startswith("/start"):
        who = " ".join(x for x in [sender.get("first_name"),
                                   sender.get("last_name")] if x) or "?"
        username = sender.get("username")
        await notify_admin(
            "Telegram orqali murojaat\n"
            f"Kimdan: {who}"
            + (f" (@{username})" if username else "")
            + f"\nTelegram ID: {telegram_id}\n\n{text[:1500]}"
        )
        await send_message(chat_id, _SUPPORT_HINT)
        return

    parts = text.split(maxsplit=1)
    if len(parts) < 2:
        await send_message(chat_id,
                           _START_HINT)
        return

    nonce = parts[1].strip()
    redis = get_redis()
    key = nonce_key(nonce)

    current = await redis.get(key)
    if current is None:
        await send_message(chat_id,
                           "Havolaning muddati tugagan. Ilovada qaytadan "
                           "«Telegram orqali kirish» ni bosing.")
        return

    code = pending_code(current)
    if code is None:
        await send_message(chat_id, "Bu havola allaqachon ishlatilgan.")
        return

    await send_message(
        chat_id,
        "Topag'onga kirishni tasdiqlaysizmi?\n\n"
        f"Ilovangizdagi kod: {code}\n\n"
        "Agar siz hozir kirishga urinmagan bo'lsangiz yoki bu kod "
        "ekraningizdagidan farq qilsa — «Bekor qilish» ni bosing.",
        reply_markup={"inline_keyboard": [[
            {"text": f"✅ Tasdiqlash ({code})", "callback_data": f"tgok:{nonce}"},
            {"text": "✖️ Bekor qilish", "callback_data": f"tgno:{nonce}"},
        ]]},
    )
