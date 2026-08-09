-- =============================================================================
--  quality_deep.sql — audit ochib bergan uchta savolga aniq javob.
--
--    Get-Content sql/quality_deep.sql | docker compose exec -T db psql -U edu -d edu
--
--  Faqat SELECT. Hech narsa o'zgarmaydi.
-- =============================================================================

\echo '===== A. media USTUNIDA NIMA BOR? ====='
-- 13 596 raqami shubhali: bu deyarli butun bank. Ehtimol media ustuni SQL NULL
-- emas, JSON null yoki bo'sh obyekt — u holda `media IS NOT NULL` HAMMASIGA
-- to'g'ri keladi va rasm bilan aloqasi yo'q.
SELECT
    jsonb_typeof(media)                    AS tur,
    count(*)                               AS soni,
    left(min(media::text), 60)             AS namuna_min,
    left(max(media::text), 60)             AS namuna_max
FROM questions
GROUP BY jsonb_typeof(media)
ORDER BY 2 DESC;

\echo ''
\echo '--- HAQIQIY rasmli savollar (ichida ref bor) ---'
SELECT count(*) AS haqiqiy_rasmli
FROM questions
WHERE media IS NOT NULL
  AND jsonb_typeof(media) = 'object'
  AND media ? 'ref'
  AND coalesce(media->>'ref', '') <> '';

\echo ''
\echo '--- ularning fan/sinf bo`yicha taqsimoti ---'
SELECT s.code AS fan, q.grade, count(*) AS rasmli, q.status
FROM questions q JOIN subjects s ON s.id = q.subject_id
WHERE q.media ? 'ref' AND coalesce(q.media->>'ref','') <> ''
GROUP BY s.code, q.grade, q.status ORDER BY 3 DESC;

\echo ''
\echo '--- matnida "rasm" so`zi bor, lekin media ref YO`Q (yashirin muammo) ---'
SELECT q.source_ref, s.code AS fan, left(qt.stem, 70) AS matn
FROM questions q
JOIN subjects s ON s.id = q.subject_id
JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'active'
  AND qt.stem ~* '(rasmda|rasmdagi|sxemada|chizmada|jadvalda|tasvirlangan)'
  AND NOT (q.media ? 'ref')
ORDER BY s.code, q.source_ref
LIMIT 60;

\echo ''
\echo '--- yuqoridagining SONI ---'
SELECT s.code AS fan, count(*) AS rasmsiz_rasmli_savol
FROM questions q
JOIN subjects s ON s.id = q.subject_id
JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'active'
  AND qt.stem ~* '(rasmda|rasmdagi|sxemada|chizmada|tasvirlangan)'
  AND NOT (q.media ? 'ref')
GROUP BY s.code ORDER BY 2 DESC;


\echo ''
\echo '===== B. ona_tili TAKRORLARI — variantlari HAM bir xilmi? ====='
-- Agar savol matni bir xil, LEKIN variantlar boshqa bo'lsa — bu normal
-- (bitta savol shakli, har xil parcha). Variantlar ham bir xil bo'lsa —
-- chinakam dublikat.
WITH sig AS (
  SELECT q.id, q.source_ref, qt.stem,
         string_agg(coalesce(ot.text,''), '|' ORDER BY o.position) AS variantlar
  FROM questions q
  JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
  LEFT JOIN options o ON o.question_id = q.id
  LEFT JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
  WHERE q.status = 'active' AND q.source_ref LIKE 'ona_tili%'
  GROUP BY q.id, q.source_ref, qt.stem
)
SELECT left(stem, 50) AS matn,
       count(*)                              AS bir_xil_matn,
       count(DISTINCT variantlar)            AS turli_variant,
       CASE WHEN count(DISTINCT variantlar) = 1 THEN 'CHINAKAM DUBLIKAT'
            ELSE 'normal (variantlar boshqa)' END AS xulosa
FROM sig GROUP BY stem HAVING count(*) > 1
ORDER BY 2 DESC LIMIT 30;

\echo ''
\echo '--- butun bazada CHINAKAM dublikatlar (matn + variantlar bir xil) ---'
WITH sig AS (
  SELECT q.id, q.source_ref, s.code AS fan, qt.stem,
         string_agg(coalesce(ot.text,''), '|' ORDER BY o.position) AS variantlar
  FROM questions q
  JOIN subjects s ON s.id = q.subject_id
  JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
  LEFT JOIN options o ON o.question_id = q.id
  LEFT JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
  WHERE q.status = 'active'
  GROUP BY q.id, q.source_ref, s.code, qt.stem
)
SELECT fan, count(*) AS nusxa,
       string_agg(source_ref, ', ' ORDER BY source_ref) AS source_reflar
FROM sig GROUP BY fan, stem, variantlar HAVING count(*) > 1
ORDER BY 2 DESC LIMIT 40;


\echo ''
\echo '===== C. bio_g9_q0127..0131 va geo_g10_q1120 — to`liq ko`rinish ====='
SELECT q.source_ref, o.option_key, o.position,
       ot.text AS variant,
       q.grading_spec->'correct_option_ids' AS kalit
FROM questions q
JOIN options o ON o.question_id = q.id
LEFT JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
WHERE q.source_ref IN ('bio_g9_q0127','bio_g9_q0128','bio_g9_q0129',
                       'bio_g9_q0130','bio_g9_q0131','geo_g10_q1120',
                       'geo_g10_q0665','geo_g10_q0666')
ORDER BY q.source_ref, o.position;

\echo ''
\echo '--- "[noaniq" / "xira" / defekt izohi qolgan savollar ---'
SELECT s.code AS fan, count(*) AS soni
FROM questions q
JOIN subjects s ON s.id = q.subject_id
JOIN options o ON o.question_id = q.id
JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
WHERE q.status = 'active' AND ot.text ~* '(noaniq|xira|\[.*bet)'
GROUP BY s.code ORDER BY 2 DESC;

\echo ''
\echo '--- ularning source_ref lari (chiqarib tashlash uchun) ---'
SELECT DISTINCT q.source_ref
FROM questions q
JOIN options o ON o.question_id = q.id
JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
WHERE q.status = 'active' AND ot.text ~* '(noaniq|xira|\[.*bet)'
ORDER BY 1 LIMIT 100;

\echo ''
\echo '===== D. OCR buzilgan belgilar (тАФ, ┬л, ╩╗ kabi) ====='
-- Bular hisobotdagi "тАФ" ko'rinishidagi belgilar. Ular bazada emas, psql
-- kodlashida ham bo'lishi mumkin — shu so'rov haqiqatini aniqlaydi.
SELECT s.code AS fan, count(*) AS soni
FROM questions q
JOIN subjects s ON s.id = q.subject_id
JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'active' AND qt.stem ~ '[\u0400-\u04FF]'   -- kirill harfi
GROUP BY s.code ORDER BY 2 DESC;
