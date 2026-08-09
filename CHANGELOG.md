# O'zgarishlar tarixi

Bu fayl — **nima o'zgargani va NEGA**. Hozirgi holat `CLAUDE.md` da,
arxitektura qarorlari `README.md` da.

Sanalar — ish qilingan kun, reliz emas.

---

## 2026-08-09 (kechqurun) — fizika, kimyo va uch ko'rinish muammosi

### Fizika + kimyo: 11 753 savol

Ikkala fan bazada bor edi, lekin bo'sh — kartochkalar «Tez orada» deb turardi.
Kontent aslida bor ekan: `D:\data_subjects\fizika` va `\kimyo`. U yerga
tushmaganining sababi — bu ikki bank normalizatordan o'tmagan va o'z shakli
bilan yotgan edi:

* fayl nomlari izchil emas (`10.json`, `core (1).json`, `8_core.json`);
* fizikada variant identifikatorlari `opt_a`, qolgan 24 ming savolda `a`;
* `kimyo9/core.json` da ikki obyekt orasida vergul yo'q edi — JSON umuman
  ochilmasdi (`diagnose_json.py --fix` bilan tuzatildi, 795/795 mos).

`stage_phys_chem.py` shu farqlarni yopadi va kontentga tegmaydi. Nega yangi
skript, `normalize_all.sh` emas: normalizator o'z chiqishini kirish papkasiga
yozadi va ID prefikslarini qayta ishlaydi (CLAUDE.md tuzoq 9–10), bu yerda
esa savollar allaqachon kanonik shaklga yaqin edi.

**1 093 savol yuklanmadi** — manbada javob kaliti yo'q yoki variantlar
umuman chiqmagan (PDF'dan olishda yo'qolgan). Ular majburan yuklanmadi:
javobsiz savol o'quvchini o'zi javob bera olmaydigan holatga qo'yadi.

**~700 savol `draft` bo'lib tushdi.** Matnida «Rasmda uchta g'isht...» bor,
rasmning o'zi yo'q. Bu ikki bankda `has_image` maydoni umuman yo'q edi,
shuning uchun bayroq matndan aniqlanadi. `rasm` ga so'z chegarasi bilan
tegib bo'lmaydi (o'zbekchada qo'shimcha ergashadi), shuning uchun prefiks
bo'yicha qidirilib `rasmiy`/`rasman` ochiq istisno qilindi; kimyodagi
«davriy jadval» ham istisno — u devordagi plakat, savolga ilova emas.

Prodda tekshirildi: `audit_grading` 35 884 savolda 0 muammo; fizika va kimyo
savoli uchidan-uchiga yuborildi — to'g'ri javobda kalit beriladi, noto'g'risida
berilmaydi.

### Rus tili: jim fallback o'rniga uzr

`to_public` tarjima topmasa `uz-Latn` ga tushadi. Ruscha tanlagan o'quvchi
ruscha menyu va o'zbekcha savollarni ko'rardi — hech qanday izohsiz. Bu eng
yomon variant: ilova buzuq ko'rinadi.

Ogohlantirish vidjeti bor edi, lekin faqat bosh sahifada va sharti klientda
qattiq yozilgan edi (`lang == 'ru'`). Endi:

