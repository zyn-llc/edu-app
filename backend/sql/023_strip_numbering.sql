-- =========================================================================
--  023_strip_numbering.sql — savol matnidagi va variantlardagi qoldiq
--  raqamlashni olib tashlash
-- =========================================================================
--
--  MUAMMO (2026-08-06, sinovda ko'rilgan).
--
--  Savollar PDF/Word to'plamlaridan olingan va parser raqamlashni matn
--  ichida qoldirgan:
--
--      "12. Tabiat komponentlari birgalikda nimani hosil qiladi?"
--      variantlar:  "A)mavjudod, tajjub"  "B)muhofaza, loqayd"
--
--  Ilova o'z tartib raqamini ("Savol 3/20") ko'rsatadi, ya'ni matn
--  ichidagi "12." unga zid keladi va savol buzuq ko'rinadi. Variantdagi
--  "A)" esa ilovaning o'z harf belgisi (A/B/C/D doirasi) bilan
--  IKKILANADI — o'quvchi ikkita harf ko'radi.
--
--  Manba fayllarda o'lchangan hajmi (`clean_data/*/uz.json`, 23 484 savol):
--      raqam bilan boshlanuvchi savol : 137   (ona_tili 105, geo_g5 32)
--      "A)" prefiksli variantli savol : 205   (ona_tili 98, wh_g11 40)
--
--  NEGA REGEXP_REPLACE, VA NEGA AYNAN SHU SHART.
--
--  Shart ataylab tor: raqamdan keyin `.` yoki `)` KELISHI SHART, undan
--  keyin esa HARF turishi shart. Sabab — noto'g'ri tegib ketmaslik:
--
--      "1991 – 2017-yillarda ..."   -> tegilmaydi (nuqta/qavs yo'q)
--      "2) 5x + 3 = 13 tenglama..." -> tegilmaydi (keyin raqam, harf emas)
--      "12. Tabiat komponentlari"   -> TEGILADI
--
--  `{1,4}` — 4 xonadan uzun "tartib raqami" bo'lmaydi; `19951.` kabi
--  narsaga tegib ketmaslik uchun chegara qo'yilgan.
--
--  Variantlar uchun harf ro'yxati `[A-Da-d]` bilan chegaralangan: bankdagi
--  barcha savollarda ko'pi bilan 4 ta variant bor, ya'ni `E)` bo'lishi
--  mumkin emas va "E)" bilan boshlanadigan haqiqiy javob matni
--  (masalan "E) harfi") tasodifan kesilmaydi.
--
--  IDEMPOTENT: ikkinchi marta ishga tushirilsa hech narsa o'zgarmaydi,
--  chunki birinchi yurishdan keyin shart bajarilmay qoladi.
-- =========================================================================

BEGIN;

-- --- 1. Savol matnidagi bosh raqamlash -----------------------------------
UPDATE question_translations
SET stem = regexp_replace(stem, '^\s*\d{1,4}\s*[.)]\s*', '')
WHERE stem ~ '^\s*\d{1,4}\s*[.)]\s*[[:alpha:]]';

-- --- 2. Variantlardagi "A)" / "a." prefiksi -------------------------------
-- Bo'sh joy shart EMAS: manbada "A)mavjudod" (bo'shliqsiz) ham uchraydi.
UPDATE option_translations
SET text = regexp_replace(text, '^\s*[A-Da-d]\s*[.)]\s*', '')
WHERE text ~ '^\s*[A-Da-d]\s*[.)]\s*\S';

-- --- 3. Bosh/oxirgi bo'sh joy ---------------------------------------------
-- Yuqoridagi kesishdan keyin qolishi mumkin.
UPDATE question_translations SET stem = btrim(stem) WHERE stem <> btrim(stem);
UPDATE option_translations   SET text = btrim(text) WHERE text <> btrim(text);

-- --- 4. Kesishdan keyin bo'sh qolgan yozuvlar -----------------------------
-- Bunday bo'lmasligi kerak (shart harf talab qiladi), lekin tekshiramiz:
-- bo'sh matnli savol o'quvchiga ko'rinmasligi shart.
UPDATE questions q
SET status = 'draft'
WHERE q.status = 'active'
  AND EXISTS (
    SELECT 1 FROM question_translations t
    WHERE t.question_id = q.id AND btrim(t.stem) = ''
  );

COMMIT;

-- --- Tekshiruv (qo'lda ishga tushiring) -----------------------------------
--   SELECT count(*) FROM question_translations
--    WHERE stem ~ '^\s*\d{1,4}\s*[.)]\s*[[:alpha:]]';        -- 0 bo'lishi kerak
--   SELECT count(*) FROM option_translations
--    WHERE text ~ '^\s*[A-Da-d]\s*[.)]\s*\S';                -- 0 bo'lishi kerak
