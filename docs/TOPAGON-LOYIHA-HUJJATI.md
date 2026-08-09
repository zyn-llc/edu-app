# Topag'on — loyiha hujjati

**O'zbekiston maktab o'quvchilari (5–11-sinf) uchun bilim musobaqasi ilovasi**

| | |
|---|---|
| Sana | 2026-08-06 |
| Holat | Prodda ishlayapti, yopiq beta |
| Backend | `https://api.topagon.uz` |
| Ilova | `https://topagon.uz` |
| Telegram bot | `@topagonuzbot` |
| Hajm | Backend ~6 800 satr Python · Ilova ~12 200 satr Dart · Landing ~1 700 satr |
| Testlar | 85 ta o'tadi |
| Endpointlar | 46 ta |

> Bu hujjat **fikr-mulohaza olish uchun** yozilgan. Har bir qarorning yonida
> "nega shunday qilingan" bor — chunki fikr bildirish uchun natijani emas,
> sababni ko'rish kerak. Oxirgi bo'limda **aniq nimalar bo'yicha fikr
> kutilayotgani** sanab o'tilgan.

---

## 1. Muammo va yechim

### Muammo

O'zbekistonda 5–11-sinf o'quvchisi imtihonga tayyorlanayotganda uchta narsaga
duch keladi:

1. **Savollar tarqoq.** Darslik oxiridagi testlar, PDF to'plamlar, Telegram
   kanallardagi rasmlar. Bir joyda, sinf va mavzu bo'yicha saralangan bank yo'q.
2. **Javob kaliti bilan birga tarqaladi.** PDF'da javob pastda turadi —
   o'quvchi o'zini aldashi juda oson va bu mashqning ma'nosini yo'qotadi.
3. **Motivatsiya yo'q.** Yolg'iz test yechish zerikarli. O'quvchi 15 daqiqadan
   keyin tashlab ketadi.

### Yechim

Uchtasiga uchta javob:

1. **Yagona bank** — 18 000 dan ortiq savol, sinf/fan/mavzu bo'yicha
   filtrlanadi, hammasi bitta joyda.
2. **Javob kaliti faqat serverda.** Klientga savol matni va variantlar
   beriladi, to'g'ri javob esa **yo'q**. O'quvchi javobini yuborgandan
   **keyin** natijani oladi. Bu invariant butun kod bo'ylab bitta joyda
   (`services/projection.py`) qo'riqlanadi.
3. **O'yin mexanikasi** — XP, daraja, seriya (streak), tanga, reyting va
   do'st bilan 1v1 bellashuv.

---

## 2. Texnologiya to'plami

| Qatlam | Nima | Nega |
|---|---|---|
| Backend | FastAPI + async SQLAlchemy 2.0 | Async I/O — 2 GB RAM li VPS'da ham minglab ulanish |
| Baza | PostgreSQL 16 + PostGIS | Savollar, foydalanuvchilar, tranzaksiyalar |
| Kesh/reyting | Redis 7 | Reyting sorted set'lari, OTP, rate limit, Telegram nonce |
| Klient | Flutter (Material 3) | Bitta koddan Android + Web + desktop |
| Holat boshqaruvi | Riverpod 2 | Provider'lar orasidagi bog'liqlik aniq ko'rinadi |
| Tarmoq | Dio | Interceptor'lar: token, til, avtomatik refresh |
| Konteynerlar | Docker Compose | `docker-compose.prod.yml` — api, db, redis |
| Reverse proxy | nginx + certbot | TLS, statik fayllar |

### Nega Flutter Web, React emas

Deadline — 2 kun, jamoa — bitta odam. Flutter'da **bitta kod bazasi** Android
APK ham, veb-sayt ham beradi. React tanlansa, mobil uchun alohida React Native
kod bazasi kerak bo'lardi.

Narxi: Flutter Web'ning birinchi yuklanishi og'ir (~3 MB CanvasKit). Buni
brendlangan yuklanish ekrani bilan qopladik — foydalanuvchi oq sahifaga emas,
logotipga qaraydi.

---

## 3. Backend arxitekturasi

### 3.1 Qatlamlar

```
app/
├── api/v1/          — HTTP qatlami. Faqat: so'rovni tekshirish, xizmatni
│                      chaqirish, javobni shakllantirish. Biznes mantiq YO'Q.
├── services/        — biznes mantiq. HTTP'ni bilmaydi, testlash oson.
├── models/          — SQLAlchemy ORM (22 ta jadval)
├── schemas/         — Pydantic: kirish validatsiyasi + chiqish shakli
├── core/            — config, security, database, redis, ratelimit, antiabuse
└── ingest/          — savol banklarini JSON'dan bazaga yuklash
```

**Qoida:** `api/` dagi handler 40 satrdan oshsa — mantiq `services/` ga
ko'chirilishi kerak. Sabab: `api/` ni test qilish uchun butun FastAPI
ko'tarish kerak, `services/` ni esa oddiy funksiya sifatida chaqirsa bo'ladi.

### 3.2 Ma'lumotlar modeli (22 jadval)

**Kontent (tarjima ajratilgan)**

```
subjects ──< subject_translations
   │
   └──< topics ──< topic_translations
          │
          └──< questions ──< question_translations
                   │
                   └──< options ──< option_translations
```

Nega tarjima alohida jadvalda: savol **mantiqi** (qaysi variant to'g'ri,
qiyinlik, mavzu) tildan mustaqil. Rus tilini qo'shish uchun faqat
`*_translations` ga qator qo'shiladi, savol mantiqi qayta yozilmaydi.

**Foydalanuvchi**

