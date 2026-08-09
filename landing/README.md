# Topag'on — landing

Statik sahifa. Build qadami yo'q: papkani nginx'ga qo'yasiz va tugadi.

```
landing/
  index.html
  styles.css
  main.js
  content.js
  assets/
    favicon.svg
    og.svg
  README.md
```

```nginx
server {
    server_name topagon.uz;
    root /var/www/topagon-landing;
    index index.html;
    location / { try_files $uri $uri/ =404; }
}
```

Tashqi bog'liqliklar CDN'dan keladi: GSAP 3.12.5 + ScrollTrigger, Lenis 1.1.13,
Google Fonts (Onest, Manrope, JetBrains Mono). Ular yuklanmasa sahifa baribir
to'liq o'qiladi — quyidagi "Nima uchun bunday" bo'limiga qarang.

---

## Token rejasi

### Ranglar — 6 ta

| Token | Qiymat | Qayerda |
|---|---|---|
| `--ink` | `#0E1116` | qorong'i yer: hero, bank bo'limi, futer |
| `--paper` | `#FBFAF6` | yorug' yer: zina, fanlar, reyting |
| `--grid` | `#CBD8E6` | katak chiziqlari, hairline, ajratgichlar |
| `--pen` | `#16357F` | sharikli ruchka ko'ki: chiplar, zina, raqam yorliqlari |
| `--mark` | `#C1362F` | o'qituvchining qizil qalami — **faqat belgi** |
| `--brand` | `#F8721C` | ilova brendi — **faqat CTA** |

**Nega bular.** Yo'nalish ilovaning o'z dunyosidan olingan: katak daftar,
sharikli ruchka, o'qituvchining qizil qalami, DTM javob varag'i. Umumiy edtech
gradient-siyohrang emas, krem + serif + terrakota ham emas.

`--mark` va `--brand` hech qachon yonma-yon turmaydi: qizil faqat `--paper`
ustida (belgi, to'g'ri javob), apelsin faqat tugmada. Shu ajratish tufayli
ikkalasi bir-birini xiralashtirmaydi.

`--brand` — yettinchi g'oya emas, ilovadan **meros**. Uni olib tashlasak sayt
va ilova ikki xil kompaniyanikiday ko'rinardi.

Qolgan uchta qiymat (`--chalk`, `--ink-soft`, `--paper-soft`) — yangi rang emas,
yuqoridagilardan olingan matn ottenkalari.

### Shriftlar — 3 ta

| Rol | Shrift | Nega |
|---|---|---|
| Display | **Onest 800** | Lotin + **kirill**, 900 gacha vazn, katta o'lchamda tiniq |
| Body | **Manrope 400/600** | ilovada allaqachon ishlatiladi — davomiylik |
| Raqam/utility | **JetBrains Mono 400/700** | `tabular-nums`: sanaladigan raqam sakramaydi |

**Plus Jakarta Sans olinmadi** — unda kirill yo'q. Ruscha versiya rejalashtirilgan
va kontentda kirill savollar bor; ular fallback shriftga tushib butunlay boshqacha
ko'rinardi.

### Tartib — «katak daftar»

Butun sahifa — bitta katak varaq. 24 px qadamdagi CSS gradient kataklarni
chizadi va **shu qadam ayni paytda layout tizimi**: chetki paddinglar, kartalar
orasi, bo'limlar oralig'i — hammasi 24 ning karrasi. Qorong'i bo'limlarda xuddi
shu katak `--pen` rangida 18% shaffoflik bilan chiziladi — doska effekti.

Matn bloklari qattiq `--paper` ustida turadi va katakni to'sadi, ya'ni tekstura
o'qishga xalaqit bermaydi.

### Imzo elementi — o'zi chiziladigan qizil belgi

Bitta SVG `clip-path` — o'qituvchining ✓ belgisi. U hero brendida, zinaning
har bosqichida va savol kartasidagi to'g'ri javobda chiqadi. `--mark` qizili
**sahifada boshqa hech qayerda yo'q** — aynan shu kamdan-kamlik uni bezakdan
imzoga aylantiradi.

---

## Bo'limlar va ScrollTrigger'lar

Har bir trigger `main.js` da `ScrollTrigger #N` deb izohlangan.

