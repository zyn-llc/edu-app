-- =============================================================================
--  020 — takrorlangan `subjects` qatorlarini olib tashlash va unikal
--        cheklovni tiklash.
--
--  MUAMMO. `pg_restore --clean` avval cheklovlarni o'chiradi, keyin ma'lumot
--  yuklaydi, oxirida cheklovlarni qaytaradi. Bizda migratsiyalar restore'dan
--  OLDIN ishlagani uchun `subjects` da 002_seed qatorlari turgan edi; dump
--  qatorlari ularning ustiga qo'shildi va `subjects_code_key` ni qaytarish
--  "duplicate key" bilan yiqildi.
--
--  Natija ilovada shunday ko'rinadi: ro'yxatda `ozbekiston_tarixi` ikki marta —
--  biri to'g'ri nomi va 2 415 savoli bilan, ikkinchisi xom kod nomi va
--  "Savollar tayyorlanmoqda" bilan (tarjimasi ham, savoli ham yo'q).
--
--  YECHIM. Har bir `code` uchun BITTA "haqiqiy" qatorni tanlaymiz —
--  savoli ko'prog'ini, teng bo'lsa tarjimasi borini. Qolganlarining
--  bog'liqliklarini haqiqiysiga ko'chirib, o'zlarini o'chiramiz. Keyin
--  unikal cheklovni qaytaramiz, shunda muammo BOSHQA TAKRORLANMAYDI.
--
--  Toza o'rnatishda zararsiz: dublikat yo'q bo'lsa hech narsa o'chmaydi.
-- =============================================================================

BEGIN;

-- ---- 1. Har bir kod uchun saqlanadigan qatorni tanlash ----------------------
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

-- ---- 2. Yo'qoladigan qatorlar ----------------------------------------------
CREATE TEMP TABLE _dupe ON COMMIT DROP AS
SELECT s.id AS dup_id, k.keep_id
  FROM subjects s
  JOIN _keep k ON k.code = s.code
 WHERE s.id <> k.keep_id;

-- ---- 3. Bog'liqliklarni haqiqiy qatorga ko'chirish --------------------------
-- Savol yoki mavzu dublikatga bog'langan bo'lsa, uni yo'qotmaymiz.
UPDATE questions q SET subject_id = d.keep_id
  FROM _dupe d WHERE q.subject_id = d.dup_id;

UPDATE topics t SET subject_id = d.keep_id
  FROM _dupe d WHERE t.subject_id = d.dup_id;

-- Tarjima: haqiqiysida shu til uchun yozuv bo'lmasa ko'chiramiz, bo'lsa
-- dublikatnikini tashlaymiz (aks holda (subject_id, lang) unikalligi buziladi).
UPDATE subject_translations st SET subject_id = d.keep_id
  FROM _dupe d
 WHERE st.subject_id = d.dup_id
   AND NOT EXISTS (
        SELECT 1 FROM subject_translations x
         WHERE x.subject_id = d.keep_id AND x.lang = st.lang);

DELETE FROM subject_translations st
 USING _dupe d WHERE st.subject_id = d.dup_id;

-- ---- 4. Dublikatlarni o'chirish ---------------------------------------------
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
