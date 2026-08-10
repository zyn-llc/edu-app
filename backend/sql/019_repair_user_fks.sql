-- =============================================================================
--
--
--      coin_transactions_user_id_fkey   feedback_user_id_fkey
--      guardianship_parent_id_fkey      guardianship_student_id_fkey
--      refresh_tokens_user_id_fkey      submissions_user_id_fkey
--      user_progress_user_id_fkey
--
--  chiqadi.
--
--  umuman tegilmaydi.
--
-- =============================================================================

BEGIN;

-- ---- 1. Yetim qatorlarni tozalash ------------------------------------------
DELETE FROM submissions       WHERE user_id   NOT IN (SELECT id FROM users);
DELETE FROM coin_transactions WHERE user_id   NOT IN (SELECT id FROM users);
DELETE FROM user_progress     WHERE user_id   NOT IN (SELECT id FROM users);
DELETE FROM refresh_tokens    WHERE user_id   NOT IN (SELECT id FROM users);
DELETE FROM guardianship      WHERE parent_id NOT IN (SELECT id FROM users)
                                 OR student_id NOT IN (SELECT id FROM users);

UPDATE feedback SET user_id = NULL
 WHERE user_id IS NOT NULL AND user_id NOT IN (SELECT id FROM users);

-- ---- 2. Cheklovlarni qaytarish ---------------------------------------------
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