| Jadval | Vazifa |
|---|---|
| `users` | rol, telefon, telegram_id, **username**, parol hash'i, avatar rangi, sinf, hudud |
| `refresh_tokens` | uzoq muddatli tokenlar — **faqat SHA-256 hash'i** saqlanadi |
| `guardianship` | ota-ona ↔ farzand bog'lanishi |
| `user_progress` | XP, daraja, seriya |
| `submissions` | har bir javob — audit izi va statistika manbai |

**Iqtisod va o'yin**

| Jadval | Vazifa |
|---|---|
| `coin_transactions` | **qo'shiluvchi (append-only) daftar** |
| `challenges`, `challenge_results` | 1v1 bellashuv |
| `invite_codes`, `invite_redemptions` | beta kirish kodlari |
| `notes`, `announcements`, `feedback` | daftar, e'lonlar, murojaat |

### 3.3 Muhim qaror: tanga balansi SAQLANMAYDI

`users.coins` ustuni **yo'q**. Balans — `SUM(amount)` daftar bo'yicha.

Nega: balans ustuni bo'lsa, u va daftar bir-biriga mos kelmay qolishi mumkin
(yozuv qo'shildi, ustun yangilanmadi — yoki teskarisi). Bunday xatoni topish
deyarli imkonsiz, chunki hech qayerda xato chiqmaydi, shunchaki raqam
noto'g'ri bo'lib qoladi. Yig'indi esa **ta'rifi bo'yicha** har doim to'g'ri.

Narxi: har o'qishda `SUM`. Bitta foydalanuvchida bir necha yuz qator —
indeks bilan bu mikrosoniyalar masalasi.

**Yopiq halqa:** tangani pulga aylantiradigan funksiya **yo'q** va bo'lmaydi
ham. Bu qimor bo'lib qolmasligi uchun ataylab shunday.

### 3.4 Javob kaliti hech qachon klientga bormaydi

Bu loyihaning eng muhim invarianti. `services/projection.py` — bitta
"tor joy" (choke point): ORM'dagi `Question` bu yerda ikkiga ajraladi:

| Turi | Nima bor | Qayerga ketadi |
|---|---|---|
| `PublicQuestion` | matn, variantlar | **klientga** |
| `GradingQuestion` | + `grading_spec` (javob kaliti) | **faqat serverda** |

`grading_spec` `PublicQuestion` sxemasida umuman yo'q — ya'ni uni tasodifan
qaytarib yuborishning iloji yo'q, Pydantic maydonni tashlab yuboradi.

Mock backend (`lib/api/mock_backend.dart`) ham shu qoidaga bo'ysunadi: demo
rejimida ham javob faqat yuborilgandan keyin ochiladi.

### 3.5 Baholash — savol turi bo'yicha

`services/grading.py` da har tur uchun alohida funksiya, reyestr orqali:

| Tur | Qanday baholanadi |
|---|---|
| `mcq` | variant `id` si mos keladimi |
| `multi_select` | to'plamlar teng bo'lishi kerak |
| `numeric` | songa aylantiriladi; **kasr** (`3/4`), **vergulli o'nlik** (`0,5`), **Unicode minus** (`−5`) tushuniladi; yaxlitlash farqi uchun tolerantlik bor |
| `open_keyword` | normalizatsiyadan keyin aynan moslik |
| `matching`, `ordering` | juftliklar / tartib |
| `open_text` | hozircha qo'lda — AI rubrikasi keyingi bosqichda |

`numeric` uchun alohida e'tibor sababi: o'quvchi javobni **qanday yozsa**,
shunday qabul qilinishi kerak. `0.5`, `0,5`, `1/2` — uchalasi ham to'g'ri.
Aks holda o'quvchi to'g'ri yechib, "noto'g'ri" degan javobni oladi va
ilovaga ishonchi yo'qoladi.

### 3.6 Reyting — Redis sorted set

Uchta ko'lam:

```
lb:total                    — umumiy
lb:subject:{fan_kodi}       — fan bo'yicha
lb:region:{hudud_kodi}      — hudud bo'yicha
```

O'qishda Postgres **umuman ishlatilmaydi** (`ZREVRANGE` / `ZREVRANK` /
`ZSCORE`); Postgres faqat ko'rsatilayotgan sahifadagi ismlarni olish uchun
so'raladi. Shuning uchun reyting `O(log N)` bo'lib qoladi — 10 million
foydalanuvchida ham bu qayta yozish emas, konfiguratsiya masalasi.

### 3.7 Bellashuv (1v1) — pul xavfsizligi

Holatlar: `open` → `active` → `done`, yon tarmoqlar `cancelled`, `expired`.

Kafolatlar:

* **Garov eskrouda.** Ikkala o'yinchi tangasi daftar orqali ushlab turiladi
  (`challenge_stake`, manfiy). Yon balans yo'q, klientga ishonch yo'q.
* **Savollar muzlatilgan.** `challenges.question_ids` yaratishda yoziladi —
  ya'ni osonroq savol olish uchun qayta tashlab bo'lmaydi, va ikkala o'yinchi
  **aynan bir xil** savollarni oladi.
* **Har yo'lda tanga saqlanadi.** G'alaba / durang / bekor qilish / muddati
  o'tishi — to'rttasida ham umumiy tanga miqdori o'zgarmaydi.
* **Bellashuv XP va reyting bermaydi.** Aks holda ikki hisob ochib, o'zaro
  o'ynab, reytingni sun'iy ko'tarish mumkin bo'lardi.

### 3.8 Kontentni himoya qilish (anti-scraping)

Savol banki — mahsulotning asosiy aktivi. U klientga **butunlay
yuborilmaydi**, savol-savol beriladi. Shuning uchun real xavf APK'ni
ochish emas, `/v1/questions` ni aylanib butun bankni yig'ib olish.

Ikki qatlam, ikki xil vazifa:

