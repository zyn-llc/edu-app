# Deploy — 2026-08-06, qadam-baqadam

> Bu faylni **Git Bash**da ochiq turgan holda o'qing. Har qadamda kutilayotgan
> chiqish yozilgan — mos kelmasa to'xtang, keyingi qadamga o'tmang.

## 0. Oldindan tekshiruv (3 daqiqa, deploy'dan OLDIN)

`deploy.sh app` ichida `flutter analyze || die` bor. Oxirgi **to'rt sessiyada
`flutter analyze` bir marta ham ishga tushirilmagan**, ya'ni skript katta
ehtimol shu yerda to'xtaydi — lekin **backend allaqachon yangilangan** bo'ladi.
Shuning uchun analyze'ni alohida, oldin ishga tushiring:

```bash
cd "/d/platform edu/mobile"
flutter pub get      # flutter_animate: ^4.5.0 yangi paket
flutter gen-l10n
flutter analyze
```

**Kutilgan:** `No issues found!`
**Xato chiqsa:** tuzating, keyin qaytaring. `deploy.sh` ni ishga tushirmang.

SSH ishlayotganini ham tekshiring:

```bash
ssh root@189.74.96.41 "echo ok && docker --version"
```

**Kutilgan:** `ok` + docker versiyasi. Parol so'ralsa — kalit qo'yilmagan,
lekin deploy baribir ishlaydi (bir necha marta parol so'raydi).

---

## 1. Backend

```bash
cd "/d/platform edu"
bash deploy.sh backend
```

Qadamlar va kutilgan natija:

| Qadam | Kutilgan chiqish |
|---|---|
| 1/5 kod ko'chirish | `scp` progress, xatosiz |
| 2/5 zaxira | `pre-deploy.dump` va uning hajmi (bir necha MB) |
| 3/5 qayta qurish | docker build loglari, oxirida `Container ..._api Started` |
| 4/5 migratsiya holati | ro'yxat; **faqat `021` va `022` "kutmoqda" bo'lishi kerak** |
| — | `Enter bosing` so'raladi |
| 5/5 tekshiruv | `{"status":"ok","env":"prod"}` va `{"password":true,"telegram":true,...}` |

**⚠️ 4/5 da diqqat.** Agar `022` dan tashqari eski migratsiyalar ham
"kutmoqda" deb chiqsa — **Ctrl+C**. Bu `schema_migrations` jadvali
sinxrondan chiqqanini bildiradi va ko'r-ko'rona ishga tushirish bazani
buzishi mumkin. Menga ro'yxatni yuboring.

**Muvaffaqiyat mezoni:** oxirida `✓ Backend yangilandi` va
`/v1/auth/methods` javob berdi. Hozir u **404** qaytaryapti — shu 404 ning
yo'qolishi butun deploy'ning ma'nosi.

Agar `! TELEGRAM_ADMIN_CHAT_ID` ogohlantirishi chiqsa — murojaatlar sizga
kelmaydi. `@userinfobot` dan id oling va VPS'dagi `.env` ga yozing.

---

## 2. Ilova (Flutter Web)

```bash
bash deploy.sh app
```

| Qadam | Kutilgan |
|---|---|
| 1/4 build | `flutter analyze` toza (0-qadamda tekshirilgan), build 1–3 daqiqa |
| 2/4 marker | `✓ yangi kod build'da bor` |
| 3/4 yuklash | `scp` + `rsync`, xatosiz |
| 4/4 serverda | raqam (0 emas), `✓ Ilova yangilandi` |

Keyin **majburiy**: brauzerda `F12 → Application → Clear site data`, oynani
yoping va qaytadan oching. Eski service worker allaqachon o'rnatilgan —
oddiy `Ctrl+Shift+R` yetmaydi.

Tekshiring: kirish varag'ida **parol** yo'li birinchi turibdimi; quiz
variantlari kulrang emasmi; `catalog?grade=10` da 12 ta bo'lim chiqadimi.

---

## 3. Landing

```bash
bash deploy.sh landing
```

Fayllar `/var/www/topagon-landing` ga tushadi, lekin **nginx hali unga
ulanmagan** — `topagon.uz` hozir ham Flutter ilovasini beradi. Landing'ni
ko'rish uchun `bash deploy.sh split` kerak, u esa `app.topagon.uz` uchun
DNS A-yozuvini talab qiladi.

`split` dan keyin ilovani **qayta quring**, aks holda `?join=KOD` havolasi
reklama sahifasiga olib boradi:

```bash
WEB_BASE_URL=https://app.topagon.uz bash deploy.sh app
```

---

## 4. Deploy'dan keyin — 2 daqiqalik tekshiruv

```bash
curl -s https://api.topagon.uz/health
curl -s https://api.topagon.uz/v1/auth/methods
curl -s "https://api.topagon.uz/v1/subjects" | head -c 300
```

Ilovada: ro'yxatdan o'tish (parol) → mashq → XP chipi → dashboard'da XP
o'sdimi → chiqib, parol bilan qayta kirish.
