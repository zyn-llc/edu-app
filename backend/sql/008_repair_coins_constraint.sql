-- =============================================================================
--  008_repair_coins_constraint.sql — self-healing repair.
--
--  Root cause found 2026-07-07: on the dev machine, 006b's content overwrote
--  006_challenges.sql, so the coin_reason_ck ALTER (new economy-v2 reasons) and
--  the daily-login unique index never ran. Result: any logged-in user answering
--  WRONG with balance > 0 triggered a CHECK violation -> HTTP 500 -> the app's
--  "Yuborilmadi" error. (Reproduced end-to-end before writing this fix.)
--
--  This migration is IDEMPOTENT and state-independent: it produces the correct
--  end state whether 005, 006, 006b, all, or any mix ran before it. Safe to run
--  on every deploy.
--
--    docker compose exec -T db psql -U edu -d edu < sql/008_repair_coins_constraint.sql
-- =============================================================================

ALTER TABLE coin_transactions DROP CONSTRAINT IF EXISTS coin_reason_ck;
ALTER TABLE coin_transactions ADD CONSTRAINT coin_reason_ck CHECK (reason IN (
    -- earn (+)
    'quiz_reward', 'streak_bonus', 'daily_ad_reward', 'purchase',
    'daily_login', 'challenge_win', 'challenge_refund',
    -- spend (-)
    'competition_entry', 'cosmetic', 'badge', 'challenge_stake',
    'quiz_penalty'
));

CREATE UNIQUE INDEX IF NOT EXISTS uq_coin_daily_login
    ON coin_transactions (user_id, ref_id)
    WHERE reason = 'daily_login';

-- Verification (prints the constraint so a wrong state is visible immediately):
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint WHERE conname = 'coin_reason_ck';