1. **Tezlik (rate)** — daqiqasiga qattiq chegara. Portlashni to'xtatadi.
2. **Hajm (volume)** — bir soatda ko'rilgan **turli** savollar soni.
   Sabrli yig'uvchi har qanday daqiqalik chegaradan pastda qoladi; uni
   ochib beradigan narsa — **kenglik**. Haqiqiy o'quvchi tor to'plamni
   qayta-qayta ko'radi, yig'uvchi esa hech qachon takrorlamaydi.

Turli savollar Redis HyperLogLog bilan sanaladi (~0.8% xato) — foydalanuvchi
boshiga o'nlab KB emas, bir necha yuz bayt.

Mehmon uchun bank determinantik namunaga qisqartiriladi: anonim chaqiruvchi
kontentning ko'p qismiga umuman yeta olmaydi.

**Redis ishlamay qolsa o'quvchi bloklanmaydi** — barcha tekshiruvlar
"ochiq yiqiladi" (fail open) va log yozadi. O'rganishni to'xtatish
scraping'dan ko'ra qimmatroq.

### 3.9 Autentifikatsiya — to'rt yo'l

| Yo'l | Holat | Vazifasi |
|---|---|---|
| **Foydalanuvchi nomi + parol** | ✅ ochiq | **Qaytib kirish** uchun asosiy yo'l |
| **Telegram** | ✅ ochiq | Birinchi marta kirish uchun eng tez — yozadigan narsa yo'q |
| **Taklif kodi** | ✅ ochiq | Yopiq beta sinovchilari |
| **Telefon + SMS** | ⛔ yopiq | Eskiz moderatsiyada (yuridik shaxs kerak) |

Klient qaysi yo'l ochiqligini `GET /v1/auth/methods` dan **oldindan**
so'raydi va faqat ishlaydiganlarini ko'rsatadi.

Nega bu muhim: ilgari kirish ekrani **telefon maydonini birinchi** qilib
ko'rsatardi. Foydalanuvchi raqamini kiritib, "Kod yuborish" ni bosib, 503
xatosini olardi. Ishlaydigan yagona yo'l esa ekranning **pastida** edi.
Ro'yxatdan o'tishdagi eng katta yo'qotish aynan shu yerda edi.

**Tokenlar:**

* Access — JWT, 15 daqiqa, holatsiz, ichida `sub` + `role`.
* Refresh — **shaffof bo'lmagan tasodifiy satr**, 30 kun. Bazada faqat
  SHA-256 hash'i. Har ishlatilganda **aylantiriladi** (rotation): eski qator
  bekor qilinadi, yangisi beriladi. Ya'ni o'g'irlangan refresh token ko'pi
  bilan bir marta ishlaydi, keyin haqiqiy foydalanuvchining navbatdagi
  yangilashi muvaffaqiyatsiz bo'ladi va o'g'irlik **ko'rinadi**.

Klientda bir vaqtda bir nechta so'rov 401 olsa, ular **bitta** yangilashni
kutadi (single-flight). Aks holda birinchisi tokenni aylantirar, qolganlari
eskirgan token bilan yiqilar va foydalanuvchi noo'rin tizimdan chiqarilardi.

### 3.10 Parol bilan kirish — qarorlar

**Shikoyat:** «har safar Telegramga o'tish sign up dek bo'lishi xato».

Foydalanuvchi haq edi. Mavjud uchala yo'l ham *qaytib* kirishga yaramasdi:
telefon o'chirilgan, taklif kodi bir martalik, Telegram esa har safar
brauzerdan chiqib, botda «Start» bosib qaytishni talab qilardi.

| Qaror | Sabab |
|---|---|
| Parol **6+ belgi**, murakkablik talab qilinmaydi | Foydalanuvchi — maktab o'quvchisi. "Katta harf + belgi" talabi amalda `Parol1!` yoki umuman voz kechish beradi. Kuch parolga emas, **urinishlar soniga** qo'yilgan |
| Cheklov **ikki o'lchamda**: IP bo'yicha 40/soat, nom bo'yicha 10/soat | Faqat IP bo'lsa — maktab Wi-Fi'si NAT ortida, bitta IP ortidagi sinf bir-birini bloklaydi. Faqat nom bo'lsa — nomlarni ketma-ket sinash mumkin |
| Foydalanuvchi topilmasa ham argon2 bir marta ishlaydi | Aks holda javob vaqti farqidan qaysi nomlar mavjudligini aniqlab olish mumkin |
| Xato sababi oshkor qilinmaydi | "Nom yo'q" va "parol noto'g'ri" bir xil javob beradi |
| **Parol tiklash yo'q** | Pochta ham, SMS ham yo'q — xavfsiz tiklash oqimini qurishning iloji yo'q. Buning o'rniga Telegram bilan kirgan foydalanuvchi parol qo'yadi, ya'ni **Telegram tiklash yo'li bo'lib qoladi**. Ekranda bu ochiq yozilgan |
| Nomda **kirill harfi taqiqlangan** | `зизу` lotin klaviaturada terilmaydi. Foydalanuvchi keyin "parolim ishlamayapti" deb qolardi. Cheklov klientda, serverda va bazada — uchalasida bir xil |
| Nomni almashtirish yopiq | Nom reytingda, bellashuvda va ota-ona ekranida ko'rinadi |

### 3.11 Prod himoyalari (7 ta)

`ENVIRONMENT=prod` bo'lganda quyidagilardan biri qanoatlanmasa **server
umuman ko'tarilmaydi**:

1. `JWT_SECRET` — ≥32 bayt va standart qiymat emas
2. `OTP_DEBUG_RETURN=false` — aks holda OTP kodi API javobida qaytadi
3. Baza paroli standart emas
4. `CORS_ORIGINS` — `*` emas, aniq domenlar
5. `SMS_PROVIDER` — `console` emas (u faqat log yozadi, SMS yubormaydi)
6. Telegram yoqilgan bo'lsa — token, bot nomi **va webhook siri** bo'lishi shart
7. `ALLOW_CLIENT_AD_REWARDS=false` — aks holda klient o'ziga tanga yozib olardi

