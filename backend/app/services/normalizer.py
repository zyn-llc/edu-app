"""
Text normalizer for answer grading.

Why this exists: Uzbek is written in two scripts (Latin and Cyrillic). A student
may type "Toshkent" or "Тошкент" — both are correct. If we don't fold them to one
canonical form, keyword grading silently marks correct answers wrong. The SAME
normalizer must run over stored accepted answers and over student input.

Pure functions, no I/O, no DB — so it is trivially unit-testable.
"""
from __future__ import annotations
import re
import unicodedata

# Uzbek Cyrillic -> Latin. Multi-char first is unnecessary since each Cyrillic
# letter is a single codepoint; we map codepoint -> latin string.
_CYRILLIC_TO_LATIN = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo",
    "ж": "j", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
    "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
    "ф": "f", "х": "x", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sh",
    "ъ": "'", "ы": "i", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    "ў": "o'", "қ": "q", "ғ": "g'", "ҳ": "h",
}

# Any apostrophe-like glyph (oʻ, oʼ, oʹ, o`, o´) -> straight quote.
_APOSTROPHES = "\u02bb\u02bc\u02b9\u2018\u2019\u0060\u00b4\u2032"
_APOS_RE = re.compile(f"[{re.escape(_APOSTROPHES)}]")
_WS_RE = re.compile(r"\s+")


def _transliterate(text: str) -> str:
    out = []
    for ch in text:
        lower = ch.lower()
        if lower in _CYRILLIC_TO_LATIN:
            mapped = _CYRILLIC_TO_LATIN[lower]
            out.append(mapped.upper() if ch.isupper() else mapped)
        else:
            out.append(ch)
    return "".join(out)


def normalize(text: str) -> str:
    """Canonical form for comparison.

    Pipeline: NFKC -> transliterate Cyrillic to Latin -> unify apostrophes ->
    lowercase -> strip -> collapse internal whitespace.
    """
    if text is None:
        return ""
    text = unicodedata.normalize("NFKC", text)
    text = _transliterate(text)
    text = _APOS_RE.sub("'", text)
    text = text.lower().strip()
    text = _WS_RE.sub(" ", text)
    return text
