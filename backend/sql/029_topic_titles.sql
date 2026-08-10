-- =========================================================================
--  buzilgan tire
-- =========================================================================
--
--
--
--      94-§. murakkab trigonometriya
--
--  tutilgani ham hech qayerda aytilmagan. Raqam ro'yxatni o'qishni
--
--
--
--      1991???2017-yillarda Fransiya
--      Suriya, Iroq, Isroil, Falastin (1991???2017)
--      VI???VII asrlar madaniy hayoti
--
--
--  sarlavhalarida.
--
--
--
--      1991 – 2017-yillarda dunyo mamlakatlari        -> TEGILMAYDI
--      100-§. hosilaning geometrik ma'nosi            -> TEGILADI
--
--  boshlanadigan qolgan 13 qatorga tegilmaydi.
--
--  `'`, `‘`, `’`, `ʻ`, `ʼ`) — hammasi ro'yxatga kiritilgan.
--
--
--
-- =========================================================================

BEGIN;

UPDATE topic_translations
SET title = regexp_replace(
        title, '^[0-9]+(\.[0-9]+)*\s*-\s*(§|bo[''‘’ʻʼ]lim)\.?\s*', '')
WHERE title ~ '^[0-9]+(\.[0-9]+)*\s*-\s*(§|bo[''‘’ʻʼ]lim)';

-- --- 2. Butunlay qavs ichida qolgan sarlavha -------------------------------
UPDATE topic_translations
SET title = btrim(substring(title from 2 for length(title) - 2))
WHERE title ~ '^\([^()]*\)$';

-- --- 3. Buzilgan tire: `1991???2017` -> `1991–2017` ------------------------
--
-- tireni topadi:
--
--     1991???2017        -> 1991–2017      (raqam–raqam)
--     VI???VII asrlar    -> VI–VII asrlar  (rim raqami, harf sifatida)
UPDATE topic_translations
SET title = regexp_replace(
        title, '([0-9[:alpha:]])\?{2,}([0-9[:alpha:]])', '\1–\2', 'g')
WHERE title ~ '[0-9[:alpha:]]\?{2,}[0-9[:alpha:]]';

-- --- 4. Bosh harfni tiklash ------------------------------------------------
-- tegilmaydi.
UPDATE topic_translations
SET title = upper(left(title, 1)) || substring(title from 2)
WHERE title ~ '^[a-z]';

UPDATE topic_translations SET title = btrim(title) WHERE title <> btrim(title);

DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM topic_translations WHERE btrim(title) = '';
    IF n > 0 THEN
        RAISE EXCEPTION 'TO''XTATILDI: % ta bo''lim sarlavhasi bo''sh qoldi', n;
    END IF;
END $$;

COMMIT;

--   SELECT count(*) FROM topic_translations
--    WHERE title ~ '^[0-9]+(\.[0-9]+)*\s*-\s*(§|bo[''‘’ʻʼ]lim)';
--   SELECT count(*) FROM topic_translations
--    WHERE title ~ '[0-9[:alpha:]]\?{2,}[0-9[:alpha:]]';
--   SELECT count(*) FROM topic_translations WHERE title ~ '^[a-z]';
--   SELECT count(*) FROM topic_translations WHERE title ~ '^[0-9]';