Nega "ogohlantirish" emas, "ko'tarilmaydi": ogohlantirish log'da qoladi va
hech kim o'qimaydi. Xavfsiz bo'lmagan konfiguratsiya bilan ishga tushgan
server esa oylab shunday turadi.

---

## 4. API — 46 endpoint

<details>
<summary>To'liq ro'yxat</summary>

**Auth (14)**

```
GET    /v1/auth/methods              qaysi yo'llar ochiq (autentifikatsiyasiz)
POST   /v1/auth/register             nom + parol -> yangi hisob
POST   /v1/auth/login                nom + parol -> token
POST   /v1/auth/password             mavjud hisobga parol qo'shish
GET    /v1/auth/username-free        nom bo'shmi (yozayotganda)
POST   /v1/auth/otp/request          SMS kod so'rash
POST   /v1/auth/otp/verify           kodni tekshirish -> token
POST   /v1/auth/invite               taklif kodi -> token
POST   /v1/auth/telegram/start       nonce + botga havola
POST   /v1/auth/telegram/poll        botda Start bosildimi
POST   /v1/telegram/webhook          Telegram xabarlari
POST   /v1/auth/refresh              token aylantirish
POST   /v1/auth/logout               refresh tokenni bekor qilish
GET/PATCH /v1/auth/me                profil
```

**Kontent (4)**

```
GET  /v1/subjects                          fanlar + shaxsiy statistika
GET  /v1/subjects/{id}/catalog?grade=N      sinflar, bo'limlar, imtihon konteksti
GET  /v1/questions                          savol olish (filtrlar bilan)
POST /v1/submissions                        javob yuborish -> baho + mukofot
```

**O'yin va ijtimoiy (12)**

```
GET  /v1/leaderboard        reyting (umumiy / fan / hudud)
GET  /v1/me                 profil + progress + o'rin
GET  /v1/me/analysis        mavzular bo'yicha kuchli/zaif tomonlar
GET  /v1/coins              balans + tariflar
POST /v1/coins/ad-reward    reklama ko'rgani uchun tanga
GET/POST /v1/challenges                 ro'yxat / yaratish
POST /v1/challenges/join                kod bilan qo'shilish
POST /v1/challenges/{id}/cancel         bekor qilish
GET  /v1/challenges/{id}/questions      muzlatilgan savollar
POST /v1/challenges/{id}/submit         natija
GET  /v1/regions                        hududlar ro'yxati
GET  /v1/announcements                  e'lonlar
```

**Ota-ona (5)**

```
POST /v1/parent/link-code                 farzand kod oladi
POST /v1/parent/link                      ota-ona kodni kiritadi
GET  /v1/parent/children                  farzandlar ro'yxati
GET  /v1/parent/children/{id}             batafsil
GET  /v1/parent/children/{id}/analysis    mavzular tahlili
```

**Daftar, murojaat, admin (11)**

```
GET/POST/PATCH/DELETE /v1/notes           shaxsiy eslatmalar
POST /v1/feedback                         murojaat (Telegram'ga uzatiladi)
GET  /v1/admin/feedback                   murojaatlar ro'yxati
POST /v1/admin/feedback/{id}/seen         ko'rildi
GET  /v1/admin/stats                      umumiy statistika
GET  /v1/admin/analytics                  retention, DAU, konversiya
GET  /health                              tiriklik tekshiruvi
```

</details>

---

## 5. Kontent

### 5.1 Hozirgi bank (2026-08-06, prod API'dan o'lchangan)

| Fan | Aktiv savollar | Bo'limlar |
|---|---:|---:|
| Geografiya | 7 169 | 179 |
| Matematika | 5 453 | 128 |
| O'zbekiston tarixi | 2 415 | 46 |
| Biologiya | 1 540 | 58 |
| Ona tili | 824 | 10 |
| Huquq | 644 | 34 |
| Jahon tarixi | 620 | 24 |
| **Jami** | **18 665** | **479** |

Fizika, Kimyo, Geometriya — ilovada ko'rinadi, lekin **0 savol**. Ular
ataylab "tez orada" holatida: karta xiralashgan va bosilmaydi. Ilgari ular
boshqalar bilan aynan bir xil ko'rinardi va faqat bosilmasdi — sinovchilar
buni buzuq deb hisoblashardi.