* `/v1/subjects` `translated_count` qaytaradi — so'ralgan tildagi aktiv
  savollar soni (asosiy tilda qo'shimcha JOIN qilinmaydi);
* ogohlantirish bosh sahifa, fanlar ro'yxati va mashq tanlash ekranida;
* matnga uzr qo'shildi va nima bo'layotgani ochiq yozildi.

Birinchi ruscha savol yuklangan kuni ogohlantirish o'z-o'zidan yo'qoladi.
Aynan shuning uchun shart serverdan keladi: qo'lda o'chiriladigan narsa
o'chirilmay qoladi.

### Keng monitorda kontentning chegarasi yo'q edi

Rail rejimida markaziy ustun 1100 px bilan cheklangan, tashqarisi esa AYNAN
bir xil rangda edi. 27 dyuymli monitorda (2560 px) bu ikki yonda 700 px dan
bo'sh maydon degani — kartochkalar bo'shliqda osilib turardi.

* `WindowSize.extraLarge` da ustun 1440 px;
* ustun ikki yonidan `hairline` chiziq bilan ajratiladi, lekin faqat ekran
  undan keng bo'lganda — tor ekranda ikkita ma'nosiz chiziq qolmasin;
* `test/rail_desktop_test.dart` ga 2560 px qamrovi qo'shildi. Bu kenglikda
  boshqa vidjet daraxti quriladi va qamrovsiz qoldirilsa xato faqat katta
  monitorli foydalanuvchida ko'rinardi.

### Birinchi yuklanish sekinligi

Shikoyat «yangi foydalanuvchilarda sekin» degan edi va aynan shu ajratma
sababni ko'rsatdi: qaytgan foydalanuvchida kesh bor, yangi foydalanuvchi esa
~8 MB CanvasKit wasm va 3.8 MB `main.dart.js` so'raydi — nginx esa ularni
**har so'rovda qaytadan gzip qilardi**. 2 yadroli VPS'da bu bir necha soniya
CPU, va bir vaqtda kirgan bir nechta yangi foydalanuvchi navbatga tushardi.

* `deploy.sh` build'dan keyin `.gz` fayllarni bir marta yaratadi (`-9`);
* nginx'da `gzip_static on` — tayyor faylni beradi, topmasa eski yo'lga
  tushadi, ya'ni bu qadam yiqilsa ham sayt ishlaydi;
* `.symbols` fayllari (4.7 MB) deploydan chiqarildi — brauzer ularni hech
  qachon so'ramaydi;
* `assets/logo.png` 1254×1254 (504 KB) edi va 36 px doira uchun shu holda
  bundle'ga tushardi → 192×192 (9 KB).

### Data auditi

Xom papkalar clean_data bilan MATN bo'yicha solishtirildi (ID bo'yicha emas:
normalizator identifikatorni almashtiradi va ID solishtiruvi 7 767 ta
"yo'qolgan" savol ko'rsatardi — aslida 1 661). Batafsili CLAUDE.md da.

---

## 2026-08-09 — xavfsizlik auditi va uning natijalari

To'liq adversarial audit o'tkazildi (backend, klient, SQL, deploy). Topilgan
20 muammodan eng jiddiylari quyida. Umumiy naqsh: **izoh to'g'ri, kod
noto'g'ri** — ya'ni deyarli har bir xato hujjat va amalning bir-biridan
ajralib ketgan joyida edi.

### Kritik — javob kaliti oshkor bo'lardi

`api/v1/content.py` har bir yuborishda `correct_option_ids` va `explanation`
ni qaytarardi — **noto'g'ri javobda ham**. `services/grading.py` bosh izohi
esa aynan teskarisini yozgan edi.

Natijada "bir marta xato qil → javobni o'qi → qayta yubor" farmi ochiq edi:
jarima 1 noncoin, mukofot 5 noncoin + 10 XP + reyting ballari. Kirgan
foydalanuvchi uchun `/v1/submissions` da **hech qanday chegara yo'q** edi,
ya'ni buni skript bilan avtomatlashtirsa reyting butunlay ma'nosiz bo'lardi.

Xuddi shu yo'l bilan **bellashuv kaliti** ham oldindan o'qib olinardi:
`GET /v1/challenges/{id}/questions` savol id larini beradi, keyin har biri
oddiy mashq sifatida yuboriladi. Garov qo'yilgan har bir bellashuv 100%
yutilardi.

* kalit va izoh endi faqat `if result.is_correct:` ostida;
* kirgan foydalanuvchi uchun 300/soat chegara (mehmonda 120/soat, IP bo'yicha);
* yakunlanmagan bellashuvdagi savol mashqda **409** beradi (`sql/025`);
* `tests/test_submissions.py` — shu uchtasini qulflaydigan 7 test.

### Telegram kirish — bir bosishda hisob o'g'irlash

Nonce'ni kim «Start» bossa, o'shaning hisobi bog'lanardi. Hujumchi o'zi
`start` chaqirib, `t.me/bot?start=<nonce>` havolasini qurbonga yuborardi;
qurbon bosgan zahoti hujumchining `poll` chaqiruvi qurbon hisobiga to'liq
token juftligini olardi.

Endi oqim ikki bosqichli: `start` **tasdiq kodini** ham beradi, bot xuddi
o'sha kodni tugmada ko'rsatadi va faqat tasdiqlangandan keyin hisob
bog'lanadi. `tests/test_telegram_auth.py` eski xatti-harakat qaytmasligini
qo'riqlaydi.

### `/v1/me/analysis` har bir real foydalanuvchida 500 berardi

`services/analysis.py` `TopicTranslation.name` ni so'rardi — ustun `title`.
Xato faqat MA'LUMOT bo'lganda chiqardi (`topic_mastery` bo'sh ro'yxatda erta
qaytadi), `analysis` uchun esa bitta ham test yo'q edi.

Bir qatorlik tuzatishdan tashqari `tests/test_orm_attrs.py` qo'shildi: u AST
bo'ylab yurib, modelda mavjud bo'lmagan har qanday atribut havolasini tutadi.
Bu klass xato boshqa qaytmaydi.

### Boshqa tuzatishlar

| Nima | Sabab |
|---|---|
| `/v1/me` `username` ni qaytaradi | Klient profilni shu endpointdan o'qiydi. `username` yo'qligi tufayli parol bilan ro'yxatdan o'tgan har bir foydalanuvchi "parol o'rnatilmagan" ni ko'rardi va tugmani bosganda 409 olardi |
| OTP uchun IP chegarasi **yozildi** | `OTP_IP_HOURLY_CAP` to'rtta faylda e'lon qilingan, kodda esa umuman o'qilmagan edi. Eskiz yoqilganda bu to'g'ridan-to'g'ri pul |
| Rate limit auth yo'llarida `fail_closed` | Redis uzilishi parolni cheksiz taxmin qilishga yo'l ochardi |
| `uq_coin_challenge_settle` (`sql/026`) | Muddati o'tgan bellashuv qaytarimi lock'siz o'qish yo'lidan yozilardi — parallel `GET` bilan noncoin ko'paytirish mumkin edi |
| `coin_sign_ck` (`sql/026`) | Bitta noto'g'ri chaqiruv (`credit` o'rniga `spend`) iqtisodiyotni jimgina ag'darardi |
| `apply_wrong_penalty` da advisory lock | Balans −1 ga tushib, "0 dan pastga tushmaydi" qoidasini buzardi |
| Parol almashtirilganda sessiyalar bekor | Tokenini o'g'irlatgan odam hujumchini quva olmasdi |
| Admin: `compare_digest`, har xatoda 404, 20/soat | `!=` javob vaqti orqali kalitni oshkor qiladi; 403 esa kalit sozlanganini tasdiqlaydi |
| nginx `/v1/admin/` uchun IP cheklovi ochildi | Ikkala qator ham izohda turardi |
| `PATCH /me` da `locale` oq ro'yxati, `limit` da `ge=1` | Ikkalasi ham 500 berardi |
| Buzuq `grading_spec` mashqni o'ldirmaydi | `challenges.py` allaqachon to'g'ri qilardi, `content.py` yo'q — assimetriya |
| `/v1/parent/link` da chegara | Butun kodda cheklovsiz qolgan yagona kod-kiritish yo'li edi |

### UX

* Xom `DioException` o'rniga `EmptyState` + `humanError` (429 uchun alohida
  matn). Ilgari o'quvchi ekranda `DioException [connection error]: http://...`
  ni ko'rardi.
* Noto'g'ri javobda endi `quizWrongHint` chiqadi — kalit yo'qligi sababsiz
  bo'shliq bo'lib qolmasin.
* Mehmon banki 1/16 → 3/16: tor bo'limda savollar takrorlanib, "bank kichik"
  degan taassurot qoldirardi.
* Kirish varag'i: bitta asosiy tugma + «Boshqa usullar». To'rtta teng variant
  eng ko'p odam yo'qotadigan nuqtada tanlov falajini berardi.

### Infratuzilma

* `scripts/backup.sh` endi `BACKUP_REMOTE` ga ko'chiradi va yuklash
  muvaffaqiyatsiz bo'lsa xato kodi bilan tugaydi. Ilgari zaxira **faqat
  o'sha VPS'da** turardi.
* Redis `maxmemory 256mb` — `noeviction` chegarasiz xavfli edi.
* `Dockerfile`: non-root, `HEALTHCHECK`, 2 worker, `--proxy-headers`.
* `nginx-app.conf` ga CSP.
* `deploy.sh` da `WEB_BASE_URL` standarti `topagon.uz` (reklama sahifasi)
  edi — har bir bellashuv havolasi noto'g'ri manzilga borardi. Endi
  `app.topagon.uz`.
* `API_BASE_URL` berilmagan release build endi jim ravishda `127.0.0.1` ga
  qaramaydi, balki aniq xato bilan yiqiladi.

### Retention

Telegram xabarlari qo'shildi (`app/services/notify.py`, `sql/028`): bellashuv
chaqiruvi, natija, tugayotgan muddat va uziladigan seriya. Ilgari platformada
qaytishga UNDAYDIGAN hech narsa yo'q edi — do'sti chorlaganini o'quvchi faqat
ilovani o'zi ochsa bilardi.

Chegaralar: kuniga 2 ta, bir xil xabar bir marta (birlamchi kalit bilan),
sozlamalarda o'chirish tugmasi.

### Tozalash

* O'lik sxema o'chirildi (`sql/027`): `competitions`, `transactions`,
  `friendships`, `badges`, `user_badges`, `submissions.competition_id`.
  Bo'sh jadval zararsizdek tuyuladi, lekin u yolg'on hujjat.
* Ishlatilmaydigan kod: `progress.record_submission`, `coins.spend(earned_only)`,
  faqat `NotImplementedError` ko'taradigan `open_text` graderi.
* Repodan: bir martalik psql chiqishlari, bo'sh fayllar, eski IDE fayli,
  AI prompt fayllari.
* Testlar 67 → **104** (`fakeredis` va `httpx` o'rnatilgandan keyin OTP,
  ranking va SMS testlari ham ishlaydi).

---

## 2026-08-08 — sahifa ritmi + footer

Tashqi ko'rikda: "AI-generated ko'rinadi, sahifalar to'satdan tugaydi".
Sabab dizayn emas edi — ekranda **o'zgaradigan ma'lumot yo'q** edi. Har bir
blok bir xil grammatikada (ikonka → sarlavha → kulrang izoh → tugma) va hech
biri foydalanuvchining bugungi holatini bilmasdi.

* `progress` javobiga bugungi/haftalik kesim qo'shildi (`answered_today`,
  `xp_today`, `week[7]`). Migratsiya kerak emas — hammasi `submissions` dan.
* Kun chegarasi UTC emas, **UTC+5**: UTC'da 00:00–05:00 da yechilgan savol
  kechagi kunga tushardi va seriya buzilardi.
* `xp_today` `DISTINCT ON (question_id)` bilan — XP faqat birinchi to'g'ri
  javobda beriladi, oddiy `count(*)` raqamni shishirardi.
* `AppFooter`, `DailyGoalCard`, `WeekStrip`, `ContinueCard`.

**Ijtimoiy blok ("Hozir N o'quvchi faol") ATAYLAB qilinmadi**: platformada
bir necha sinovchi bor, bunday blok yo bo'sh turadi, yo raqamni
bo'rttirishga majbur qiladi. Bo'sh joy soxta raqamdan yaxshiroq.

---

## 2026-08-07 — dizayn + valyuta nomi

* «tanga» → **noncoin** (faqat UI va l10n; serverda maydon `coins` bo'lib
  qoldi, migratsiya kerak emas).
* Animatsiyali fan ikonkalari, `NonCoinIcon`, `XpIcon`, `RewardFly`.
* Lottie/Rive EMAS, Flutter kodi: fayllar 10–40 KB, web'da runtime kerak,
  aylanish/tebranish esa `Transform` bilan ancha arzon.
* `MediaQuery.maybeDisableAnimationsOf` har animatsiyada — OS darajasidagi
  "Reduce motion" vestibulyar sezgirlik uchun majburiy.

---

## 2026-08-06 — parol bilan kirish, ota-ona paneli, Telegram

* **Parol yo'li qo'shildi** (`sql/022`). Sabab: uchala mavjud yo'l ham
  QAYTIB kirishga yaramasdi — telefon+OTP prodda o'chirilgan, taklif kodi bir
  martalik, Telegram esa har safar brauzerdan chiqishni talab qilardi.
  Foydalanuvchi buni har safar yangi ro'yxatdan o'tish deb qabul qilardi.
* Parol 6+ belgi, murakkablik talab qilinmaydi: foydalanuvchi — maktab
  o'quvchisi. Kuch parolga emas, **urinishlar soniga** qo'yilgan.
* Parol tiklash yo'q (pochta ham, SMS ham yo'q) — Telegram tiklash yo'li
  bo'lib xizmat qiladi.
