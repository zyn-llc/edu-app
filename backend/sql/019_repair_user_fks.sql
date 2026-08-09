-- =============================================================================
--  019 — pg_restore'dan keyin foydalanuvchi FK'larini tiklash.
--
--  MUAMMO. Prodga kontent `pg_restore --clean --if-exists` bilan yuklanadi.
--  Migratsiyalar undan OLDIN ishlagani uchun `users` jadvalida seed qatori
--  turadi; dump'dagi `users` COPY'si o'sha qator bilan to'qnashib yiqiladi.
--  Bolalar jadvallari (submissions, coin_transactions, ...) esa to'liq
--  yuklanadi — natijada egasi yo'q "yetim" qatorlar qoladi va pg_restore
--  ettita FOREIGN KEY cheklovini QO'SHA OLMAYDI:
--
--      coin_transactions_user_id_fkey   feedback_user_id_fkey
--      guardianship_parent_id_fkey      guardianship_student_id_fkey
--      refresh_tokens_user_id_fkey      submissions_user_id_fkey
--      user_progress_user_id_fkey
--
--  Cheklovsiz baza jim buziladi: o'chirilgan foydalanuvchining tangalari va
--  javoblari qolib ketadi, reyting va retention statistikasi noto'g'ri
--  chiqadi.
--
--  YECHIM. Yetim qatorlarni o'chirib (prodga dev sinov ma'lumoti KERAK EMAS),
--  cheklovlarni qaytadan qo'yamiz. Kontentga (savollar, fanlar, mavzular)
--  umuman tegilmaydi.
--
--  Toza o'rnatishda ham xavfsiz: o'chiradigan qatori yo'q, cheklov allaqachon
--  bor bo'lsa qayta qo'shilmaydi.
-- =============================================================================

BEGIN;

-- ---- 1. Yetim qatorlarni tozalash ------------------------------------------
DELETE FROM submissions       WHERE user_id   NOT IN (SELECT id FROM users);
DELETE FROM coin_transactions WHERE user_id   NOT IN (SELECT id FROM users);
DELETE FROM user_progress     WHERE user_id   NOT IN (SELECT id FROM users);
DELETE FROM refresh_tokens    WHERE user_id   NOT IN (SELECT id FROM users);
DELETE FROM guardianship      WHERE parent_id NOT IN (SELECT id FROM users)
                                 OR student_id NOT IN (SELECT id FROM users);

-- Fikrlar SAQLANADI: FK'si `ON DELETE SET NULL`, ya'ni muallifsiz xabar
-- to'g'ri holat. Xabarning o'zi qimmatli — o'chirmaymiz.
UPDATE feedback SET user_id = NULL
 WHERE user_id IS NOT NULL AND user_id NOT IN (SELECT id FROM users);

-- ---- 2. Cheklovlarni qaytarish ---------------------------------------------
-- `ADD CONSTRAINT IF NOT EXISTS` Postgres'da yo'q, shuning uchun DO blok.
DO $$
DECLARE
    c record;
BEGIN
    FOR c IN
        SELECT * FROM (VALUES
            ('coin_transactions', 'coin_transactions_user_id_fkey', 'user_id',    'CASCADE'),
            ('feedback',          'feedback_user_id_fkey',          'user_id',    'SET NULL'),
            ('guardianship',      'guardianship_parent_id_fkey',    'parent_id',  'CASCADE'),
            ('guardianship',      'guardianship_student_id_fkey',   'student_id', 'CASCADE'),
            ('refresh_tokens',    'refresh_tokens_user_id_fkey',    'user_id',    'CASCADE'),
            ('submissions',       'submissions_user_id_fkey',       'user_id',    'CASCADE'),
            ('user_progress',     'user_progress_user_id_fkey',     'user_id',    'CASCADE')
        ) AS t(tbl, con, col, act)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = c.con
        ) THEN
            EXECUTE format(
                'ALTER TABLE public.%I ADD CONSTRAINT %I '
                'FOREIGN KEY (%I) REFERENCES public.users(id) ON DELETE %s',
                c.tbl, c.con, c.col, c.act);
            RAISE NOTICE 'qo''shildi: %', c.con;
        ELSE
            RAISE NOTICE 'allaqachon bor: %', c.con;
        END IF;
    END LOOP;
END $$;

COMMIT;

-- ---- 3. Natija --------------------------------------------------------------
SELECT conrelid::regclass AS jadval, conname
  FROM pg_constraint
 WHERE contype = 'f'
   AND confrelid = 'public.users'::regclass
 ORDER BY 1, 2;
