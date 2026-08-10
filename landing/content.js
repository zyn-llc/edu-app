/* =========================================================================
   content.js — sahifadagi BARCHA matn va raqamlar.
   =========================================================================
   Ruscha versiya kerak bo'lganda: shu faylni `content.ru.js` qilib nusxalab,
   qiymatlarni tarjima qiling va `index.html` dagi <script> manzilini
   almashtiring. Markup'ga tegish SHART EMAS — `main.js` matnni shu obyektdan
   `data-i18n` atributlari bo'yicha joylashtiradi... EMAS.

   MUHIM QAROR: matn HTML ichida ham YOZILGAN, bu obyekt esa yagona manba
   sifatida saqlanadi. Nega ikkalasi:
     * JS o'chirilgan brauzerda sahifa TO'LIQ o'qilishi kerak (talab), ya'ni
       matn markup'da bo'lishi shart;
     * lekin tarjimon uchun 40 ta faylni emas, bitta ro'yxatni ochish qulay.
   `main.js` yuklanganda matnni shu obyektdan qayta yozadi — demak tarjima
   qilinganda faqat shu fayl o'zgaradi, HTML esa zaxira nusxa bo'lib qoladi.

   RAQAMLAR HAQIDA. Hech bir raqam o'ylab topilmagan. Manbalar:
     * `bank.*`  — tayyorlangan banklardagi <papka>/core.json fayllaridagi
                   yozuvlar soni (2026-08-06 holatiga).
     * `active`  — Postgres `questions` jadvalidagi status='active' yozuvlar
                   Bu ilovada HOZIR ochiq savollar soni.
   Ikkalasi ham sahifada aytiladi va bir-biriga zid emas: bank kattaroq,
   chunki uning bir qismi hali ko'rib chiqilmoqda.
   ========================================================================= */