* **Ota-ona paneli rol talabidan xalos qilindi.** `require_role("parent")`
  butun funksiyani ishlamas qilgan edi: rol ro'yxatdan o'tishda qotib qoladi,
  oilada bitta hisob bo'ladi → to'g'ri kod ham 403 olardi. Haqiqiy chegara
  rol emas, **guardianship yozuvi** — u faqat bola bergan kod bilan
  yaratiladi.
* `GET /v1/auth/methods` — klient qaysi yo'l ochiqligini oldindan biladi.
  Ilgari kirish ekrani prodda ishlamaydigan telefon yo'lini birinchi qilib
  ko'rsatardi; ro'yxatdan o'tishdagi eng katta yo'qotish shu yerda edi.
* `core/names.py` — ism reytingda, bellashuvda va ota-ona ekranida boshqalarga
  ko'rinadi. Sinovda `火` ismli hisob uzunlik tekshiruvidan o'tib ketgan edi.
* Telegram `tg_poll` chegarasi IP'dan **nonce**'ga o'tkazildi: NAT ortidagi
  maktab Wi-Fi'sida ikkitadan ko'p odam bo'lsa uchinchisi 429 olardi.

---

## 2026-08-04 — kontent kengaytirildi

`clean_data/` da 7 970 ta `text_open` savol yotgan edi, lekin
`run_subject.py` da `LOADABLE_TYPES = {"mcq"}` turgani uchun ular hech qachon
yuklanmagan. Ko'prik qo'shildi: javob bitta songa yechilsa → `numeric`, aks
holda → `open_keyword`.

Javobda bo'sh joy/vergul/`=` bo'lsa `risky_answer` belgisi bilan **draft**
yuklanadi: `open_keyword` aynan moslik talab qiladi, ya'ni "x=3, y=8"
saqlansa o'quvchining "x=3,y=8" javobi noto'g'ri chiqardi.

Natija: `mcq` 13 447 · `numeric` 2 924 · `open_keyword` 895 aktiv.

---

## Undan oldin

Phase 1: auth+OTP, coin economy, friend challenge, leaderboard, feedback,
admin stats. Batafsil tarix `docs/` papkasida.
