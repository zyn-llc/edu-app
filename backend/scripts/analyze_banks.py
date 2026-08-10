#!/usr/bin/env python3
"""
analyze_banks.py — `clean_data/` da yotgan, lekin bazaga TUSHMAGAN savollarni
tahlil qiladi.

    PYTHONPATH=. python scripts/analyze_banks.py "D:\\data_subjects\\clean_data"
    PYTHONPATH=. python scripts/analyze_banks.py "D:\\data_subjects\\clean_data" --samples 15

Nima uchun: `run_subject.py` da `LOADABLE_TYPES = {"mcq"}` turibdi, ya'ni
`text_open` turidagi har bir savol "non-mcq type" sababi bilan o'tkazib
yuboriladi. Ular normalizatsiyadan o'tgan, fayllarda yotibdi, lekin hech
qachon yuklanmagan.

Savol shu: ularni yuklash XAVFSIZMI? Javob `grading_spec.accepted_forms`
ga bog'liq:

  * Agar javob BITTA SONGA yechilsa   → `numeric` grader ishlatiladi.
    U kasrni (1/3), vergulli o'nlikni (0,5), Unicode minusni (−2) va
    tolerantlikni qo'llab-quvvatlaydi — o'quvchi qanday yozsa ham tushunadi.
    XAVFSIZ.

  * Agar javob MATN bo'lsa            → `open_keyword` grader ishlatiladi.
    U aynan mos kelishni talab qiladi. `normalizer.normalize()` bo'sh joyni
    SAQLAYDI (faqat ketma-ket bo'shliqlarni bittaga tushiradi), shuning uchun
    "x=3, y=8" saqlangan bo'lsa, o'quvchining "x=3,y=8" javobi NOTO'G'RI
    deb baholanadi. XAVFLI.

Bu skript ana shu ikki guruhni sanaydi va xavfli namunalarni ko'rsatadi.
HECH NARSANI O'ZGARTIRMAYDI — faqat o'qiydi va hisobot chiqaradi.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict

try:
    from app.services.normalizer import normalize
    from app.services.grading import _parse_student_number
except ImportError:
    print("XATO: backend paketi topilmadi.\n"
          "  cd \"D:\\platform edu\\backend\"\n"
          "  $env:PYTHONPATH = \".\"\n"
          "  python scripts/analyze_banks.py <clean_data yo'li>", file=sys.stderr)
    raise SystemExit(2)

def load_core(path: str):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict):
        for key in ("items", "questions", "core", "data"):
            if isinstance(data.get(key), list):
                return data[key]
        return []
    return data if isinstance(data, list) else []

def numeric_forms(forms: list[str]) -> list[float]:
    """Bitta songa yechiladigan variantlar."""
    out = []
    for f in forms:
        try:
            out.append(_parse_student_number(f))
        except Exception:
            pass
    return out

_RISKY_CHARS = re.compile(r"[ ,;=()\[\]{}/]")

def classify(q: dict) -> tuple[str, list[str], str]:
    """(guruh, accepted_forms, sabab) qaytaradi."""
    spec = q.get("grading_spec") or {}
    forms = spec.get("accepted_forms") or spec.get("accepted") or []
    if isinstance(forms, str):
        forms = [forms]
    forms = [str(f).strip() for f in forms if str(f).strip()]

    if not forms:
        return "buzuq", forms, "accepted_forms bo'sh — baholab bo'lmaydi"

    nums = numeric_forms(forms)
    if nums:
        spread = max(nums) - min(nums) if len(nums) > 1 else 0.0
        if spread > 1e-9:
            return ("ziddiyatli", forms,
                    f"variantlar turli son beradi: {sorted(set(nums))[:4]}")
        return "numeric", forms, f"son sifatida yechildi: {nums[0]:g}"

    norm = [normalize(f) for f in forms]
    risky = [f for f in norm if _RISKY_CHARS.search(f)]
    if risky:
        return ("xavfli_kalit", forms,
                "bo'sh joy/vergul/tenglik belgisi bor — aynan moslik talab qilinadi")
    if any(len(f) > 40 for f in norm):
        return "xavfli_kalit", forms, "javob juda uzun (>40 belgi)"
    return "xavfsiz_kalit", forms, "qisqa, bitta tokenli matn"

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("clean_data", help="clean_data papkasining yo'li")
    ap.add_argument("--samples", type=int, default=8,
                    help="har guruhdan nechta namuna ko'rsatilsin")
    args = ap.parse_args()

    base = args.clean_data
    if not os.path.isdir(base):
        print(f"XATO: papka yo'q: {base}", file=sys.stderr)
        return 2

    by_type = Counter()
    groups = Counter()
    per_bank: dict[str, Counter] = defaultdict(Counter)
    samples: dict[str, list] = defaultdict(list)
    reasons = Counter()

    banks = sorted(d for d in os.listdir(base)
                   if os.path.exists(os.path.join(base, d, "core.json")))

    for bank in banks:
        rows = load_core(os.path.join(base, bank, "core.json"))
        for q in rows:
            if not isinstance(q, dict):
                continue
            qtype = q.get("type") or q.get("question_type") or "?"
            by_type[qtype] += 1
            per_bank[bank][qtype] += 1
            if qtype != "text_open":
                continue
            grp, forms, why = classify(q)
            groups[grp] += 1
            per_bank[bank][f"~{grp}"] += 1
            reasons[why[:70]] += 1
            if len(samples[grp]) < args.samples:
                samples[grp].append((bank, q.get("id"), forms, why))

    line = "=" * 74
    print(line)
    print("  BANK TAHLILI — clean_data va baza o'rtasidagi farq")
    print(line)
    print(f"  papka : {base}")
    print(f"  banklar: {len(banks)}")

    # ---- 1. Turlar bo'yicha ----
    print("\n--- 1. SAVOL TURLARI (clean_data'da) " + "-" * 36)
    total = sum(by_type.values())
    for t, n in by_type.most_common():
        state = "yuklanadi" if t == "mcq" else "O'TKAZIB YUBORILADI"
        print(f"  {t:<14} {n:>7}   {state}")
    loadable = by_type.get("mcq", 0)
    print(f"  {'JAMI':<14} {total:>7}")
    print(f"\n  Bazaga tushadi : {loadable:>7}")
    print(f"  Yo'lda qoladi  : {total - loadable:>7}"
          f"   ({(total - loadable) / total * 100:.0f}%)")

    # ---- 2. text_open guruhlari ----
    to = by_type.get("text_open", 0)
    if to:
        print("\n--- 2. text_open SAVOLLARINI YUKLASH XAVFSIZMI? " + "-" * 25)
        order = ["numeric", "xavfsiz_kalit", "xavfli_kalit", "ziddiyatli", "buzuq"]
        labels = {
            "numeric":       "numeric grader  — XAVFSIZ, darhol yuklash mumkin",
            "xavfsiz_kalit": "open_keyword    — xavfsiz (qisqa, bitta token)",
            "xavfli_kalit":  "open_keyword    — XAVFLI, aynan moslik kerak",
            "ziddiyatli":    "variantlar bir-biriga zid — qo'lda ko'rish kerak",
            "buzuq":         "accepted_forms yo'q — baholab bo'lmaydi",
        }
        for g in order:
            n = groups.get(g, 0)
            if n:
                print(f"  {n:>7}  ({n / to * 100:>4.0f}%)  {labels[g]}")
        safe = groups.get("numeric", 0) + groups.get("xavfsiz_kalit", 0)
        print(f"\n  DARHOL YUKLASA BO'LADI : {safe:>7}  ({safe / to * 100:.0f}%)")
        print(f"  ISHLASH KERAK          : {to - safe:>7}  ({(to - safe) / to * 100:.0f}%)")

        # ---- 3. Namunalar ----
        print("\n--- 3. NAMUNALAR " + "-" * 56)
        for g in order:
            if not samples[g]:
                continue
            print(f"\n  [{g}]")
            for bank, qid, forms, why in samples[g]:
                shown = " | ".join(forms[:3])
                if len(shown) > 58:
                    shown = shown[:55] + "..."
                print(f"    {bank}/{qid}")
                print(f"      javob : {shown}")
                print(f"      sabab : {why}")

    # ---- 4. Bank bo'yicha ----
    print("\n--- 4. BANK BO'YICHA " + "-" * 52)
    print(f"  {'bank':<14}{'mcq':>7}{'text_open':>11}{'numeric':>9}{'xavfli':>8}")
    for bank in banks:
        c = per_bank[bank]
        m, t = c.get("mcq", 0), c.get("text_open", 0)
        flag = "  <-- BAZAGA HECH NARSA TUSHMAGAN" if m == 0 and t else ""
        print(f"  {bank:<14}{m:>7}{t:>11}{c.get('~numeric', 0):>9}"
              f"{c.get('~xavfli_kalit', 0):>8}{flag}")

    print("\n" + line)
    print("  Bu skript hech narsani o'zgartirmadi — faqat o'qidi.")
    print(line)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