**Tur bo'yicha:** `mcq` 13 447 aktiv · `numeric` 2 924 · `open_keyword` 895
aktiv + **4 097 draft** (ko'rib chiqishni kutmoqda).

### 5.2 Savol yuklash quvuri

```
xom JSON  →  normalize  →  clean_data/{fan}_g{sinf}/{core,uz,ru}.json
                                    ↓
                          run_subject.py --dry-run
                                    ↓
                          run_subject.py  →  PostgreSQL
                                    ↓
                          audit_grading.py  →  0 muammo bo'lishi shart
```

Uchta fayl, uchta vazifa:

* `core.json` — **mantiq**: tur, sinf, mavzu, qiyinlik, to'g'ri javob
* `uz.json` — o'zbekcha matn va variantlar
* `ru.json` — ruscha matn, variant `id` lari **aynan bir xil**

`--dry-run` bazaga hech narsa yozmaydi va har yozuvni `OK` / `WARN` /
`SKIP` / `ERROR` deb belgilaydi.

### 5.3 Xavfli javoblar avtomatik `draft` bo'ladi

Ochiq javobli savolda javob `x=3, y=8` shaklida bo'lsa, u **draft** bo'lib
yuklanadi va `tags->>'risky_answer' = 'true'` belgisini oladi.

Sabab: `open_keyword` aynan moslikni talab qiladi va normalizator bo'sh
joyni saqlaydi. Ya'ni bazada `x=3, y=8` tursa, o'quvchining `x=3,y=8`
javobi **noto'g'ri** hisoblanardi — vergul yonidagi bo'sh joy tufayli.
Bunday savollar aslida tanlovli (`mcq`) bo'lishi kerak.

4 097 ta shunday savol ko'rib chiqishni kutmoqda.

### 5.4 LaTeX

Bazada LaTeX shaklida saqlanadi (`$\frac{1}{3}$`), ko'rsatish qatlamida
Unicode'ga o'giriladi (`core/math_text.dart`): `\log`, `\sqrt[n]`,
`\begin{cases}` va h.k. Bu ishlaydi; doimiy yechim — o'girishni yuklash
paytiga ko'chirish.

---

## 6. Dizayn tizimi

### 6.1 Ranglar

| Token | Yorug' | Qorong'i | Qayerda |
|---|---|---|---|
| `primary` | `#F8721C` | `#FF8A3D` | brend apelsin — asosiy harakat |
| `background` | `#F8F9FA` | `#131110` | sahifa foni |
| `surface` | `#FFFFFF` | `#1E1A17` | karta |
| `surfaceAlt` | `#F1F3F5` | `#262019` | ikkilamchi karta |
| `hairline` | `#E7EAEE` | `#312A24` | ajratuvchi chiziq |
| `ink` | `#191C1F` | `#F3EEE7` | asosiy matn |
| `muted` | `#6B7280` | `#A39A8E` | ikkilamchi matn |
| `success` | `#2E9E5B` | `#4FC98A` | to'g'ri javob |
| `warning` | `#C98A00` | `#F5B93C` | ogohlantirish |
| `danger` | `#D8452F` | `#FF6F5A` | xato |
| podium | `gold #E0A106` · `silver #9AA3AC` · `bronze #B4703A` | | reyting TOP-3 |

**Fon o'zgarishi va sababi.** Ilgari fon iliq krem (`#FBF7F2`) edi. Muammo:
iliq fonda **oq karta deyarli ko'rinmasdi** — ikkalasining yorqinligi juda
yaqin edi va interfeys "yassi" tuyulardi. Neytral sovuq fon (`#F8F9FA`)
kartalarni ajratadi va apelsin brend rangini ham kuchaytiradi.

### 6.2 Bo'shliq va burchaklar

8pt shkala: `xs 4` · `sm 8` · `ms 12` · `md 16` · `lg 24` · `xl 32` · `xxl 48`

Burchak radiusi: tugma `14` · karta `18` · varaq `20` · "tabletka" `999`

### 6.3 Harakat

| Nom | Davomiylik | Qayerda |
|---|---|---|
| `fast` | 160 ms | hover, bosish |
| `normal` | 240 ms | karta o'zgarishi |
| `slow` | 320 ms | ekranga kirish |
| `stagger` | 40 ms | ro'yxat elementlari orasidagi kechikish |

Egri chiziqlar: kirish `easeOutCubic`, interaktiv `easeOut`, urg'uli
`easeInOutCubicEmphasized`.

**Kechikish 8-elementdan keyin o'smaydi.** Sabab: pastdagilar baribir
ekrandan tashqarida — kechikishni oshirish faqat kutishni uzaytiradi.

**`prefers-reduced-motion`** landing sahifasida to'liq qo'llab-quvvatlanadi:
harakat butunlay o'chadi, mazmun o'zgarmaydi.

### 6.4 Chuqurlik

| Soya | Shaffoflik | Qachon |
|---|---|---|
| `Shadows.card` | 4% | tinch holat |
| `Shadows.lift` | 12% | hover |
| `Shadows.glow(color)` | 35% rangli | FAB |
| `Shadows.overlay` | — | modal |

Qorong'i temada soyalar **bo'sh** — u yerda chuqurlik sirt rangi bilan
beriladi, qora fonda qora soya ko'rinmaydi.

**Hover:** `−4 px` yuqoriga siljish + kuchli soya + 1.5 px aksent chegara.
`scale` **ataylab ishlatilmaydi** — masshtablash matnni xiralashtiradi.

Ilgari hover soyasi 10% shaffof edi va sinovchilar kartalar
bosiladiganini payqamasdi.

### 6.5 Shrift

**Manrope.** Plus Jakarta Sans ko'rib chiqildi va **rad etildi**: unda
kirill yo'q. Ilova `ru` ni qo'llab-quvvatlaydi va kontentda kirill savollar
bor — ular fallback shriftga tushib butunlay boshqacha ko'rinardi. Manrope
lotin, kirill va ruschani bitta oilada beradi.

Matn masshtabi `0.85`–`1.3` oralig'ida cheklangan: tizim sozlamasida juda
katta shrift qo'yilgan qurilmada tugma matnlari qutidan chiqib ketardi.

### 6.6 Moslashuvchanlik

| Kenglik | Tartib |
|---|---|
| < 600 dp | pastki navigatsiya paneli |
| ≥ 600 dp | chapda `NavigationRail` |
| ≥ 1200 dp | yoyilgan rail (matn bilan) |

Kontent kengligi ekran bo'yicha cheklanadi: quiz 760 · picker 760 ·
dashboard 1100 · natija 460. Cheklovsiz 27 dyuymli monitorda matn qatori
150 belgiga cho'zilardi — o'qib bo'lmaydi.

---

## 7. Ilova ekranlari

### 7.1 Tuzilish

```
HomeShell (lazy IndexedStack)
├── Asosiy      dashboard_screen.dart
├── Reyting     leaderboard_screen.dart
├── Bellashuv   challenges_screen.dart
└── Ota-ona     parent_screen.dart

Ichki: subject_grid → picker → quiz → result
Boshqa: profile, settings, notes, news, child_detail
Kirish: login_sheet → {password, telegram, invite, phone}
```

**`IndexedStack` lazy qilindi:** ilgari ilova ochilishi bilan to'rtala
ekran ham tarmoqqa chiqardi (4 ta keraksiz so'rov) va kirish animatsiyalari
ko'rinmas ekranda tugab qolardi.

### 7.2 Asosiy ekran

* Gorizontal statistika lentasi: XP, daraja (progress bilan), seriya,
  tanga, o'rin. Raqamlar **0 dan sanaladi** (700 ms).
* Bugungi maqsad kartasi
* Fan gridi — har kartada savol soni, aniqlik chizig'i, oxirgi mashq vaqti
* Mehmon uchun "natijangiz saqlanmayapti" bloki

### 7.3 Mashq oqimi

```
Fan tanlash → Sinf → (ixtiyoriy) Bo'lim → Savollar soni → Quiz → Natija
```

**Bo'limlar sinf bo'yicha filtrlanadi** — bu haqiqiy xato edi va tuzatildi.
Ilgari 10-sinf tanlansa ham butun fanning 179 ta bo'limi chiqardi, ularning
ko'pi 10-sinfda umuman yo'q. Endi `?grade=` parametri bor va tekshirildi:
`catalog?grade=10` → 12 ta bo'lim, yig'indisi aynan 1 132 — 10-sinf savollar
soniga teng.

Quizda: mukofot chipi (`+10 XP`), sabab ko'rsatiladi (mehmonsiz / takroriy
savol), tugagach progress provider'lari yangilanadi.

### 7.4 Mukofot shaffofligi

**Muammo:** "Kirgandan keyin XP o'smaydi."

**Haqiqiy sabab ikkita edi:**

1. Klientda mashqdan keyin `meOverviewProvider` **invalidate qilinmasdi** —
   dashboard eski raqamni ko'rsatardi. Backend to'g'ri ishlardi.
2. Mehmon rejimida va **takroriy savolda** XP ataylab berilmaydi (farming
   oldini olish uchun), lekin ilova buni **aytmasdi**.

**Yechim:** server javobiga `xp_awarded`, `coins_awarded`, `reward_reason`
qo'shildi; quiz ekranida yo "+10 XP" chipi, yo sabab ko'rsatiladi.

### 7.5 Ota-ona paneli

**Muammo:** kod to'g'ri kiritilsa ham panel ochilmasdi.

**Sabab:** `/v1/parent/*` `require_role("parent")` talab qilardi. Rol
ro'yxatdan o'tishda qotib qoladi, telefon kirish esa yopiq — oilada bitta
hisob bo'lsa to'g'ri kod ham **403** olardi.

**Yechim:** rol sharti olib tashlandi. Ruxsat endi **guardianship yozuvi**
bilan beriladi — u faqat bola bergan kod orqali yaratiladi, ya'ni rol hech
qachon haqiqiy xavfsizlik chegarasi bo'lmagan.

Panel ko'rsatadi: 7 kunlik javoblar soni, to'g'rilari, aniqlik foizi, faol
kunlar, oxirgi mashq vaqti va mavzular bo'yicha zaif tomonlar. **XP
ko'rsatilmaydi** — ota-ona XP nima ekanini bilmaydi va u savolga javob
bermaydi.

### 7.6 Bellashuv havolasi

Ilgari kod (`WUCYA4`) ulashilardi va kodni olgan odam ilovani topib, kirib,
qo'lda kiritishi kerak edi. Endi `https://topagon.uz/?join=KOD` havolasi +
Telegram ulashish tugmasi. Havolani bosgan odam to'g'ri tabga tushadi va kod
avtomatik qo'yiladi.

### 7.7 Avatar

Bosh harf + 12 rangdan biri. **Rasm yuklash EMAS** — obyekt saqlash,
moderatsiya va CDN kerak bo'lardi, deadline esa 2 kun. Rang tanlanmagan
bo'lsa ism hash'idan barqaror rang olinadi, ya'ni avatar "tasodifiy" emas.

### 7.8 Rus tili

Interfeys ruschaga tarjima qilingan, lekin **savollarda ruscha tarjima
yo'q**. Server mos tarjimani topmasa o'zbekchasini qaytaradi.

Natija eng yomon variant edi: ruscha menyu + o'zbekcha savollar, va
foydalanuvchi ilova buzuq deb o'ylaydi. **Yechim:** yashirin fallback
o'rniga ochiq xabar — "ruscha savollar tayyorlanmoqda" + bir bosishda
o'zbek tiliga qaytish tugmasi.

---

## 8. Reklama sahifasi (landing)

`topagon.uz` uchun alohida statik sahifa: vanilla HTML/CSS/JS + GSAP
ScrollTrigger + Lenis. Framework yo'q.

**Dizayn kontseptsiyasi:** katakli daftar. 24 px to'r ham tekstura, ham
tartib tizimi — ya'ni bezak emas, konstruksiya.

| Token | Qiymat |
|---|---|
| `--ink` | `#0E1116` |
| `--paper` | `#FBFAF6` |
| `--grid` | `#CBD8E6` |
| `--pen` | `#16357F` (ko'k ruchka) |
| `--mark` | `#C1362F` (qizil tekshiruv) |
| `--brand` | `#F8721C` |

Shriftlar: Onest (sarlavha), Manrope (matn), JetBrains Mono (raqamlar).

**Bo'limlar:** hero (javob doiralari canvas'da) → sinf zinasi (pinlangan
scroll) → fanlar tokchasi (gorizontal surish, tezlikka bog'liq qiyshayish) →
bitta savoldan butun bankgacha (canvas maydon) → reyting (FLIP animatsiya).

**Ikki qoida:**

1. **Sotib olingan aktiv yo'q.** Hamma grafika kod bilan chizilgan.
2. **O'ylab topilgan statistika yo'q.** Sahifadagi har bir raqam
   `clean_data/*/core.json` dan hisoblangan. Brifda "22 000" yozilgan edi —
   ishlatilmadi, chunki bazada boshqa raqam turibdi.

`prefers-reduced-motion` da sahifa **to'liq statik** bo'ladi va butun mazmun
ko'rinadi.

---

## 9. Infratuzilma va deploy

### 9.1 Server

Ubuntu 24.04 · 2 yadro · 2 GB RAM · 40 GB NVMe · TAS-IX

```
topagon.uz      → Flutter Web ilovasi (kelajakda landing)
app.topagon.uz  → ilova (domenlar ajratilgandan keyin)
api.topagon.uz  → nginx → 127.0.0.1:8000 → FastAPI konteyneri
```

### 9.2 `deploy.sh`

Bitta skript, to'rt rejim: `backend` · `app` · `landing` · `all`.

Nega skript: buyruqlarni qo'lda ko'chirganda **uch marta** xato bo'ldi —
Windows buyrug'i VPS ichida ishga tushdi, `tar` ildizi noto'g'ri
ko'rsatildi, `--pwa-strategy=none` unutildi. Skript bularni takrorlamaydi va
har qadamdan keyin natijani **tekshiradi**.

Ichiga yozilgan saboqlar:

| Tuzoq | Skript nima qiladi |
|---|---|
| `__pycache__` konteynerga tushardi | arxivdan chiqarib tashlanadi |
| `tar` ildizi allaqachon `web/` | manba `/tmp/web/`, `/tmp/web/web/` emas |
| Service worker eski versiyani keshlaydi | `--pwa-strategy=none` majburiy |
| Eski build sezilmay ketardi | `BUILD_MARKER` yuklashdan **oldin ham, keyin ham** tekshiriladi |
| `migrate.sh` muhitni olmasdi | `.env` skriptning o'zida o'qiladi |
| Migratsiya ko'r-ko'rona ishlardi | avval `--status`, keyin **Enter kutadi** |

### 9.3 Service worker muammosi

**Shikoyat:** "keyin o'zgartish qilsam avtomatik o'zgarmayapti eski
userlarida".

**Sabab:** Flutter Web standart holatda service worker yaratadi. U ilovani
keshlaydi va foydalanuvchi `Ctrl+Shift+R` bossa ham **eski versiyani**
ko'radi.

**Yechim:** `--pwa-strategy=none` + o'zini o'chiradigan service worker
(keshlarni tozalaydi, ro'yxatdan chiqadi, ochiq oynalarni yangilaydi).
Ikkinchisi kerak, chunki eski SW allaqachon brauzerlarda o'rnatilgan.

### 9.4 Zaxira

Har deploy'dan **oldin** avtomatik `pg_dump -Fc`. Migratsiya bazani
buzganda tiklanadigan nusxa bo'lishi shart.

**Tuzoq:** PowerShell `>` ikkilik oqimni buzadi — `pg_dump -Fc > fayl.dump`
natijasi yaroqsiz chiqadi (matn deb ishlanadi). To'g'ri yo'l: konteyner
ichiga `-f` bilan yozib, keyin `docker compose cp`.

### 9.5 Murojaat → Telegram

Foydalanuvchi ilovada murojaat yozadi → bazaga yoziladi → **darhol admin
Telegram'iga yuboriladi** (ism, aloqa, ilova versiyasi, matn). Botga yozilgan
erkin xabarlar ham adminga uzatiladi.

Xavfsizlik detali: `httpx` INFO darajasida so'rovning to'liq URL'ini yozadi,
Telegram Bot API'da esa **token aynan URL yo'lida** turadi. Ya'ni bot tokeni
har xabarda konteyner log'iga tushardi. Log darajasi WARNING ga tushirildi.

---

## 10. Sinovdan chiqqan tuzoqlar

Bular ishlab chiqish paytida haqiqatan boshdan kechirilgan:

| # | Tuzoq | Oqibat |
|---|---|---|
| 1 | Windows'da `localhost` → IPv6 `::1`, Docker esa IPv4'da tinglaydi | ulanish yo'q; `127.0.0.1` ishlatish shart |
| 2 | `docker compose restart` **kodni yangilamaydi** | `up -d --build` kerak |
| 3 | `media` ustunida `jsonb 'null'` turibdi, SQL NULL emas | `media IS NOT NULL` 13 584 qatorni noto'g'ri tanlaydi |
| 4 | `~* 'rasm'` → `rasmiy`, `rasman` ga ham mos keladi | so'z chegarasi kerak |
| 5 | `num.clamp()` ning statik turi `num`, `int` emas | kompilyatsiya xatosi |
| 6 | `NavigationRail`: `extended: true` bo'lsa `labelType` `null` bo'lishi shart | assert |
| 7 | `pubspec.yaml` `assets:` dagi har bir papka **diskda bo'lishi shart** | `pub get` yiqiladi |
| 8 | `INTERNET` ruxsati faqat debug manifestda | release APK tarmoqsiz chiqadi |
| 9 | XML izohida `--` bo'lmasin | "Error parsing AndroidManifest.xml" |
| 10 | Telegram webhook va `getUpdates` **bir vaqtda ishlamaydi** | biri ikkinchisini o'chiradi |
| 11 | Bot foydalanuvchiga birinchi yoza olmaydi | avval u «Start» bosishi kerak |
| 12 | `tg_poll` chegarasi IP bo'yicha edi | NAT ortidagi 3-chi odam 429 olardi → **nonce bo'yicha** qilindi |

---

## 11. Bajarilgan ishlar

### Backend
- [x] Auth: OTP, Telegram, taklif kodi, **nom+parol**
- [x] Tanga iqtisodi v2 (daftar, anti-farm, yopiq halqa)
- [x] Bellashuv (eskrou, muzlatilgan savollar, har yo'lda tanga saqlanadi)
- [x] Reyting (Redis, uch ko'lam)
- [x] Ota-ona paneli (guardianship, ma'noli ko'rsatkichlar)
- [x] Daftar, e'lonlar, analitika, murojaat → Telegram
- [x] Anti-scraping (rate + HyperLogLog hajmi)
- [x] 7 ta prod himoyasi
- [x] **85 test o'tadi**

### Ilova
- [x] Dizayn tizimi (rang, bo'shliq, harakat, chuqurlik, tipografiya)
- [x] Barcha asosiy ekranlar qayta qurildi
- [x] Moslashuvchan tartib (telefon / planshet / desktop)
- [x] Mehmon rejimi + ro'yxatdan o'tishga tashviq
- [x] Mukofot shaffofligi
- [x] Bellashuv havolasi (deep link)
- [x] Avatar
- [x] Rus tili holati ochiq aytiladi
- [x] Flutter logotipi olib tashlandi, `?join=` deep-link
- [x] LaTeX → Unicode

### Kontent
- [x] 18 665 aktiv savol, 7 fan, 479 bo'lim
- [x] `text_open` → `numeric` / `open_keyword` ko'prigi
- [x] Xavfli javoblar avtomatik `draft`
- [x] Yuklash quvuri + `--dry-run` + `audit_grading`

### Infra
- [x] Prod deploy (Docker, nginx, certbot)
- [x] `deploy.sh` — to'rt rejim, tekshiruvlar bilan
- [x] Service worker keshi muammosi hal qilindi
- [x] Har deploy'dan oldin avtomatik zaxira

---

## 12. Qolgan ishlar

| # | Ish | Muhimligi |
|---|---|---|
| 1 | 4 097 ta `open_keyword` draftni ko'rib chiqish (ko'pi `mcq` bo'lishi kerak) | Yuqori |
| 2 | Haqiqiy logotip (hozir vaqtinchalik apelsin «T») | Yuqori |
| 3 | 30 ta sinovchi yig'ish va D1 retention'ni o'lchash | Yuqori |
| 4 | Android release: imzo kaliti + appbundle | O'rta |
| 5 | Play Console: $25, maxfiylik siyosati, data safety | O'rta |
| 6 | Landing `og.png` (1200×630 — Telegram SVG ko'rsatmaydi) | O'rta |
| 7 | Ruscha kontent | O'rta |
| 8 | Bo'lim nomlarini tozalash («104-§ (test qismi, variant 47)») | Past |
| 9 | Fizika, Kimyo, Geometriya banklari | Past |
| 10 | AdMob, mascot animatsiyasi, rasm zanjiri (CDN) | Launch'dan keyin |
| 11 | Eskiz SMS (yuridik shaxs kerak) | Launch'dan keyin |
| 12 | iOS (Mac kerak) | Launch'dan keyin |

---

## 13. Fikr kutilayotgan joylar

Umumiy "yoqdi/yoqmadi" o'rniga quyidagi aniq savollarga javob foydaliroq:

### Mahsulot

1. **Birinchi 60 soniya.** Ilovani ochgan o'quvchi nima qilishini tushunadimi?
   Qayerda ikkilanib qoldingiz?
2. **Ro'yxatdan o'tish.** To'rt yo'ldan qaysi birini tanladingiz va nega?
   Parol yo'li ishonch uyg'otdimi yoki "yana bitta parol" tuyuldimi?
3. **Mukofot.** "+10 XP" chipi va sabab xabari tushunarli edimi? XP nima
   ekanini bilasizmi?
4. **Bellashuv.** Do'stingizga havola yubordingizmi? U ochib ulanaoldimi?
5. **Ota-ona paneli.** Ota-onangizga ko'rsating: u yerdagi raqamlar unga
   biror narsa aytadimi? Nima yetishmaydi?

### Dizayn

6. **Kartalar bosiladiganini payqadingizmi?** (Hover effekti aynan shu
   sababdan kuchaytirildi.)
7. **Animatsiyalar** yordam berdimi yoki sekinlashtirdimi?
8. **Xiralashgan fanlar** (Fizika, Kimyo) — "tez orada" ekani tushunarlimi
   yoki buzuq tuyuldimi?
9. **Matn hajmi va kontrast** — uzoq mashqda ko'z charchadimi?
10. Mobil, planshet va kompyuterda — qaysi birida noqulay?

### Kontent

11. **Noto'g'ri savol topdingizmi?** Aynan qaysi biri (ekranda `id` ko'rinadi).
12. **Javob qabul qilinmadimi?** Siz nima yozdingiz va nima to'g'ri deb
    hisoblandi? (`numeric` uchun bu ayniqsa muhim.)
13. **Bo'lim nomlari** tushunarlimi?

### Texnik

14. **Sekinlik.** Qayerda kutishga to'g'ri keldi? Qanaqa internet edi?
15. **Xatolar.** "Serverga ulanib bo'lmadi" chiqdimi? Qanday harakatdan keyin?
16. **Sessiya.** Ilovani yopib qayta ochsangiz, kirgan holatda qoldingizmi?

---

## 14. Aloqa

| | |
|---|---|
| Telegram bot | `@topagonuzbot` — ilova ichidan "Murojaat" yoki botga to'g'ridan-to'g'ri |
| Ilova | https://topagon.uz |
| API sog'lig'i | https://api.topagon.uz/health |

Murojaatlar to'g'ridan-to'g'ri ishlab chiquvchining Telegram'iga tushadi —
ya'ni javob bo'ladi.

---

*Hujjat 2026-08-06 holatiga ko'ra. Raqamlar prod API'dan va kod bazasidan
o'lchangan, taxmin qilinmagan.*
