"""Bellashuv havolasi taklif kodi o'rnida — yopiq beta buzilmasin.

MUAMMO (2026-08-09, jonli ma'lumot bilan aniqlangan). `?join=KOD`
havolasini bosgan odam ro'yxatdan o'ta olmasdi: undan taklif kodi
so'ralardi, u esa faqat chaqirgan odamda bor. Bazada natija ko'rindi —
yagona taklif kodi 40 joydan 0 tasi ishlatilgan, parol bilan kelgan yangi
hisob umuman yo'q.

Endi bellashuv kodining o'zi bir martalik taklif sifatida qabul qilinadi.
Bu YOPIQ BETA TO'SIG'INI BO'SHATADIGAN o'zgarish, shuning uchun bu yerda
qulflanadigan uchta xossa bor:

  1. Yaroqli, ochiq bellashuv kodi kodsiz ro'yxatdan o'tishga YO'L BERADI.
  2. Bitta kod FAQAT BIR MARTA yaraydi — aks holda bitta ochiq bellashuv
     bilan cheksiz hisob ochib bo'lardi.
  3. Yopiq/eskirgan/yo'q kod YO'L BERMAYDI, va kodsiz kelgan odam
     baribir rad etiladi.

SQL bu yerda haqiqiy bazada emas, soxta bajaruvchida tekshiriladi:
repoda DB'li test tayanchi yo'q (`test_challenges.py` bilan bir xil
yondashuv). Tekshirilayotgan narsa — SQL matni emas, QAROR mantig'i:
qaysi shartda ro'yxatdan o'tish o'tadi va qaysi shartda yiqiladi.
"""
import asyncio
import re

import pytest

from app.api.v1 import password_auth

class FakeResult:
    def __init__(self, row):
        self._row = row

    def mappings(self):
        return self

    def first(self):
        return self._row

class FakeDB:
    """`challenges` va `invite_codes` ustidagi atomik UPDATE larni taqlid qiladi.

    Muhimi: `UPDATE ... WHERE invite_used_at IS NULL` shartini HAQIQATAN
    bajaradi — ya'ni ikkinchi urinish bo'sh qaytadi, xuddi Postgres'dagi
    kabi. Aynan shu xossa "bitta kod = bitta hisob" kafolatini beradi.
    """

    def __init__(self, *, challenge=None, invite=None):
        self.challenge = challenge or {}
        self.invite = invite or {}
        self.rolled_back = False

    async def execute(self, stmt, params=None):
        sql = str(stmt)
        params = params or {}
        if "UPDATE challenges" in sql:
            row = self.challenge.get(params.get("code"))
            if row is None or not row["open"] or row["used"]:
                return FakeResult(None)
            row["used"] = True          # `SET invite_used_at = now()`
            return FakeResult({"id": row["id"], "grade": row.get("grade")})
        if "UPDATE invite_codes" in sql:
            row = self.invite.get(params.get("code"))
            if row is None or row["left"] <= 0:
                return FakeResult(None)
            row["left"] -= 1
            return FakeResult({"code": params["code"], "grade": None,
                               "region_code": None})
        raise AssertionError(f"kutilmagan SQL: {sql[:60]}")

    async def rollback(self):
        self.rolled_back = True

async def _gate(db, *, invite_code=None, join_code=None):
    """`register()` dagi taklif tekshiruvi. Muvaffaqiyatda (invite, challenge)."""
    from app.core.errors import AppError
    from app.api.v1.invites import normalize_code

    code = normalize_code(invite_code or "")
    join = (join_code or "").strip().upper()
    invite_row = challenge_row = None

    if not code and join:
        challenge_row = (await db.execute(
            "UPDATE challenges SET invite_used_at = now() WHERE code = :code",
            {"code": join})).mappings().first()
        if challenge_row is None:
            await db.rollback()
            raise AppError(401, "Invalid challenge link", "eskirgan",
                           type_="urn:bilim:auth:invite_required")

    if not code and challenge_row is None:
        raise AppError(400, "Invite code required", "kod kerak",
                       type_="urn:bilim:auth:invite_required")

    if code:
        invite_row = (await db.execute(
            "UPDATE invite_codes SET used_count = used_count + 1 "
            "WHERE code = :code", {"code": code})).mappings().first()
        if invite_row is None:
            await db.rollback()
            raise AppError(401, "Invalid code", "yaroqsiz",
                           type_="urn:bilim:auth:invite_required")

    return invite_row, challenge_row

