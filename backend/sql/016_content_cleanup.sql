-- =============================================================================
--  016_content_cleanup.sql — audit topgan buzuq savollarni chiqarib tashlash.
--
--    Get-Content sql/016_content_cleanup.sql | docker compose exec -T db psql -U edu -d edu
--
--  Hech narsa O'CHIRILMAYDI. Faqat status='draft' qilinadi:
--    * submissions FK bilan bog'langan — DELETE tarixni buzadi
--    * run_subject.py source_ref bo'yicha skip qiladi -> o'chirilgan savol
--      keyingi yuklamada QAYTIB keladi
--    * draft qaytariladi, DELETE qaytarilmaydi
--  content.py faqat 'active' ni tarqatadi, ya'ni draft = o'quvchiga ko'rinmaydi.
--
--  Har bo'limdan oldin SONI chiqadi, keyin UPDATE bo'ladi.
--
--  ⚠️ DIQQAT: eski hujjatlardagi
--       UPDATE questions SET status='draft' WHERE media IS NOT NULL
--     buyrug'ini ISHLATMA. `media` ustunida 13 584 ta JSON `null` bor va
--     PostgreSQL uchun jsonb 'null' IS NOT NULL -> ROST. O'sha buyruq butun
--     bankni draft qilib qo'yadi. To'g'ri shart: media ? 'ref'.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
--  1. HAQIQIY rasmli savollar (12 ta) — rasm hostingi hali yo'q
-- ---------------------------------------------------------------------------
\echo '--- 1. media ref bor (rasm zanjiri tayyor bo`lguncha draft) ---'
SELECT count(*) AS soni FROM questions
WHERE status = 'active' AND media ? 'ref' AND coalesce(media->>'ref','') <> '';

UPDATE questions SET status = 'draft', updated_at = now()
WHERE status = 'active' AND media ? 'ref' AND coalesce(media->>'ref','') <> '';


-- ---------------------------------------------------------------------------
--  2. Rasmga ishora qiladi, lekin rasm yo'q — javob berib bo'lmaydi
-- ---------------------------------------------------------------------------
--  Faqat ANIQ rasm so'zlari: rasm / sxema / chizma / grafik.
--  "tasvirlangan" va "jadval" ataylab KIRITILMAGAN — ular matn ichida ham
--  uchraydi ("Berilgan fikrda ... tasvirlangan"), ularni qo'lda ko'rasan.
\echo '--- 2. rasmga ishora, media yo`q ---'
SELECT count(*) AS soni
FROM questions q
JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'active'
  AND qt.stem ~* '(rasm|sxema|chizma|grafik)'
  AND NOT (q.media ? 'ref');

UPDATE questions q SET status = 'draft', updated_at = now()
FROM question_translations qt
WHERE qt.question_id = q.id AND qt.lang = 'uz-Latn'
  AND q.status = 'active'
  AND qt.stem ~* '(rasm|sxema|chizma|grafik)'
  AND NOT (q.media ? 'ref');


-- ---------------------------------------------------------------------------
--  3. Defekt izohi variant matniga kirib ketgan
-- ---------------------------------------------------------------------------
--  geo_g10_q0665 da to'g'ri javob AYNAN "[noaniq — 414-bet xira]" —
--  o'quvchi hech qachon to'g'ri javob bera olmaydi.
\echo '--- 3. variantida "[noaniq / xira / N-bet]" bor ---'
SELECT count(DISTINCT q.id) AS soni
FROM questions q
JOIN options o ON o.question_id = q.id
JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
WHERE q.status = 'active' AND ot.text ~* '(noaniq|xira|\[.*bet)';

UPDATE questions SET status = 'draft', updated_at = now()
WHERE status = 'active' AND id IN (
    SELECT o.question_id FROM options o
    JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
    WHERE ot.text ~* '(noaniq|xira|\[.*bet)');