| # | Bo'lim | Nima boshqaradi |
|---|---|---|
| — | Hero | Scroll'siz: yuklanishda niqob ostidan qator-qator ochilish (stagger 80 ms). Orqada canvas javob doiralari |
| 1 | Sinf zinasi | **Bitta** pinlangan timeline (`scrub: 1`, `+=300%`): marker zina bo'ylab ko'tariladi, bosqich kartalari crossfade + 8 px, raqam sanaladi |
| 1a | Sinf zinasi (mobil) | Pin yo'q — har bosqich `once: true` bilan chiqadi |
| 2 | Fanlar tokchasi | Pin + gorizontal surish; `ScrollTrigger.getVelocity()` dan qiyshayish, **±6° ga qisilgan**, to'xtaganda 0 |
| 2a | Fanlar (mobil) | Pin yo'q — barmoq bilan suriladi (`scroll-snap`), kartalar ketma-ket chiqadi |
| 3 | Bitta savoldan bankgacha | Pin (`+=260%`): karta 1 → 0.13 ga kichrayadi, canvas maydonida to'rtburchaklar markazdan ko'payadi, oxirida sarlavha |
| 3a | Bank (mobil) | Pin yo'q, canvas o'chirilgan — sarlavha oddiy kirish bilan |
| 4 | Reyting | FLIP: qatorlar jismonan o'rin almashadi. `once: true` — **tsikl yo'q** |

### Nega yettita emas, bitta timeline

Yettita mustaqil trigger — yettita mustaqil progress. Chegaralarda ular
bir-biriga urishadi va marker sakraydi. Bitta `scrub` esa bitta uzluksiz
progress beradi.

### Nega canvas, DOM emas

4-bo'limda 22 000 ta to'rtburchak kerak. Shuncha DOM tugun brauzerni o'ldiradi.
Bitta canvas va progress o'zgarganda bitta qayta chizish — arzon.

### Nega Three.js yo'q

Brief bitta bo'limga ruxsat bergan edi, lekin oltita bo'limning birortasi ham
uni talab qilmaydi: hero va bank — canvas 2D, zina — SVG, reyting — DOM
ustida FLIP. Bu ~150 KB gzip tejaydi va JS byudjetini bemalol qiladi.

---

## Nima uchun bunday: JS'siz va reduced-motion

Asosiy qoida — **har bir animatsiyaning yakuniy holati CSS standarti**.
Boshlang'ich ("from") holatlar faqat `html.js-motion` selektori ostida yozilgan,
bu klassni esa `main.js` faqat quyidagi ikkala shart bajarilgandagina qo'yadi:

* `prefers-reduced-motion: reduce` **emas**;
* GSAP va ScrollTrigger yuklangan.

Ya'ni CDN tushib qolsa, JS o'chirilgan bo'lsa yoki foydalanuvchi harakatni
kamaytirgan bo'lsa — sahifa hech narsani yashirmaydi. Qo'shimcha himoya
sifatida `@media (prefers-reduced-motion: reduce)` bloki `.js-motion`
qoidalarini bekor qiladi va canvaslarni butunlay o'chiradi.

Matn `index.html` da ham, `content.js` da ham bor. HTML — JS'siz o'qish uchun;
`content.js` — tarjima uchun yagona manba. JS yuklanganda matnni `content.js`
dan qayta yozadi, demak **ruscha versiya uchun faqat bitta fayl almashadi**.

### Fokus va pin

Pinlanadigan uchala bo'limda (zina, tokcha, bank) **birorta ham fokuslanadigan
element yo'q** — havola ham, tugma ham. Bu ataylab: pinlangan bo'limga tab bilan
kirilsa, brauzer elementga scroll qilishga urinadi va pin bilan urishadi.
Interaktiv narsalar faqat pinlanmagan joylarda: hero CTA, futer havolalari,
`skip` havolasi.

---

## Raqamlar qayerdan

Hech bir raqam o'ylab topilmagan. Ikkita manba bor va ikkalasi ham sahifada
ochiq aytiladi:

| Raqam | Qiymat | Manba |
|---|---|---|
| Bank hajmi | **23 484** | `D:\data_subjects\clean_data\*\core.json` yozuvlari (2026-08-06) |
| Ilovada ochiq | **17 266** | Postgres `questions` `status='active'` (CLAUDE.md §3) |
| Sinf bo'yicha (7 ta) | 1 832 … 2 865 | shu sinf papkalaridagi `core.json` yig'indisi |
| Fan bo'yicha (7 ta) | 620 … 9 942 | shu fan papkalaridagi `core.json` yig'indisi |
| Sinf oraliqlari | 5–11, 5–10, … | papka nomlaridagi haqiqiy sinflar |
| 4-bo'limdagi savol | `geo_g7_q0005` | `clean_data/geo_g7/{core,uz}.json`, to'g'ri javob `b` |

