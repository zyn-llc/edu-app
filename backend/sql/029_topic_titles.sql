-- =========================================================================
--  029_topic_titles.sql — bo'lim sarlavhalaridagi darslik raqamlashi va
--  buzilgan tire
-- =========================================================================
--
--  MUAMMO 1 (2026-08-09, ilovada ko'rilgan).
--
--  Mashq tanlash ekranida matematika bo'limlari shunday turardi:
--
--      94-§. murakkab trigonometriya
--      104-§ (test qismi, variant 47)
--      14.1-bo'lim. elementar funksiyalarning hosilasi (qo'shimcha manba)
--
--  `94-§` — darslikdagi paragraf raqami. O'quvchi bo'limni MAVZU bo'yicha
--  tanlaydi, darslik sahifasi bo'yicha emas; qaysi darslik nazarda
--  tutilgani ham hech qayerda aytilmagan. Raqam ro'yxatni o'qishni
--  qiyinlashtiradi va ustunni bir xil ko'rinishga soladi.
--
--  Bu 877 bo'limdan faqat 23 tasida bor (hammasi matematika) — ya'ni u
--  ma'lumot ham emas, izchillik ham emas.
--
--  MUAMMO 2. 21 ta sarlavhada tire o'rniga uchta savol belgisi turibdi:
--
--      1991???2017-yillarda Fransiya
--      Suriya, Iroq, Isroil, Falastin (1991???2017)
--      VI???VII asrlar madaniy hayoti
--
--  Bu terminal effekti EMAS. Tekshirildi: `ascii()` server tomonda
--  63,63,63 qaytaradi, ya'ni bazada haqiqiy `?` belgilari turibdi —
--  manbani o'qishda `–` (en dash) yo'qolgan. (Solishtirish uchun: ruscha
--  sarlavhalardagi uzun `?` zanjirlari — kirillni ko'rsata olmagan
--  terminalning ishi, bazada matn butun. Shuning uchun quyidagi shart
--  belgi ZANJIRIGA emas, ikki tomonidagi harf/raqamga qaraydi.)
--
--  Savol matnlari va variantlarda bu muammo yo'q (0 ta) — faqat bo'lim
--  sarlavhalarida.
--
--  NEGA SARLAVHA, `code` EMAS. `topics.code` — identifikator: ingest
--  idempotentligi (`Topic.code` bo'yicha qidiruv) va mavjud savollarning
--  bog'lanishi shunga tayanadi. Uni o'zgartirish keyingi ingestda butun
--  bo'limni QAYTA yaratadi va savollar ikki bo'limga bo'linib ketadi.
--  `title` esa faqat ko'rsatish uchun — xavfsiz o'zgaradi.
--
--  NEGA REGEXP AYNAN SHUNDAY TOR. Raqamdan keyin `-§` yoki `-bo'lim`
--  KELISHI SHART. Sabab — jahon tarixidagi 13 ta sarlavha ham raqam bilan
--  boshlanadi, lekin u yerda raqam MA'NONING O'ZI:
--
--      1991-2017-yillarda amerika qo'shma shtatlari   -> TEGILMAYDI
--      1991 – 2017-yillarda dunyo mamlakatlari        -> TEGILMAYDI
--      100-§. hosilaning geometrik ma'nosi            -> TEGILADI
--
--  Prodda quruq sinovdan o'tkazildi: aynan 23 qator o'zgaradi, raqam bilan
--  boshlanadigan qolgan 13 qatorga tegilmaydi.
--
--  `bo'lim` dagi apostrof uch xil bo'lishi mumkin (klaviaturaga qarab
--  `'`, `‘`, `’`, `ʻ`, `ʼ`) — hammasi ro'yxatga kiritilgan.
--
--  BOSH HARF. Prefiks olingandan keyin sarlavha kichik harfdan boshlanadi
--  ("hosilaning geometrik ma'nosi"), holbuki bazadagi qolgan 854 bo'limning
--  BARCHASI katta harf bilan boshlanadi (kichik harfli — 0 ta). Shuning
--  uchun kesishdan keyin bosh harf tiklanadi, aks holda matematika yagona
--  istisno bo'lib qolardi.
--
--  DIQQAT: bu mantiq `app/ingest/run_subject.py` dagi `topic_title()` bilan
--  BIR XIL bo'lishi kerak. U yerda tozalanmasa, keyingi ingest raqamni
--  qaytadan olib keladi va bu migratsiya allaqachon "qo'llangan" deb
--  belgilangan bo'ladi.
--
--  IDEMPOTENT: ikkinchi yurishda shartlar bajarilmaydi, hech narsa
--  o'zgarmaydi.
-- =========================================================================