window.CONTENT = {
  meta: {
    title: "Topag'on — 5-sinfdan 11-sinfgacha savollar banki",
    description:
      "O'zbekiston maktab dasturi bo'yicha 23 000 dan ortiq savol. " +
      "Mashq qiling, do'stingiz bilan bellashing, natijangizni kuzating.",
    lang: 'uz',
  },

  /* Sahifada bir necha joyda takrorlanadigan raqamlar. */
  numbers: {
    bankTotal: 23484,   // clean_data/*/core.json — jami yozuv
    activeTotal: 17266, // questions.status='active' — ilovada ochiq
    gradeFrom: 5,
    gradeTo: 11,
  },

  nav: {
    brand: "Topag'on",
    skip: 'Asosiy qismga o‘tish',
  },

  /* ---------------------------------------------------------------- 1 */
  hero: {
    /* Har element — alohida qator. Niqob bilan ochilish shu bo'linishga
       tayanadi, shuning uchun qatorlarni bu yerdan boshqarasiz. */
    headline: ['HAR BIR SAVOL —', 'BIR QADAM', 'OLDINGA'],
    sub: '5-sinfdan 11-sinfgacha. 23 000 dan ortiq savol. Bitta yo‘l.',

    /* ASOSIY TUGMA.
       Play Store'da ilova hali yo'q, shuning uchun "yuklab olish" degan
       tugma hech qayerga olib bormaydi — bu yolg'on bo'lardi. Hozircha
       tugma brauzerdagi ilovaga olib boradi.
       Play listing chiqqach: cta → 'Ilovani yuklab olish',
       ctaHref → footer.downloadHref bilan bir xil. */
    cta: 'Ilovani ochish',
    ctaHref: 'https://app.topagon.uz',

    /* Soxta hisoblagich emas — tekshirib bo'ladigan gap. */
    proof: 'Brauzerda ishlaydi. Ro‘yxatdan o‘tmasdan ham sinab ko‘rasiz.',
    scrollHint: 'Pastga',
  },

  /* ---------------------------------------------------------------- 2 */
  ladder: {
    eyebrow: 'Sinf zinasi',
    title: 'Besh yildan o‘n bir yilgacha',
    lead:
      'Har sinfda o‘z fanlaringiz va o‘z savollaringiz bor. ' +
      'Zinadan yuqoriga chiqqan sari bank kengayadi.',
    counterLabel: 'shu sinf uchun tayyorlangan savol',

    /* count — shu sinf papkalaridagi core.json yozuvlari yig'indisi.
       5:  bio_g5 134 + geo_g5 699 + math_g5 999
       6:  bio_g6 806 + geo_g6 1537 + hist_g6 662 + math_g6 1163
       7:  geo_g7 1399 + hist_g7 524 + math_g7 2559
       8:  bio_g8 227 + geo_g8 1152 + law_g8 325 + math_g8 976
       9:  bio_g9 491 + geo_g9 1378 + law_g9 290 + math_g9 1514
       10: geo_g10 1200 + math_g10 1720
       11: hist_g11 1234 + math_g11 1011 + wh_g11 620            */
    rungs: [
      {
        grade: 5,
        count: 1832,
        subjects: ['Matematika', 'Geografiya', 'Biologiya'],
        line: 'Boshlanish. Uch fandan birinchi bank tayyor.',
      },
      {
        grade: 6,
        count: 4168,
        subjects: ['Matematika', 'Geografiya', 'Biologiya', 'O‘zbekiston tarixi'],
        line: 'Tarix qo‘shiladi. Endi to‘rt fandan mashq qilasiz.',
      },
      {
        grade: 7,
        count: 4482,
        subjects: ['Matematika', 'Geografiya', 'O‘zbekiston tarixi'],
        line: 'Eng katta bank shu yerda — matematikadan 2 559 savol.',
      },
      {
        grade: 8,
        count: 2680,
        subjects: ['Matematika', 'Geografiya', 'Biologiya', 'Huquq'],
        line: 'Huquq boshlanadi. Fizika va kimyo tayyorlanmoqda.',
      },
      {
        grade: 9,
        count: 3673,
        subjects: ['Matematika', 'Geografiya', 'Biologiya', 'Huquq'],
        line: 'To‘qqizinchi sinf — bitiruv. Hamma fandan takrorlash.',
      },
      {
        grade: 10,
        count: 2920,
        subjects: ['Matematika', 'Geografiya'],
        line: 'Geografiya va matematika chuqurlashadi.',
      },
      {
        grade: 11,
        count: 2865,
        subjects: ['Matematika', 'O‘zbekiston tarixi', 'Jahon tarixi'],
        line: 'Jahon tarixi qo‘shiladi. Savollar DTM formatiga yaqin.',
      },
    ],
  },

  /* ---------------------------------------------------------------- 3 */
  shelf: {
    eyebrow: 'Fanlar',
    title: 'Yetti fan, yetti bank',
    lead: 'Har fan alohida yig‘ilgan va alohida tekshirilgan.',
    countLabel: 'savol',
    /* count — fan papkalaridagi core.json yozuvlari yig'indisi.
       gradeRange — papka nomlaridagi sinflardan olingan haqiqiy oraliq. */
    subjects: [
      { name: 'Matematika',         gradeRange: '5–11-sinf',      count: 9942 },
      { name: 'Geografiya',         gradeRange: '5–10-sinf',      count: 7365 },
      { name: 'O‘zbekiston tarixi', gradeRange: '6–11-sinf',      count: 2420 },
      { name: 'Biologiya',          gradeRange: '5–9-sinf',       count: 1658 },
      { name: 'Ona tili',           gradeRange: 'Barcha sinflar', count: 834  },
      { name: 'Huquq',              gradeRange: '8–9-sinf',       count: 645  },
      { name: 'Jahon tarixi',       gradeRange: '11-sinf',        count: 620  },
    ],
    /* Rostini aytadigan qator — tayyor bo'lmagan fanlarni yashirmaymiz. */
    note: 'Fizika va kimyo banklari yig‘ilmoqda. Tayyor bo‘lgach qo‘shiladi.',
  },

  /* ---------------------------------------------------------------- 4 */
  zoom: {
    /* Haqiqiy savol: clean_data/geo_g7/core.json + uz.json, id geo_g7_q0005.
       To'g'ri javob — `b` (Qoraqum). */
    question: {
      id: 'geo_g7_q0005',
      subject: 'Geografiya',
      grade: '7-sinf',
      text: 'O‘rta Osiyodagi eng issiq harorat qayerda kuzatilgan?',
      options: [
        { key: 'a', text: 'Termiz' },
        { key: 'b', text: 'Qoraqum' },
        { key: 'c', text: 'Qizilqum' },
        { key: 'd', text: 'Shimoliy Afg‘oniston' },
      ],
      correct: 'b',
    },
    timerNote: 'Har savolga 30 soniya',
    headline: '23 484 ta savol. Har biri tekshirilgan.',
    sub:
      'Shundan 17 266 tasi hozir ilovada ochiq. ' +
      'Qolgani ko‘rib chiqilmoqda va tayyor bo‘lgach qo‘shiladi.',
  },

  /* ---------------------------------------------------------------- 5 */
  board: {
    eyebrow: 'Bellashuv',
    title: 'Haftalik reyting',
    lead:
      'To‘g‘ri javob XP beradi, XP esa o‘rin. ' +
      'Do‘stingizga havola yuborib, bevosita bellashishingiz ham mumkin.',
    /* Namuna — ismlar o'ylab topilgan va sahifada shunday deb belgilangan.
       Bu ma'lumot emas, interfeys namunasi. */
    disclaimer: 'Namuna: reyting shunday ishlaydi',
    columns: { rank: 'O‘rin', name: 'Ism', xp: 'XP' },
    /* before → keyin animatsiya bilan after tartibiga o'tadi. */
    rows: [
      { id: 'r1', name: 'Nodira',  xpFrom: 2140, xpTo: 2140 },
      { id: 'r2', name: 'Jasur',   xpFrom: 1980, xpTo: 2310 },
      { id: 'r3', name: 'Malika',  xpFrom: 1875, xpTo: 1875 },
      { id: 'r4', name: 'Siz',     xpFrom: 1640, xpTo: 2065, me: true },
      { id: 'r5', name: 'Otabek',  xpFrom: 1520, xpTo: 1520 },
    ],
  },

  /* ---------------------------------------------------------------- 6 */
  footer: {
    title: 'Hozircha Android uchun',
    lead: 'iOS versiyasi yo‘q. Tayyor bo‘lganda shu yerda paydo bo‘ladi. ' +
          'Hozircha ilovani brauzerda ochishingiz mumkin.',
    downloadLabel: 'Google Play’dan yuklab olish',
    /* TODO — ilova Play Store'ga chiqqach haqiqiy manzil qo'yiladi.
       `#` bo'lib turganda `main.js` badge'ni "Tez orada" holatiga o'tkazadi
       va uni bosib bo'lmaydigan qiladi. */
    downloadHref: '#',
    downloadSoon: 'Tez orada',
    telegramLabel: 'Telegram',
    telegramHref: 'https://t.me/topagonuzbot',
    webLabel: 'Brauzerda ochish',
    /* Ilova app.topagon.uz da; topagon.uz — shu landing. */
    webHref: 'https://app.topagon.uz',
    contactLabel: 'Aloqa',
    contactHref: 'mailto:zayniddin686@gmail.com',
    rights: '© 2026 Topag‘on',
  },
};