**Brief'da 22 000 deyilgan edi — u qo'llanilmadi.** Bazada bunday raqam yo'q.
O'rniga ikkita haqiqiy raqam ishlatildi: bank 23 484, ochiq 17 266. Ular
bir-biriga zid emas va farqi sahifada tushuntirilgan
(«Qolgani ko'rib chiqilmoqda»).

Raqamlarni yangilash — `content.js` dagi `numbers`, `ladder.rungs[].count`,
`shelf.subjects[].count`. Jonli bazadan olish uchun:

```sql
SELECT s.code, q.grade, count(*)
FROM questions q JOIN subjects s ON s.id = q.subject_id
WHERE q.status = 'active'
GROUP BY 1, 2 ORDER BY 1, 2;
```

---

## Qolgan [TODO] qiymatlar

Sahifada `[TODO]` matni **yo'q** — hamma raqam haqiqiy. Lekin uchta narsa
tashqaridan kelishi kerak:

1. **`[TODO: Play Store havolasi]`** — `content.js` → `footer.downloadHref`
   hozir `#`. Ilova Play Console'ga chiqqach haqiqiy manzil qo'yiladi.
   `main.js` uni `#` bo'lmaganda avtomatik o'rnatadi.
2. **`[TODO: rasmiy Google Play badge]`** — hozirgi belgi o'zimiz chizganimiz.
   Google o'z badge'ini brend qoidalari bilan beradi
   (`play.google.com/intl/en_us/badges/`) — chop etishdan oldin almashtiring.
   App Store belgisi ataylab qo'yilmagan: iOS versiyasi yo'q.
3. **`[TODO: og.png]`** — `assets/og.svg` tayyor, lekin Telegram va Facebook
   SVG'ni ko'rsatmaydi. 1200×630 PNG ga eksport qiling:
   `assets/og.png`. `index.html` dagi `og:image` allaqachon shunga ishora qiladi.

Ixtiyoriy: `footer.contactHref` hozir shaxsiy pochta — jamoa manzili paydo
bo'lsa almashtiring.

---

## Qabul mezonlari — tekshiruv natijasi

Sandboxda brauzer yo'q (Chrome/Chromium o'rnatilmadi), shuning uchun quyida
**nimani qanday tekshirganim** aniq yozilgan. «O'lchandi» — avtomatik test
o'tkazilgan; «kod bo'yicha» — kodni o'qib tasdiqlangan, brauzerda ko'rilmagan.

| Mezon | Natija | Qanday |
|---|---|---|
| JS o'chirilganda sahifa to'liq o'qiladi | **PASS** | O'lchandi: jsdom bilan oltala bo'limdagi matn markup'da ekani va 7+7+5 element borligi tasdiqlandi |
| `prefers-reduced-motion` — statik sahifa, pin yo'q | **PASS (kod bo'yicha)** | CSS'da bekor qiluvchi media-blok bor; JS `if (!motion) return` bilan pin yaratishdan oldin chiqadi. **Brauzerda ko'rilmagan** |
| 360 / 768 / 1440 px da gorizontal toshish yo'q | **TEKSHIRILMAGAN** | Faqat statik audit: 320 px dan katta yagona qattiq o'lcham — `.js-ladder .rungs` ning `min-height` i (vertikal). Yagona keng element `.shelf__track` `overflow-x: auto` ichida. **Haqiqiy o'lchov brauzer talab qiladi** |
| Har bir interaktiv elementda fokus ko'rinadi; pin tab tartibini ushlab qolmaydi | **PASS** | O'lchandi: `:focus-visible` outline mavjud; pinlanadigan uchala bo'limda fokuslanadigan element **0 ta** |
| Layout xususiyatlari animatsiya qilinmaydi | **PASS** | O'lchandi: barcha `gsap.to/fromTo/set/quickTo` chaqiruvlari skanerlandi — faqat `x`, `y`, `scale`, `skewX`, `opacity` |
| Barcha matn o'zbekcha, o'ylab topilgan raqam yo'q | **PASS** | O'lchandi: markup'da `[TODO]` yo'q, undov belgisi yo'q; har bir raqam yuqoridagi jadvalda manbasi bilan |

### Siz brauzerda tekshirishingiz kerak

1. 360, 768, 1440 px — gorizontal scroll paydo bo'lmasligi.
2. Zina pinlanganda marker va kartalar mos kelishi (shrift kech yuklansa
   `ScrollTrigger.refresh()` chaqiriladi, lekin ko'z bilan ko'rish kerak).
3. Samsung A54 yoki shunga o'xshash qurilmada scroll silliqligi — mobil pin
   o'chirilgan, lekin canvas hero baribir ishlaydi.
4. `chrome://settings` → harakatni kamaytirish yoqilganda sahifa statik qolishi.

```bash
# lokal ko'rish
cd landing && python -m http.server 5173
```
