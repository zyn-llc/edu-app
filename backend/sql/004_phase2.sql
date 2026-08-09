-- =============================================================================
--  004_phase2.sql — indexes for the Phase 2 auth/ranking/parent paths.
--  Forward-only. Safe to run repeatedly (IF NOT EXISTS).
--
--  Run once against an existing database:
--    docker compose exec -T db psql -U edu -d edu < sql/004_phase2.sql
--
--  No new TABLES: 001_init.sql already defines users, refresh_tokens,
--  guardianship, and user_progress. Phase 2 only adds the indexes that its hot
--  lookups need.
-- =============================================================================

-- Every /v1/auth/refresh and /logout looks a token up by its hash. Without this
-- that's a full scan of refresh_tokens on each call.
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash
    ON refresh_tokens (token_hash);

-- Find a user's live tokens quickly (revoke-all / housekeeping).
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_active
    ON refresh_tokens (user_id)
    WHERE revoked_at IS NULL;

-- Reverse guardianship lookup (which parents are linked to this student).
-- parent -> children is already served by the PK (parent_id, student_id).
CREATE INDEX IF NOT EXISTS idx_guardianship_student
    ON guardianship (student_id);

-- Leaderboard name hydration / profile reads select users by id (PK, already
-- indexed) and submissions by user_id (idx_submissions_user_q from 001 covers it).

-- NOTE (DevOps): refresh_tokens grows monotonically. Add a periodic prune of rows
-- where expires_at < now() OR revoked_at < now() - interval '30 days'. Not a
-- migration concern; schedule it (cron / pg_cron) when staging is set up.
