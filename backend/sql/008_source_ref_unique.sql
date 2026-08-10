-- 008_source_ref_unique.sql
BEGIN;

WITH ranked AS (
    SELECT id,
           row_number() OVER (
               PARTITION BY source_ref
               ORDER BY created_at, id
           ) AS rn
    FROM questions
    WHERE source_ref IS NOT NULL
)
DELETE FROM questions q
USING ranked r
WHERE q.id = r.id AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_questions_source_ref
    ON questions (source_ref)
    WHERE source_ref IS NOT NULL;

COMMIT;