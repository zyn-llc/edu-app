-- =============================================================================
--  026_coin_integrity.sql — noncoin daftarining strukturaviy qo'riqchilari.
--
--  005 va 008 "bir marta" qoidasini `quiz_reward` va `daily_login` uchun
--  INDEKSGA qo'ygan edi — bu to'g'ri yondashuv, chunki indeks kod qanday
--  chaqirilishidan qat'i nazar ishlaydi. Bellashuv hisob-kitobi esa shu
--  himoyasiz qolgan edi:
--
--    `_lazy_expire` muddati o'tgan bellashuvni O'QISH yo'lida ham
--    ({GET /v1/challenges} va {GET /v1/challenges/{id}/questions}) qaytarim
--    yozadi, lekin u yerda satr LOCK QILINMAGAN. Parallel ikkita GET
--    ikkalasi ham `status='open'` ni o'qib, ikkalasi ham qaytarim yozardi.
--    500 noncoinlik garov 20 ta parallel so'rov bilan 10 000 ga aylanardi.
--
--  Ikkinchi qo'riqchi — belgi (sign) tekshiruvi. `credit()` va `spend()` da
--  Python darajasidagi tekshiruv bor, lekin bitta noto'g'ri chaqiruv (masalan
--  `spend` o'rniga `credit` bilan `challenge_stake`) iqtisodiyotni jimgina
--  ag'darib yuborardi.
--
--    ./scripts/migrate.sh
--
--  DIQQAT: agar duplikatlar allaqachon bo'lsa, birinchi CREATE yiqiladi —
--  bu ATAYLAB. Avval ularni ko'r:
--    SELECT user_id, reason, ref_id, count(*)
--      FROM coin_transactions
--     WHERE reason IN ('challenge_refund','challenge_win')
--     GROUP BY 1,2,3 HAVING count(*) > 1;
-- =============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_coin_challenge_settle
    ON coin_transactions (user_id, reason, ref_id)
    WHERE reason IN ('challenge_refund', 'challenge_win');

ALTER TABLE coin_transactions DROP CONSTRAINT IF EXISTS coin_sign_ck;
ALTER TABLE coin_transactions ADD CONSTRAINT coin_sign_ck CHECK (
    (amount > 0 AND reason IN (
        'quiz_reward', 'streak_bonus', 'daily_ad_reward', 'purchase',
        'daily_login', 'challenge_win', 'challenge_refund'))
 OR (amount < 0 AND reason IN (
        'competition_entry', 'cosmetic', 'badge', 'challenge_stake',
        'quiz_penalty'))
);

-- Analitika va `daily_breakdown` `created_at` bo'yicha filtrlaydi, `/v1/me`
-- esa har ochilishda foydalanuvchining butun tarixini o'qiydi. 001 dagi
-- (user_id, question_id) indeksi bularning hech biriga yaramaydi.
CREATE INDEX IF NOT EXISTS idx_submissions_created
    ON submissions (created_at);
CREATE INDEX IF NOT EXISTS idx_submissions_user_created
    ON submissions (user_id, created_at DESC);

-- Tekshirish:
--   SELECT conname FROM pg_constraint WHERE conname = 'coin_sign_ck';
--   SELECT indexname FROM pg_indexes
--    WHERE indexname IN ('uq_coin_challenge_settle',
--                        'idx_submissions_created',
--                        'idx_submissions_user_created');
