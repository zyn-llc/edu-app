-- =========================================================================
-- =========================================================================
--
--
--
--
--  yarata oladi.
--
--
--      UPDATE challenges SET invite_used_at = now()
--       WHERE code = :code AND status = 'open'
--         AND expires_at > now() AND invite_used_at IS NULL
--      RETURNING id;
--
--
-- =========================================================================

BEGIN;

ALTER TABLE challenges
    ADD COLUMN IF NOT EXISTS invite_used_at timestamptz;

COMMENT ON COLUMN challenges.invite_used_at IS
    'Shu bellashuv kodi ro''yxatdan o''tish uchun ishlatilgan payt. '
    'NULL — hali ishlatilmagan. Bitta kod faqat BIR marta yaraydi.';

-- Ro'yxatdan o'tishdagi qidiruv `code` bo'yicha, u allaqachon UNIQUE —

COMMIT;

--   SELECT count(*) FROM challenges WHERE invite_used_at IS NOT NULL;  -- 0