BEGIN;

-- --- 1. `94-§.` / `14.1-bo'lim.` prefiksi ---------------------------------
UPDATE topic_translations
SET title = regexp_replace(
        title, '^[0-9]+(\.[0-9]+)*\s*-\s*(§|bo[''‘’ʻʼ]lim)\.?\s*', '')
WHERE title ~ '^[0-9]+(\.[0-9]+)*\s*-\s*(§|bo[''‘’ʻʼ]lim)';

-- --- 2. Butunlay qavs ichida qolgan sarlavha -------------------------------
-- `104-§ (test qismi, variant 47)` dan prefiks olingach `(test qismi,
-- variant 47)` qoladi — qavs bilan boshlanadigan sarlavha ro'yxatda
-- buzuqdek ko'rinadi. Ichki qavs bo'lmagan holdagina ochamiz, aks holda
-- "aniq integral (qo'shimcha manba)" kabi qatorlar buzilardi.
UPDATE topic_translations
SET title = btrim(substring(title from 2 for length(title) - 2))
WHERE title ~ '^\([^()]*\)$';

-- --- 3. Buzilgan tire: `1991???2017` -> `1991–2017` ------------------------
--
-- Shart ikki tomondan HARF yoki RAQAM talab qiladi, bo'shliqsiz. Haqiqiy
-- savol belgisi so'z ICHIDA turmaydi — undan keyin bo'shliq yoki satr
-- oxiri keladi ("Nima uchun??? Javob:"). Ya'ni bu shart faqat buzilgan
-- tireni topadi:
--
--     1991???2017        -> 1991–2017      (raqam–raqam)
--     VI???VII asrlar    -> VI–VII asrlar  (rim raqami, harf sifatida)
--     "Nima uchun??? Ha" -> tegilmaydi     (o'ng tomonda bo'shliq)
UPDATE topic_translations
SET title = regexp_replace(
        title, '([0-9[:alpha:]])\?{2,}([0-9[:alpha:]])', '\1–\2', 'g')
WHERE title ~ '[0-9[:alpha:]]\?{2,}[0-9[:alpha:]]';

-- --- 4. Bosh harfni tiklash ------------------------------------------------
-- Faqat kichik lotin harfi bilan boshlanadiganlar. Kirill va raqamga
-- tegilmaydi.
UPDATE topic_translations
SET title = upper(left(title, 1)) || substring(title from 2)
WHERE title ~ '^[a-z]';

-- --- 5. Bosh/oxirgi bo'sh joy ----------------------------------------------
UPDATE topic_translations SET title = btrim(title) WHERE title <> btrim(title);

-- --- 6. Kesishdan keyin bo'sh qolgan sarlavha ------------------------------
-- Bunday bo'lmasligi kerak (prefiksdan keyin doim matn bor edi), lekin
-- bo'sh sarlavhali bo'lim ro'yxatda ko'rinmas tugma bo'lib qoladi.
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM topic_translations WHERE btrim(title) = '';
    IF n > 0 THEN
        RAISE EXCEPTION 'TO''XTATILDI: % ta bo''lim sarlavhasi bo''sh qoldi', n;
    END IF;
END $$;

COMMIT;

-- --- Tekshiruv (qo'lda ishga tushiring) -----------------------------------
--   -- 0 bo'lishi kerak:
--   SELECT count(*) FROM topic_translations
--    WHERE title ~ '^[0-9]+(\.[0-9]+)*\s*-\s*(§|bo[''‘’ʻʼ]lim)';
--   SELECT count(*) FROM topic_translations
--    WHERE title ~ '[0-9[:alpha:]]\?{2,}[0-9[:alpha:]]';
--   SELECT count(*) FROM topic_translations WHERE title ~ '^[a-z]';
--   -- 13 bo'lib qolishi kerak (yil oraliqlari — tegilmagan):
--   SELECT count(*) FROM topic_translations WHERE title ~ '^[0-9]';
