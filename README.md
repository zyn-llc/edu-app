# Topag'on

**O'zbekiston maktab o'quvchilari (5–11-sinf) uchun bilim musobaqasi.**
Fan bo'yicha mashq, server tomonda baholash, reyting va do'st bilan bellashuv.

> *A quiz and competition platform for Uzbek school students. FastAPI +
> PostgreSQL/PostGIS + Redis backend, Flutter (Web + Android) client, ~17 000
> curated Uzbek-language questions tagged by grade and topic. All grading is
> server-side; the client never receives an answer key it hasn't earned.*

| | |
|---|---|
| **Ilova** | https://app.topagon.uz |
| **API** | https://api.topagon.uz |
| **Sahifa** | https://topagon.uz |
| **Bot** | [@topagonuzbot](https://t.me/topagonuzbot) |

```
Backend   FastAPI · async SQLAlchemy 2.0 · PostgreSQL 16 + PostGIS · Redis 7
Klient    Flutter (Material 3, Riverpod, Dio) — Web + Android
Deploy    Docker Compose · nginx · Let's Encrypt · Ubuntu 24.04 VPS
Hajm      7 700 qator backend · 16 000 qator Dart · 42 endpoint · 104 test
Kontent   ~17 000 aktiv savol · 7 fan · sinf va mavzu bo'yicha teglangan
Til       uz-Latn (asosiy) + ru — 387 kalit, ikkalasi ham to'liq
```

---

## Arxitekturaning uchta qarori

Loyihada eng ko'p vaqt ketgan uchta qaror — qolgani shulardan kelib chiqadi.

### 1. Javob kaliti serverdan chiqmaydi

`questions.grading_spec` (JSONB) — yagona haqiqat manbai. `options` jadvalida
`is_correct` ustuni **umuman yo'q**.

Klientga ketadigan model (`PublicQuestion`) va serverdagi model
(`GradingQuestion`) ikki xil tip, va ular orasida yagona o'tish nuqtasi bor —
`services/projection.py`. Ya'ni kalit sizib chiqishi "esdan chiqarmaslik"
bilan emas, **tip tizimi bilan** to'siladi: ommaviy modelda kalitni saqlaydigan
maydon yo'q.

Kalit faqat bitta joyda, faqat **to'g'ri javobdan keyin** beriladi —
`api/v1/content.py` dagi bitta `if result.is_correct:`. Bu shart olib
tashlansa, "bir marta xato qil → javobni o'qi → qayta yubor" farmi ochiladi:
XP, noncoin va reyting cheksiz yig'iladi. Shuning uchun u
`tests/test_submissions.py` bilan qulflangan.

### 2. Valyuta — balans emas, DAFTAR

`coin_transactions` — append-only jurnal. Balans hech qayerda saqlanmaydi, u
`SUM(amount)`. Har bir yozuvning sababi (`reason`) cheklangan ro'yxatdan, va
u ro'yxatda **pulga aylantiradigan sabab yo'q** — aynan shu narsa buni o'yin
valyutasi darajasida ushlab turadi.

"Bir marta bo'ladigan" har bir mukofot **qismiy noyob indeks** bilan
qo'riqlanadi, Python sharti bilan emas:

```sql
CREATE UNIQUE INDEX uq_coin_quiz_reward
    ON coin_transactions (user_id, ref_id) WHERE reason = 'quiz_reward';
CREATE UNIQUE INDEX uq_coin_challenge_settle
    ON coin_transactions (user_id, reason, ref_id)
    WHERE reason IN ('challenge_refund', 'challenge_win');
```

Sabab: indeks kod qanday chaqirilishidan qat'i nazar ishlaydi. Lock unutilishi
mumkin, tranzaksiya izolyatsiyasi kutilmagan bo'lishi mumkin — indeks esa
yo'q. XP ham shu insert muvaffaqiyatiga bog'langan, ya'ni savolni qayta yechish
XP bermaydi.

### 3. Reyting Postgres'da emas, Redis'da

`lb:total`, `lb:subject:*`, `lb:region:*` — sorted set. O'qish `ZREVRANGE` /
`ZREVRANK`, ya'ni O(log N). Postgres faqat ko'rsatilayotgan sahifadagi ismlarni
olish uchun so'raladi.

---

## Ishga tushirish

### Backend (lokal)

```bash
cd backend
cp .env.example .env
docker compose up -d --build
curl http://127.0.0.1:8000/health
```

Migratsiyalar tartib bilan va bir martadan qo'llanadi (`schema_migrations`
jadvalida qayd yuritiladi):

```bash
./scripts/migrate.sh --status
./scripts/migrate.sh
```

### Testlar (baza kerak emas)

