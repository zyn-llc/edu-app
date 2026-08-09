"""
Ko'rinadigan ism (`display_name`) uchun tozalash va tekshirish.

## Nega alohida modul

`display_name` **boshqa foydalanuvchilarga ko'rinadi**: reytingda, bellashuv
kartochkasida, ota-ona ekranida. Ya'ni bu shunchaki profil maydoni emas —
bu boshqa odamning ekraniga tushadigan matn.

Ilgari yagona tekshiruv uzunlik edi (1–40). Natijada sinovda `火` (CJK)
ismli hisob paydo bo'ldi. Emoji, o'ngdan-chapga yoziladigan matn va
ko'rinmas belgilar ham xuddi shunday o'tib ketardi.

## Nima ruxsat etiladi

* lotin harflari (`A–Z`, `a–z`) va o'zbek diakritikasi (`ʻ`, `ʼ`, `'`)
* kirill harflari — ruscha foydalanuvchi o'z ismini yoza olishi kerak
* raqamlar, bo'shliq, defis, nuqta

Ataylab RAD ETILADI:

| Nima | Nega |
|---|---|
| CJK, arab, hind yozuvlari | Bizning auditoriya emas; ular deyarli har doim sinov yoki spam |
| Emoji | Reyting qatorini buzadi, qidiruvda topilmaydi |
| Nol kenglikdagi belgilar (`U+200B`, `U+200E`…) | Ko'rinmas — ikkita "bir xil" ism yaratish yo'li |
| Boshqaruv belgilari | Terminal va log'ni buzadi |

## Nega server tomonda

Klientdagi `FilteringTextInputFormatter` faqat qulaylik. Telegram'dan
kelgan `first_name` esa **umuman klientdan o'tmaydi** — u bot API'dan
to'g'ridan-to'g'ri keladi. Shuning uchun yagona ishonchli joy — shu modul.
"""
from __future__ import annotations

import re
import unicodedata

MIN_LEN = 1
MAX_LEN = 40

# Ruxsat etilgan belgilar. Kirill ataylab kiritilgan: `ru` interfeysi bor.
_ALLOWED = re.compile(
    r"^[A-Za-z0-9Ѐ-ӿ"      # lotin, raqam, kirill
    r"ʻʼ‘’'"     # o'zbek tutuq belgisi shakllari
    r" .\-]+$"
)

# Ko'rinmas va boshqaruv belgilari — matn ichidan olib tashlanadi.
_INVISIBLE = re.compile(r"[​-‏‪-‮⁠-⁯﻿]")

# Ketma-ket bo'shliqlar bittaga tushiriladi.
_SPACES = re.compile(r"\s+")


class NameError_(ValueError):
    """Ism qoidaga mos emas."""


def clean_name(raw: str | None) -> str:
    """Tozalaydi: NFKC normalizatsiya, ko'rinmas belgilar olib tashlanadi,
    bo'shliqlar siqiladi, chetlari kesiladi.

    NFKC nega kerak: `ｚｉｚｕ` (to'liq kenglikdagi lotin) ko'zga `zizu` deb
    ko'rinadi, lekin boshqa kod nuqtalari. Normalizatsiyasiz ikkita
    "bir xil" ism bo'lib qolardi.
    """
    s = unicodedata.normalize("NFKC", raw or "")
    s = _INVISIBLE.sub("", s)
    s = "".join(ch for ch in s if unicodedata.category(ch)[0] != "C")
    s = _SPACES.sub(" ", s).strip()
    return s


def is_valid_name(raw: str | None) -> bool:
    s = clean_name(raw)
    return bool(MIN_LEN <= len(s) <= MAX_LEN and _ALLOWED.match(s))


def validate_name(raw: str | None) -> str:
    """Tozalangan ismni qaytaradi yoki `NameError_` ko'taradi."""
    s = clean_name(raw)
    if not (MIN_LEN <= len(s) <= MAX_LEN):
        raise NameError_("ism 1–40 belgidan iborat bo'lsin")
    if not _ALLOWED.match(s):
        raise NameError_(
            "ismda faqat harflar, raqamlar, bo'shliq va - . ' belgilari "
            "bo'lishi mumkin")
    return s


def safe_name(raw: str | None, fallback: str = "") -> str:
    """Tashqi manbadan (Telegram) kelgan ism uchun.

    Bu yerda XATO KO'TARILMAYDI: Telegram'da ismi `火` bo'lgan odam ham
    ilovaga kira olishi kerak — shunchaki ismi olinmaydi va u profilda o'zi
    kiritadi. Kirishni bloklash mutlaqo nomutanosib javob bo'lardi.
    """
    s = clean_name(raw)
    return s if (MIN_LEN <= len(s) <= MAX_LEN and _ALLOWED.match(s)) else fallback
