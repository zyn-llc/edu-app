-- =============================================================================
--  025_challenge_lock_index.sql
--
--
--  bellashuvlar unga umuman tushmaydi.
--
--    ./scripts/migrate.sh
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_challenges_active_participants
    ON challenges (creator_id, opponent_id)
    WHERE status = 'active';

--   EXPLAIN SELECT 1 FROM challenges c
--    WHERE c.status = 'active'
--      AND (c.creator_id = '00000000-0000-0000-0000-000000000001'
--           OR c.opponent_id = '00000000-0000-0000-0000-000000000001');
