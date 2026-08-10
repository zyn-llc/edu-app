"""
Parol bilan kirish — validatsiya qoidalari.

Bu yerda DB yo'q: tekshirilayotgan narsa endpoint qatlamidagi sof qarorlar —
nom shakli, band nomlar ro'yxati va parol uzunligi. Baza bilan bog'liq
qismlar (noyoblik, token berish) integratsiya sinovida, `docker compose` bor
muhitda tekshiriladi.

Nega aynan shular sinaladi: bu uchtasi noto'g'ri ishlasa, oqibat jim bo'ladi.
Masalan kirill harfli nom o'tib ketsa, foydalanuvchi hisob yaratadi, keyin
lotin klaviaturada o'sha nomni tera olmaydi va "parolim ishlamayapti" deb
qoladi — sabab hech qayerda ko'rinmaydi.
"""
import pytest

from app.api.v1 import password_auth as pw
from app.core.errors import AppError

# --------------------------------------------------------------------------- #
#  Nom shakli                                                                 #
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize("name", ["zizu", "zizu_11", "A1_", "abc", "a" * 20])
def test_valid_usernames_accepted(name):
    assert pw._validate_username(name) == name

@pytest.mark.parametrize("name", [
    "ab",            # juda qisqa
    "a" * 21,        # juda uzun
    "zizu 11",
    "zizu-11",       # chiziqcha
    "зизу",
    "ali@mail",      # @
    "",
])
def test_invalid_usernames_rejected(name):
    with pytest.raises(AppError):
        pw._validate_username(name)

def test_username_is_trimmed_but_case_preserved():
    """Foydalanuvchi yozgan shakl saqlanadi (profilda ko'rinadi), lekin
    solishtirish `lower()` bilan boradi — buni `_find_by_username` bajaradi."""
    assert pw._validate_username("  Zizu  ") == "Zizu"

@pytest.mark.parametrize("name", ["admin", "ADMIN", "Support", "topagon", "rasmiy"])
def test_reserved_usernames_rejected(name):
    with pytest.raises(AppError):
        pw._validate_username(name)

# --------------------------------------------------------------------------- #
#  Parol                                                                      #
# --------------------------------------------------------------------------- #
def test_short_password_rejected():
    with pytest.raises(AppError):
        pw._validate_password("12345")

def test_six_chars_is_enough():
    assert pw._validate_password("123456") == "123456"

def test_absurdly_long_password_rejected():
    """Chegara bo'lmasa megabaytlik satr argon2'ni band qilib, arzon DoS
    yo'lini ochib qo'yardi."""
    with pytest.raises(AppError):
        pw._validate_password("x" * 200)

def test_password_regex_matches_db_constraint():
    """`022_username_password.sql` dagi CHECK bilan bir xil bo'lishi shart.
    Ikkalasi ajralib ketsa, server qabul qilgan nom bazada rad etiladi va
    foydalanuvchi 500 ko'radi."""
    assert pw.USERNAME_RE.pattern == r"^[A-Za-z0-9_]{3,20}$"
