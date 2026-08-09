-- =============================================================================
--  010_retire_legacy_duplicates.sql
--  Eski geo yuklamasi legacy ID formatida saqlangan ('geo_g10_q836'), yangi
--  canonical yuklama esa zero-padded ('geo_g10_q0836'). source_ref mos
--  kelmagani uchun idempotency ishlamagan -> bir savol bazada ikki marta.
--
--  O'CHIRMAYMIZ: submissions.question_id FK'da ON DELETE yo'q (RESTRICT), va
--  o'quvchi javob tarixini yo'qotmaslik kerak. O'rniga status='retired' —
--  content API uch joyda ham status='active' filtrlaydi, ya'ni retired savol
--  hech qayerda ko'rsatilmaydi.
--
--    docker compose exec -T db psql -U edu -d edu < sql/010_retire_legacy_duplicates.sql
-- =============================================================================

-- ---- 1) OLDIN KO'R: nechta satr retired bo'ladi -----------------------------
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

-- ---- 2) Juftligi YO'Q legacy satrlar (bular saqlanadi, faqat xabar uchun) ---
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

-- ---- 4) Natija -------------------------------------------------------------
SELECT status, count(*) FROM questions GROUP BY status ORDER BY 2 DESC;

SELECT s.code AS subject, q.grade, count(*) AS active_savol
FROM questions q JOIN subjects s ON s.id = q.subject_id
WHERE q.status = 'active'
GROUP BY s.code, q.grade
ORDER BY s.code, q.grade;
