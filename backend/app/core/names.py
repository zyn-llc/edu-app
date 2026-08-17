from __future__ import annotations

import re
import unicodedata

MIN_LEN = 1
MAX_LEN = 40

_ALLOWED = re.compile(
    r"^[A-Za-z0-9Ѐ-ӿ"      # lotin, raqam, kirill
    r"ʻʼ‘’'"     # o'zbek tutuq belgisi shakllari
    r" .\-]+$"
)

_INVISIBLE = re.compile(r"[​-‏‪-‮⁠-⁯﻿]")


_SPACES = re.compile(r"\s+")

class NameError_(ValueError):

def clean_name(raw: str | None) -> str:
    s = unicodedata.normalize("NFKC", raw or "")
    s = _INVISIBLE.sub("", s)
    s = "".join(ch for ch in s if unicodedata.category(ch)[0] != "C")
    s = _SPACES.sub(" ", s).strip()
    return s

def is_valid_name(raw: str | None) -> bool:
    s = clean_name(raw)
    return bool(MIN_LEN <= len(s) <= MAX_LEN and _ALLOWED.match(s))

def validate_name(raw: str | None) -> str:
    s = clean_name(raw)
    if not (MIN_LEN <= len(s) <= MAX_LEN):
        raise NameError_("ism 1–40 belgidan iborat bo'lsin")
    if not _ALLOWED.match(s):
        raise NameError_(
            "ismda faqat harflar, raqamlar, bo'shliq va - . ' belgilari "
            "bo'lishi mumkin")
    return s

def safe_name(raw: str | None, fallback: str = "") -> str:
    s = clean_name(raw)
    return s if (MIN_LEN <= len(s) <= MAX_LEN and _ALLOWED.match(s)) else fallback
