SELECT count(*) AS "retire bo'ladigan legacy dublikatlar"
FROM questions q
WHERE q.status = 'active'
  AND q.source_ref ~ '_q[0-9]{1,3}$'
  AND EXISTS (
      SELECT 1 FROM questions n
      WHERE n.source_ref =
            regexp_replace(q.source_ref, '_q[0-9]{1,3}$', '_q')
            || lpad(substring(q.source_ref from '_q([0-9]{1,3})$'), 4, '0')
        AND n.id <> q.id
  );

SELECT count(*) AS "juftsiz legacy satrlar (active qoladi)"
FROM questions q
WHERE q.status = 'active'
  AND q.source_ref ~ '_q[0-9]{1,3}$'
  AND NOT EXISTS (
      SELECT 1 FROM questions n
      WHERE n.source_ref =
            regexp_replace(q.source_ref, '_q[0-9]{1,3}$', '_q')
            || lpad(substring(q.source_ref from '_q([0-9]{1,3})$'), 4, '0')
        AND n.id <> q.id
  );

-- ---- 3) Retire -------------------------------------------------------------
BEGIN;

UPDATE questions q
SET status = 'retired'
WHERE q.status = 'active'
  AND q.source_ref ~ '_q[0-9]{1,3}$'
  AND EXISTS (
      SELECT 1 FROM questions n
      WHERE n.source_ref =
            regexp_replace(q.source_ref, '_q[0-9]{1,3}$', '_q')
            || lpad(substring(q.source_ref from '_q([0-9]{1,3})$'), 4, '0')
        AND n.id <> q.id
  );

COMMIT;


SELECT status, count(*) FROM questions GROUP BY status ORDER BY 2 DESC;

SELECT s.code AS subject, q.grade, count(*) AS active_savol
FROM questions q JOIN subjects s ON s.id = q.subject_id
WHERE q.status = 'active'
GROUP BY s.code, q.grade
ORDER BY s.code, q.grade;
