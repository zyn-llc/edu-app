-- 008_source_ref_unique.sql
-- Faza 0 / arxitektura kamchilik #1: ingest idempotency'ni DB darajasida majburiy qilish.
-- 001-007 dan keyin ishlatiladi. Pre-launch migratsiya (dublikat savollarda hali
-- real submission yo'q deb faraz qilinadi -- launch'dan oldin xavfsiz).
BEGIN;

-- 1) Bir xil source_ref'ga ega dublikat savollarni o'chirish, eng eskisini qoldirib.
--    question_translations / options / option_translations ON DELETE CASCADE bilan tozalanadi.
--    Agar submissions FK RESTRICT tufayli xato bersa -> dublikatda real submission bor,
--    qo'lda ko'rib chiqiladi (pre-launch'da bo'lmasligi kerak).
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

-- 2) Bundan keyin unikallikni majburiy qilish (partial: source_ref nullable).
CREATE UNIQUE INDEX IF NOT EXISTS ux_questions_source_ref
    ON questions (source_ref)
    WHERE source_ref IS NOT NULL;

COMMIT;