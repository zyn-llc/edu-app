-- =============================================================================
--        cheklovni tiklash.
--
--  yuklaydi, oxirida cheklovlarni qaytaradi. Bizda migratsiyalar restore'dan
--
--
--  unikal cheklovni qaytaramiz, shunda muammo BOSHQA TAKRORLANMAYDI.
--
-- =============================================================================

BEGIN;

CREATE TEMP TABLE _keep ON COMMIT DROP AS
SELECT DISTINCT ON (s.code)
       s.code,
       s.id AS keep_id
  FROM subjects s
  LEFT JOIN LATERAL (
      SELECT count(*) AS n FROM questions q WHERE q.subject_id = s.id
  ) qc ON TRUE
  LEFT JOIN LATERAL (
      SELECT count(*) AS n FROM subject_translations t WHERE t.subject_id = s.id
  ) tc ON TRUE
 ORDER BY s.code, qc.n DESC, tc.n DESC, s.id;

CREATE TEMP TABLE _dupe ON COMMIT DROP AS
SELECT s.id AS dup_id, k.keep_id
  FROM subjects s
  JOIN _keep k ON k.code = s.code
 WHERE s.id <> k.keep_id;

-- ---- 3. Bog'liqliklarni haqiqiy qatorga ko'chirish --------------------------
UPDATE questions q SET subject_id = d.keep_id
  FROM _dupe d WHERE q.subject_id = d.dup_id;

UPDATE topics t SET subject_id = d.keep_id
  FROM _dupe d WHERE t.subject_id = d.dup_id;

UPDATE subject_translations st SET subject_id = d.keep_id
  FROM _dupe d
 WHERE st.subject_id = d.dup_id
   AND NOT EXISTS (
        SELECT 1 FROM subject_translations x
         WHERE x.subject_id = d.keep_id AND x.lang = st.lang);

DELETE FROM subject_translations st
 USING _dupe d WHERE st.subject_id = d.dup_id;

DELETE FROM subjects s USING _dupe d WHERE s.id = d.dup_id;

-- ---- 5. Unikal cheklovni qaytarish ------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.subjects'::regclass
           AND contype = 'u'
           AND conname = 'subjects_code_key'
    ) THEN
        ALTER TABLE public.subjects ADD CONSTRAINT subjects_code_key UNIQUE (code);
        RAISE NOTICE 'subjects_code_key qaytarildi';
    ELSE
        RAISE NOTICE 'subjects_code_key allaqachon bor';
    END IF;
END $$;

COMMIT;

-- ---- 6. Natija --------------------------------------------------------------
SELECT s.code,
       (SELECT name FROM subject_translations t
         WHERE t.subject_id = s.id AND t.lang = 'uz-Latn') AS nomi,
       (SELECT count(*) FROM questions q
         WHERE q.subject_id = s.id AND q.status = 'active') AS aktiv_savol
  FROM subjects s
 ORDER BY s.sort_order, s.code;