```bash
cd backend
pip install -r requirements.txt
PYTHONPATH=. python -m pytest tests -q
```

Testlar ataylab DB'siz: ular mantiqni tekshiradi, SQL'ni emas. DB'ga
bog'liq bo'lgani — `scripts/preflight.py` va `app/ingest/audit_grading.py`.

### Klient

```bash
cd mobile
flutter pub get && flutter gen-l10n
flutter run -d chrome --dart-define=MOCK=true     # serversiz demo
```

`MOCK=true` — tarmoqqa umuman chiqmaydigan rejim: `lib/api/mock_backend.dart`
40+ endpointni ichkarida taqlid qiladi. Demo va UI testlari uchun. Mock **real
server bilan bir xil qoidalarga bo'ysunadi** — masalan noto'g'ri javobda kalit
qaytarmaydi; aks holda mockda ishlaydigan ekran prodda boshqacha ko'rinardi.

```bash
flutter analyze && flutter test --dart-define=MOCK=true
```

---

## Papkalar

```
backend/
  app/
    api/v1/          42 endpoint — handler'lar yupqa, mantiq services/ da
    api/deps.py      autentifikatsiya/avtorizatsiya bog'liqliklari
    core/            config, xavfsizlik, rate limit, anti-scraping, Redis
    models/          ORM
    schemas/         public / grading proyeksiya ajratmasi
    services/        grading, coins, challenges, ranking, progress, telegram
    ingest/          savol banklarini JSON'dan bazaga yuklash
  sql/               001..026 — forward-only migratsiyalar
  tests/             104 test — DB kerak emas
  deploy/            nginx konfiguratsiyalari (api / ilova / sahifa)
  scripts/           migrate, backup, preflight, telegram_setup, make_invites
mobile/
  lib/
    api/             Dio klient + mock backend
    auth/            token saqlash, auth kontrolleri
    features/        ekranlar (quiz, challenges, leaderboard, parent, ...)
    theme/ widgets/  dizayn tizimi
    l10n/            uz + ru (.arb — manba, .dart generatsiya qilinadi)
landing/             topagon.uz reklama sahifasi (statik)
docs/                arxitektura, testlash, deploy, kontent auditi
```

---

## Xavfsizlik

Prodda ishga tushishdan oldin `config.validate_runtime()` **10 ta shartni**
tekshiradi va bittasi bajarilmasa server **umuman ko'tarilmaydi**: zaif
`JWT_SECRET`, OTP kodining javobda qaytishi, standart DB paroli, `CORS_ORIGINS=*`,
SMS shlyuzining `console` rejimi, Telegram webhook sirining yo'qligi, va
klientga ishonadigan reklama mukofoti.

Boshqa qatlamlar:

* **Autentifikatsiya** — HS256 JWT (15 daq) + rotatsiya qilinadigan, faqat
  SHA-256 hash ko'rinishida saqlanadigan refresh token (30 kun). Parol —
  argon2.
* **Telegram kirish ikki bosqichli** — bot «Start» da hisobni bog'lamaydi,
  ilova ekranidagi kod bilan tasdiq so'raydi. Usiz oqim bir bosishda hisob
  o'g'irlash edi (`services/telegram.py` izohiga qara).
* **Rate limit** — o'quv yo'llarida ochiq, auth yo'llarida **yopiq** ishlaydi:
  Redis uzilishi o'quvchini mashq o'rtasida to'xtatmasligi kerak, lekin u
  parolni cheksiz taxmin qilishga yo'l ochmasligi ham kerak.
* **Anti-scraping** — savol banki mahsulotning asosiy aktivi. Burst chegarasi
  (30/daq) va HyperLogLog bilan hisoblanadigan "kenglik" nazorati (soatiga 900
  ta noyob savol): haqiqiy o'quvchi tor to'plamga qaytadi, skraper esa hech
  qachon takrorlamaydi.
* **Avtorizatsiya** — ota-ona paneli rolga emas, **guardianship yozuviga**
  bog'langan, u esa faqat bolaning o'zi bergan kod orqali yaratiladi.

---

## Hujjatlar

| Fayl | Nima haqida |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | konvensiyalar va qatlamlar |
| [docs/TESTING.md](docs/TESTING.md) | test strategiyasi |
| [docs/openapi.yaml](docs/openapi.yaml) | API kontrakti |
| [backend/BOSHLASH.md](backend/BOSHLASH.md) | noldan deploy, 1–13 qadam |
| [backend/deploy/DEPLOY.md](backend/deploy/DEPLOY.md) | VPS sozlamalari |
| [CHANGELOG.md](CHANGELOG.md) | nima o'zgardi va nega |

---

## Litsenziya

Hozircha yopiq manba. Kod President Tech Award ko'rigi uchun ochilgan.
