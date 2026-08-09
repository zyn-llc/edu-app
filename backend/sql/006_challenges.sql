-- =============================================================================
--  006b_challenges_fix.sql — replace the OLD draft challenges table.
--
--  001_init.sql shipped an early-design `challenges` table (challenger_id /
--  challengee_id, no stake, no invite code). 006 used CREATE TABLE IF NOT
--  EXISTS, so on databases initialized from 001 the old table survived and the
--  new indexes failed ("column creator_id does not exist"). This migration
--  drops the old draft (it was never written to by any endpoint) and recreates
--  the real schema. challenge_results is recreated too so its FK points at the
--  new table.
--
--    docker compose exec -T db psql -U edu -d edu < sql/006b_challenges_fix.sql
--
--  Safe to re-run. NOT safe on a DB with live challenge data — by the time such
--  a DB exists, this migration has already been applied.
-- =============================================================================

DROP TABLE IF EXISTS challenge_results;
DROP TABLE IF EXISTS challenges CASCADE;

CREATE TABLE challenges (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    code            text NOT NULL UNIQUE,
    creator_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    opponent_id     uuid REFERENCES users(id) ON DELETE SET NULL,
    subject_id      uuid NOT NULL REFERENCES subjects(id),
    grade           smallint,
    question_count  integer NOT NULL,
    stake           integer NOT NULL CHECK (stake >= 0),
    question_ids    uuid[] NOT NULL,
    status          text NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open','active','done','cancelled','expired')),
    creator_score   integer,
    opponent_score  integer,
    winner_id       uuid REFERENCES users(id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    expires_at      timestamptz NOT NULL
);

CREATE INDEX idx_challenges_creator ON challenges (creator_id, created_at DESC);
CREATE INDEX idx_challenges_opponent ON challenges (opponent_id, created_at DESC);

CREATE TABLE challenge_results (
    challenge_id  uuid NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    score         integer NOT NULL,
    max_score     integer NOT NULL,
    detail        jsonb,
    created_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (challenge_id, user_id)
);
