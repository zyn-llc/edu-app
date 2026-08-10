-- =============================================================================
--  qaytaradi.
--
--  SABAB: `app/ingest/run_subject.py` da
--      grade=c.get("grade", bank_grade)
--
--
--  `_g<raqam>_q` shabloniga tushmaydigan qatorlarga TEGILMAYDI.
-- =============================================================================

BEGIN;

\echo '--- OLDIN: grade IS NULL ---'
SELECT count(*) AS sinfsiz FROM questions WHERE grade IS NULL;

UPDATE questions
   SET grade = (regexp_match(source_ref, '_g(\d+)_q'))[1]::smallint
 WHERE grade IS NULL
   AND source_ref ~ '_g\d+_q'
   AND ((regexp_match(source_ref, '_g(\d+)_q'))[1]::int BETWEEN 1 AND 11);

\echo '--- KEYIN: sinf bo''yicha taqsimot ---'
SELECT grade, count(*) AS soni
  FROM questions
 WHERE status = 'active'
 GROUP BY grade
 ORDER BY grade NULLS LAST;

COMMIT;
