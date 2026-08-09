"""
Telegram kirish — hisob FAQAT tasdiqlangandan keyin bog'lanadi.

HUJUM (2026-08-09 auditida topilgan). Ilgari `/start <nonce>` ni kim bossa,
Redis'ga O'SHANING user_id si yozilardi. Hujumchi o'zi `start` chaqirib,
`t.me/bot?start=<nonce>` havolasini qurbonga yuborardi; qurbon «Start»
bosgan zahoti hujumchining `poll` chaqiruvi qurbon hisobiga to'liq token
juftligini olardi. Bir bosishda hisob o'g'irlash.

Shu fayldagi birinchi test aynan o'sha xatti-harakatni qaytadan paydo
bo'lishidan qo'riqlaydi: `/start` dan KEYIN kalit hamon kutish holatida
turishi shart.
"""
import asyncio
import uuid
from types import SimpleNamespace

import pytest

# `app.services.telegram` modul darajasida `httpx` ni import qiladi (Bot API
# chaqiruvlari uchun). U `requirements.txt` da bor, ya'ni Docker'da va CI'da
# mavjud; ba'zi lokal venv'larda esa yo'q — `test_sms.py` ham shu sababli
# yig'ilmaydi. Testni o'chirib qo'ygandan ko'ra o'tkazib yuborgan yaxshi.
#   Lokalda ishga tushirish uchun:  pip install httpx
pytest.importorskip("httpx", reason="httpx o'rnatilmagan (pip install httpx)")

from app.services import telegram as tg      # noqa: E402


class FakeRedis:
    def __init__(self, data=None):
        self.data = dict(data or {})

    async def get(self, k):
        return self.data.get(k)

    async def set(self, k, v, ex=None):
        self.data[k] = v

    async def delete(self, k):
        self.data.pop(k, None)

    async def ttl(self, k):
        return 300


class FakeDB:
    async def commit(self):
        pass


@pytest.fixture
def bot(monkeypatch):
    """Bot chiqishini yozib boradi va hisob yaratishni soxtalashtiradi."""
    sent: list[tuple[int, str, dict | None]] = []
    answered: list[tuple[str, str]] = []
    created: list[int] = []
    user_id = uuid.uuid4()

    async def _send(chat_id, text, reply_markup=None):
        sent.append((chat_id, text, reply_markup))

    async def _answer(cq_id, text=""):
        answered.append((cq_id, text))

    async def _get_or_create(db, telegram_id, *, display_name=None):
        created.append(telegram_id)
        return SimpleNamespace(id=user_id, display_name=display_name)

    monkeypatch.setattr(tg, "send_message", _send)
    monkeypatch.setattr(tg, "answer_callback", _answer)
    monkeypatch.setattr(tg, "get_or_create_by_telegram", _get_or_create)
    return SimpleNamespace(sent=sent, answered=answered, created=created,
                           user_id=user_id)


def _start_update(nonce, telegram_id=555):
    return {"message": {
        "text": f"/start {nonce}",
        "chat": {"id": 900},
        "from": {"id": telegram_id, "first_name": "Zizu"},
    }}


def _callback(action, nonce, telegram_id=555):
    return {"callback_query": {
        "id": "cq1",
        "data": f"{action}:{nonce}",
        "from": {"id": telegram_id, "first_name": "Zizu"},
        "message": {"chat": {"id": 900}},
    }}


def _run(redis, update, monkeypatch):
    monkeypatch.setattr(tg, "get_redis", lambda: redis)
    asyncio.run(tg.handle_update(FakeDB(), update))


# --------------------------------------------------------------------------- #
def test_start_does_not_bind_the_account(bot, monkeypatch):
    nonce, code = "n1", "A7K2"
    redis = FakeRedis({tg.nonce_key(nonce): tg.pending_value(code)})

    _run(redis, _start_update(nonce), monkeypatch)

    # Hisob YARATILMAGAN va kalit hamon kutishda — bu testning butun mazmuni.
    assert bot.created == []
    assert redis.data[tg.nonce_key(nonce)] == tg.pending_value(code)

    # Foydalanuvchiga kod ko'rsatilgan va ikkita tugma berilgan.
    chat_id, text, markup = bot.sent[-1]
    assert chat_id == 900 and code in text
    buttons = markup["inline_keyboard"][0]
    assert [b["callback_data"] for b in buttons] == [f"tgok:{nonce}",
                                                     f"tgno:{nonce}"]


def test_confirm_binds_the_account(bot, monkeypatch):
    nonce = "n2"
    redis = FakeRedis({tg.nonce_key(nonce): tg.pending_value("BB33")})

    _run(redis, _callback("tgok", nonce), monkeypatch)

    assert bot.created == [555]
    assert redis.data[tg.nonce_key(nonce)] == str(bot.user_id)
    assert tg.pending_code(redis.data[tg.nonce_key(nonce)]) is None


def test_cancel_leaves_the_nonce_pending(bot, monkeypatch):
    nonce = "n3"
    redis = FakeRedis({tg.nonce_key(nonce): tg.pending_value("CC44")})

    _run(redis, _callback("tgno", nonce), monkeypatch)

    assert bot.created == []
    assert tg.pending_code(redis.data[tg.nonce_key(nonce)]) == "CC44"


def test_confirm_on_expired_nonce_creates_nothing(bot, monkeypatch):
    redis = FakeRedis()                       # kalit umuman yo'q
    _run(redis, _callback("tgok", "gone"), monkeypatch)

    assert bot.created == []
    assert redis.data == {}


def test_confirm_twice_does_not_rebind(bot, monkeypatch):
    """Ikkinchi bosish allaqachon tasdiqlangan nonce'ni qayta yozmasin."""
    nonce = "n4"
    already = str(uuid.uuid4())
    redis = FakeRedis({tg.nonce_key(nonce): already})

    _run(redis, _callback("tgok", nonce, telegram_id=999), monkeypatch)

    assert bot.created == []
    assert redis.data[tg.nonce_key(nonce)] == already


def test_start_without_nonce_is_a_plain_hint(bot, monkeypatch):
    redis = FakeRedis()
    _run(redis, {"message": {"text": "/start", "chat": {"id": 900},
                             "from": {"id": 555}}}, monkeypatch)
    assert bot.created == []
    assert "topagon.uz" in bot.sent[-1][1]


def test_pending_code_roundtrip():
    assert tg.pending_code(tg.pending_value("XY12")) == "XY12"
    assert tg.pending_code(str(uuid.uuid4())) is None
    assert tg.pending_code(None) is None
    assert len(tg.new_confirm_code()) == 4
