# Kontent auditi — 2026-08-06

> Prod raqamlari `https://api.topagon.uz/v1/subjects` dan **o'lchangan**.
> Manba raqamlari `D:\data_subjects\clean_data\*/core.json` va `uz.json`
> fayllarini o'qib hisoblangan. Taxmin qilingan raqam yo'q.

---

## 1. Proddagi bank (aktiv savollar)

| Fan | Aktiv savol | Bo'lim |
|---|---:|---:|
| Geografiya | 7 169 | 179 |
| Matematika | 5 453 | 128 |
| O'zbekiston tarixi | 2 415 | 46 |
| Biologiya | 1 540 | 58 |
| Ona tili | 824 | 10 |
| Huquq | 644 | 34 |
| Jahon tarixi | 620 | 24 |
| **Jami** | **18 665** | **479** |
| Geometriya · Fizika · Kimyo | 0 | 0 |

---

## 2. Manba fayllar — papka, sinf, oxirgi ID

Bank 25 ta papkadan yuklangan. `sinf` — `core.json` dagi `grade` maydoni.

| Papka | Savol | Sinf | Oxirgi ID |
|---|---:|---|---|
| bio_g5 | 134 | 5 | `bio_g5_q0134` |
| bio_g6 | 806 | 6 | `bio_g6_q0806` |
| bio_g8 | 227 | 8 | `bio_g8_q0227` |
| bio_g9 | 491 | 9 | `bio_g9_q0491` |
| geo_g5 | 699 | 5 | `geo_g5_q0699` |
| geo_g6 | 1 537 | 6 | `geo_g6_q1537` |
| geo_g7 | 1 399 | 7 | `geo_g7_q1399` |
| geo_g8 | 1 152 | 8 | `geo_g8_q1152` |
| geo_g9 | 1 378 | 9 | `geo_g9_q1378` |
| geo_g10 | 1 200 | 10 | `geo_g10_q1200` |
| hist_g6 | 662 | 6 | `hist_g6_q0662` |
| hist_g7 | 524 | 7 | `hist_g7_q0524` |
| hist_g11 | 1 234 | 11 (1 006) + **NULL (228)** | `hist_g11_q1234` |
| wh_g11 | 620 | 11 | `wh_g11_q0620` |
| law_g8 | 325 | **NULL** | `law_g8_q0325` |
| law_g9 | 290 | **NULL** | `law_g9_q0290` |
| law_dtm | 30 | **NULL** | `law_dtm_q0030` |
| math_g5 | 999 | 5 | `math_g5_q0999` |
| math_g6 | 1 163 | **NULL** | `math_g6_q1163` |
| math_g7 | 2 559 | 7 | `math_g7_q2559` |
| math_g8 | 976 | 8 | `math_g8_q0976` |
| math_g9 | 1 514 | 9 | `math_g9_q1514` |
| math_g10 | 1 720 | **NULL** | `math_g10_q1720` |
| math_g11 | 1 011 | **NULL** | `math_g11_q1011` |
| ona_tili | 834 | **NULL** | `ona_tili_q0834` |
| **Jami** | **23 484** | | |

### ⚠️ Topilma 1 — manbada `grade` bo'sh

`math_g6`, `math_g10`, `math_g11`, `law_*`, `ona_tili` va `hist_g11` ning
228 tasida `grade = null`. Papka nomida sinf turibdi, lekin maydonga
yozilmagan.

Bazada bu `sql/018_backfill_grades.sql` bilan to'ldirilgan, ya'ni **prodda
muammo yo'q**. Lekin YANGI bank yuklanganda xato qaytadi. Shuning uchun
`run_subject.py --dry-run` da sinf taqsimotini har safar ko'rish shart.

### ⚠️ Topilma 2 — `subject` kodi bir xil emas

Manbada bitta fan uch xil nom bilan yozilgan:

```
biologiya / biology
matematika / math / mathematics / math_g10 / math_g11 / math_g6
history / world_history
```

`020_dedupe_subjects.sql` buni bazada birlashtirgan. Manba fayllar esa
tuzatilmagan — qayta yuklashda dublikat fan yana paydo bo'ladi.

---

## 3. Buzuq savollar

### 3.1 Matnda qolgan tartib raqami — **137 ta**

Parser PDF'dagi raqamlashni matn ichida qoldirgan:

```
"12. Tabiat komponentlari birgalikda nimani hosil qiladi?"
```

Ilova o'z tartib raqamini ("3/20") ko'rsatgani uchun bu ikkilanadi va savol
buzuq ko'rinadi.

| Papka | Soni | Ulushi |
|---|---:|---:|
| ona_tili | 105 | 12.6% |
| geo_g5 | 32 | 4.6% |

### 3.2 Variantda qolgan harf prefiksi — **205 savol**

```
variantlar:  "A)mavjudod, tajjub"   "B)muhofaza, loqayd"
```

Ilova variantlar yoniga o'z A/B/C/D doirasini chizadi — o'quvchi **ikkita
harf** ko'radi.

| Papka | Soni |
|---|---:|
| ona_tili | 98 |
| wh_g11 | 40 |
| geo_g6 | 23 |
| bio_g9, geo_g10 | 15 |
| qolganlari | 14 |

**Yechim:** `sql/023_strip_numbering.sql` — deploy'da avtomatik qo'llanadi.
Shart ataylab tor (raqamdan keyin `.`/`)`, undan keyin HARF), shuning uchun
`"1991 – 2017-yillarda"` yoki `"2) 5x + 3 = 13"` kabi matnlarga tegmaydi.

### 3.3 Juda qisqa savol matni — 7 ta

`"Ufq nima?"`, `"Spora bu..."`, `"Agora nima?"` — bular **xato emas**,
haqiqiy qisqa ta'rif savollari. Tegilmadi.

---

## 4. Tur bo'yicha (prod)

```
mcq           13 447 aktiv    368 draft   1 001 retired
numeric        2 924 aktiv
open_keyword     895 aktiv  4 097 draft
```

**4 097 ta `open_keyword` draft** hali ko'rib chiqilmagan
(`tags->>'risky_answer' = 'true'`). Ko'pchiligi aslida tanlovli savol
("I va III chorak") — ularni `mcq` ga aylantirish to'g'ri yechim. Bu
launch'ga to'siq emas: ular `draft` bo'lgani uchun o'quvchiga ko'rinmaydi.

---

## 5. Nima qilinishi kerak

| # | Ish | Holat |
|---|---|---|
| 1 | Bazadagi raqamlash/prefikslarni tozalash | ✅ `023_strip_numbering.sql` yozildi |
| 2 | Manba fayllarda `subject` kodini birxillashtirish | ⬜ qayta yuklashdan oldin |
| 3 | Manba fayllarda `grade` ni to'ldirish | ⬜ qayta yuklashdan oldin |
| 4 | `normalize` bosqichiga raqamlashni kesish qo'shish | ⬜ yangi bank uchun |
| 5 | 4 097 draftni ko'rib chiqish | ⬜ launch'dan keyin |
| 6 | Fizika / Kimyo / Geometriya banklari | ⬜ launch'dan keyin |