def _db(open_code="Y39CNY", used=False, grade=9):
    return FakeDB(challenge={open_code: {"id": "ch-1", "grade": grade,
                                         "open": True, "used": used}},
                  invite={"VT37KCN5": {"left": 40}})

def test_bellashuv_kodi_royxatdan_otkazadi():
    db = _db()
    invite, challenge = asyncio.run(_gate(db, join_code="Y39CNY"))
    assert invite is None
    assert challenge is not None and challenge["id"] == "ch-1"

def test_kod_kichik_harfda_ham_ishlaydi():
    """Havoladan kelgan kod qanday yozilgan bo'lsa ham qabul qilinsin."""
    db = _db()
    _, challenge = asyncio.run(_gate(db, join_code=" y39cny "))
    assert challenge is not None

def test_bitta_kod_faqat_bir_marta():
    """Eng muhim xossa: ochiq bellashuv cheksiz hisob ochish yo'li emas."""
    db = _db()
    asyncio.run(_gate(db, join_code="Y39CNY"))
    with pytest.raises(Exception) as e:
        asyncio.run(_gate(db, join_code="Y39CNY"))
    assert getattr(e.value, "status_code", 401) in (401, 400)
    assert db.rolled_back

def test_notogri_kod_rad_etiladi():
    db = _db()
    with pytest.raises(Exception):
        asyncio.run(_gate(db, join_code="YOQKOD"))

def test_yopilgan_bellashuv_rad_etiladi():
    db = FakeDB(challenge={"Y39CNY": {"id": "ch-1", "open": False,
                                      "used": False}})
    with pytest.raises(Exception):
        asyncio.run(_gate(db, join_code="Y39CNY"))

def test_kodsiz_kelgan_baribir_rad_etiladi():
    """Yopiq beta ochilib ketmasin: hech qanday kod bo'lmasa — yo'q."""
    db = _db()
    with pytest.raises(Exception):
        asyncio.run(_gate(db))

def test_taklif_kodi_yoli_buzilmagan():
    db = _db()
    invite, challenge = asyncio.run(_gate(db, invite_code="VT37KCN5"))
    assert challenge is None
    assert invite is not None and invite["code"] == "VT37KCN5"
    # Bellashuv kodi behuda sarflanmagan.
    assert db.challenge["Y39CNY"]["used"] is False

def test_taklif_kodi_bellashuvdan_ustun():
    """Ikkalasi kelsa taklif kodi ishlatiladi, bellashuv teginilmaydi."""
    db = _db()
    invite, challenge = asyncio.run(_gate(db, invite_code="VT37KCN5",
                                          join_code="Y39CNY"))
    assert invite is not None and challenge is None
    assert db.challenge["Y39CNY"]["used"] is False

def test_endpoint_kodi_shu_mantiqni_saqlaydi():
    """Yuqoridagi `_gate` endpoint bilan ajralib ketmaganini tekshiradi.

    Soxta bazali test faqat mantiqni qamraydi; agar kimdir endpointdagi
    `if code:` qorovulini olib tashlasa, bellashuv yo'li jimgina buzilardi
    (bo'sh `code` bilan `UPDATE invite_codes` hech nima topmaydi).
    """
    src = password_auth.register.__doc__ or ""
    del src
    import inspect
    body = inspect.getsource(password_auth.register)
    assert "UPDATE challenges" in body
    assert "invite_used_at IS NULL" in body
    # `if code:` qorovuli — bellashuv yo'lining tirikligi shunga bog'liq.
    assert re.search(r"\n\s+if code:\s*\n", body)
