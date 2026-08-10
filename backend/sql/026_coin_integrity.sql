-- =============================================================================
--  026_coin_integrity.sql — noncoin daftarining strukturaviy qo'riqchilari.
--
--  himoyasiz qolgan edi:
--
--    `_lazy_expire` muddati o'tgan bellashuvni O'QISH yo'lida ham
--    ({GET /v1/challenges} va {GET /v1/challenges/{id}/questions}) qaytarim
--
--  ag'darib yuborardi.
--
--    ./scripts/migrate.sh
--
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
-- (user_id, question_id) indeksi bularning hech biriga yaramaydi.
CREATE INDEX IF NOT EXISTS idx_submissions_created
    ON submissions (created_at);
CREATE INDEX IF NOT EXISTS idx_submissions_user_created
    ON submissions (user_id, created_at DESC);

--   SELECT conname FROM pg_constraint WHERE conname = 'coin_sign_ck';
--   SELECT indexname FROM pg_indexes
--    WHERE indexname IN ('uq_coin_challenge_settle',
--                        'idx_submissions_created',
--                        'idx_submissions_user_created');
