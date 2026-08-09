-- =============================================================================
--  005_coins.sql — closed-loop coin ledger.
--  Forward-only. Idempotent (IF NOT EXISTS).
--    docker compose exec -T db psql -U edu -d edu < sql/005_coins.sql
--
--  DESIGN: coins are an append-only LEDGER, never a balance column. Balance is
--  SUM(amount). Every earn is +, every spend is -. There is deliberately NO
--  transaction reason that converts coins back to money (no cashout/withdraw/
--  transfer) — that absence is what keeps this a virtual play currency and NOT
--  e-money or gambling. Do not add such a reason without legal sign-off.
-- =============================================================================

CREATE TABLE IF NOT EXISTS coin_transactions (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount      integer NOT NULL,            -- signed: + earn, - spend
    reason      text    NOT NULL,            -- see allowed set below
    source      text    NOT NULL DEFAULT 'earned',  -- 'earned' | 'purchased'
    ref_type    text,                        -- 'question'|'competition'|'item'|'payment'
    ref_id      text,                        -- loose reference (e.g. question_id)
    created_at  timestamptz NOT NULL DEFAULT now(),

    -- Closed-loop guard: only known reasons; none of them move coins to money.
    CONSTRAINT coin_reason_ck CHECK (reason IN (
        'quiz_reward', 'streak_bonus', 'daily_ad_reward', 'purchase',  -- earn (+)
        'competition_entry', 'cosmetic', 'badge', 'challenge_stake'    -- spend (-)
    )),
    CONSTRAINT coin_source_ck CHECK (source IN ('earned', 'purchased'))
);

-- Balance + history reads: newest first per user.
CREATE INDEX IF NOT EXISTS idx_coin_tx_user
    ON coin_transactions (user_id, created_at DESC);

-- ANTI-FARM (structural): a given question can mint a quiz reward exactly once
-- per user. Even if the app races, the DB rejects the second insert — so XP/coins
-- can't be farmed by re-answering. XP award is gated on this insert succeeding.
CREATE UNIQUE INDEX IF NOT EXISTS uq_coin_quiz_reward
    ON coin_transactions (user_id, ref_id)
    WHERE reason = 'quiz_reward';
