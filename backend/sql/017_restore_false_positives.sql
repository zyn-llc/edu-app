SELECT q.source_ref, left(qt.stem, 75) AS matn
FROM questions q
JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'draft'
  AND NOT (q.media ? 'ref')
  AND qt.stem ~* '(rasmiy|rasman)'
  AND qt.stem !~* '(\mrasm\M|rasmda|rasmdagi|rasmga|rasmni|rasmning|rasmlar|sxema|chizma|grafik)'
ORDER BY q.source_ref LIMIT 30;

\echo ''
\echo '--- SONI ---'
SELECT count(*) AS qaytariladi
FROM questions q
JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'draft'
  AND NOT (q.media ? 'ref')
  AND qt.stem !~* '(\mrasm\M|rasmda|rasmdagi|rasmga|rasmni|rasmning|rasmlar|sxema|chizma|grafik)'
  AND q.id NOT IN (
      SELECT o.question_id FROM options o
      JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
      WHERE ot.text ~* '(noaniq|xira|\[.*bet)')
  AND q.id NOT IN (
      SELECT o.question_id FROM options o
      JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
      GROUP BY o.question_id, ot.text HAVING count(*) > 1);

BEGIN;

UPDATE questions q SET status = 'active', updated_at = now()
FROM question_translations qt
WHERE qt.question_id = q.id AND qt.lang = 'uz-Latn'
  AND q.status = 'draft'
  AND NOT (q.media ? 'ref')
  AND qt.stem !~* '(\mrasm\M|rasmda|rasmdagi|rasmga|rasmni|rasmning|rasmlar|sxema|chizma|grafik)'
  AND q.id NOT IN (
      SELECT o.question_id FROM options o
      JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
      WHERE ot.text ~* '(noaniq|xira|\[.*bet)')
  AND q.id NOT IN (
      SELECT o.question_id FROM options o
      JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
      GROUP BY o.question_id, ot.text HAVING count(*) > 1)
  AND q.id NOT IN (
      SELECT id FROM (
        SELECT q2.id, row_number() OVER (
                 PARTITION BY qt2.stem,
                 (SELECT string_agg(coalesce(ot2.text,''), '|' ORDER BY o2.position)
                    FROM options o2
                    LEFT JOIN option_translations ot2
                      ON ot2.option_id = o2.id AND ot2.lang = 'uz-Latn'
                   WHERE o2.question_id = q2.id)
                 ORDER BY q2.source_ref) AS rn
        FROM questions q2
        JOIN question_translations qt2
          ON qt2.question_id = q2.id AND qt2.lang = 'uz-Latn'
      ) d WHERE rn > 1);

COMMIT;

\echo ''
\echo '===== YAKUNIY HOLAT ====='
SELECT count(*) FILTER (WHERE status='active') AS jami_aktiv,
       count(*) FILTER (WHERE status='draft')  AS jami_draft
FROM questions;

\echo ''
SELECT s.code AS fan,
       count(*) FILTER (WHERE q.status='active') AS aktiv,
       count(*) FILTER (WHERE q.status='draft')  AS draft
FROM questions q JOIN subjects s ON s.id = q.subject_id
GROUP BY s.code ORDER BY 3 DESC;

\echo ''
\echo '--- draft qolganlar: nega draft ekani ---'
SELECT
    count(*) FILTER (WHERE q.media ? 'ref')                         AS rasm_hostingi_yoq,
    count(*) FILTER (WHERE qt.stem ~* '(\mrasm\M|rasmda|rasmdagi|rasmga|rasmni|rasmlar|sxema|chizma|grafik)') AS rasmga_ishora,
    count(*)                                                        AS jami_draft
FROM questions q
LEFT JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'draft';