-- ---------------------------------------------------------------------------
--  4. Ikki varianti AYNAN bir xil — javob noaniq
-- ---------------------------------------------------------------------------
--  geo_g10_q1120: opt_a va opt_d ikkalasi ham "-2 °C", kalit opt_d.
--  "-2 °C" ni tanlagan o'quvchi opt_a ni bosса XATO oladi. Bu eng yomon
--  turdagi nosozlik: o'quvchi to'g'ri biladi, lekin tizim xato deydi.
\echo '--- 4. takroriy variant matni ---'
SELECT count(DISTINCT question_id) AS soni FROM (
    SELECT o.question_id, ot.text
    FROM questions q
    JOIN options o ON o.question_id = q.id
    JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
    WHERE q.status = 'active'
    GROUP BY o.question_id, ot.text HAVING count(*) > 1) d;

UPDATE questions SET status = 'draft', updated_at = now()
WHERE status = 'active' AND id IN (
    SELECT o.question_id
    FROM options o
    JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
    GROUP BY o.question_id, ot.text HAVING count(*) > 1);


-- ---------------------------------------------------------------------------
--  5. Chinakam dublikatlar — matn VA variantlar bir xil
-- ---------------------------------------------------------------------------
--  Birinchisi (source_ref bo'yicha eng kichigi) QOLADI, qolgani draft.
--  ona_tili dagi 50/27/25 lik guruhlar bu yerga TUSHMAYDI — ularda variantlar
--  har xil, ya'ni ular haqiqiy alohida savollar.
\echo '--- 5. chinakam dublikatlar (birinchisi qoladi) ---'
WITH sig AS (
    SELECT q.id, q.source_ref, qt.stem,
           string_agg(coalesce(ot.text,''), '|' ORDER BY o.position) AS variantlar
    FROM questions q
    JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
    LEFT JOIN options o ON o.question_id = q.id
    LEFT JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
    WHERE q.status = 'active'
    GROUP BY q.id, q.source_ref, qt.stem
), ranked AS (
    SELECT id, row_number() OVER (PARTITION BY stem, variantlar
                                  ORDER BY source_ref) AS rn
    FROM sig
)
SELECT count(*) AS soni FROM ranked WHERE rn > 1;

WITH sig AS (
    SELECT q.id, q.source_ref, qt.stem,
           string_agg(coalesce(ot.text,''), '|' ORDER BY o.position) AS variantlar
    FROM questions q
    JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
    LEFT JOIN options o ON o.question_id = q.id
    LEFT JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
    WHERE q.status = 'active'
    GROUP BY q.id, q.source_ref, qt.stem
), ranked AS (
    SELECT id, row_number() OVER (PARTITION BY stem, variantlar
                                  ORDER BY source_ref) AS rn
    FROM sig
)
UPDATE questions SET status = 'draft', updated_at = now()
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);


-- ---------------------------------------------------------------------------
--  6. Kirill harflari qolib ketgan (OCR)
-- ---------------------------------------------------------------------------
\echo '--- 6. matnida kirill harfi ---'
SELECT q.source_ref, left(qt.stem, 60) AS matn
FROM questions q
JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'active' AND qt.stem ~ '[\u0400-\u04FF]';
-- Soni kam (4 ta) — ularni draft qilmaymiz, qo'lda tuzatasan.

COMMIT;


-- =============================================================================
--  NATIJA
-- =============================================================================
\echo ''
\echo '===== YAKUNIY HOLAT ====='
SELECT s.code AS fan, q.grade,
       count(*) FILTER (WHERE q.status = 'active') AS aktiv,
       count(*) FILTER (WHERE q.status = 'draft')  AS draft
FROM questions q JOIN subjects s ON s.id = q.subject_id
GROUP BY s.code, q.grade ORDER BY s.code, q.grade;

\echo ''
SELECT count(*) FILTER (WHERE status='active') AS jami_aktiv,
       count(*) FILTER (WHERE status='draft')  AS jami_draft
FROM questions;

\echo ''
\echo '===== QO`LDA KO`RIB CHIQISH KERAK ====='
\echo '--- "jadval"/"tasvirlangan" bor, lekin rasm so`zi yo`q ---'
SELECT q.source_ref, left(qt.stem, 70) AS matn
FROM questions q
JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'active'
  AND qt.stem ~* '(jadval|tasvirlangan)'
  AND qt.stem !~* '(rasm|sxema|chizma|grafik)'
ORDER BY q.source_ref LIMIT 50;

-- Qaytarib olish (kerak bo'lsa):
--   UPDATE questions SET status='active', updated_at=now()
--   WHERE source_ref IN ('...');
