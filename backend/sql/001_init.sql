-- =============================================================================
--  Education Competition Platform — canonical schema  (v1)
-- =============================================================================
--  CORE PRINCIPLE (do not violate):
--    Answer keys live ONLY in questions.grading_spec and option correctness is
--    NEVER stored on a renderable row. The "options" table has no is_correct
--    column on purpose, so it is *structurally impossible* to leak a key by
--
--  EXTENSIBILITY (built in from day one, even though only MCQ exists now):
--    - question.type is text (app-validated), so adding 'matching', 'numeric',
--      'open_keyword', etc. is a data change, never a migration.
--    - All type-specific answer data lives in grading_spec JSONB — one shape per
--    - Multilingual via *_translations tables (uz-Latn, uz-Cyrl, ru, en, ...).
--      The "core" row is language-independent; text is in translations.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;      -- fuzzy text (search, dedup)
-- PostGIS is enabled on the Islamic platform; not required here. Region is a code.

-- ---------------------------------------------------------------------------
--  Reference / lookup
-- ---------------------------------------------------------------------------

-- Supported UI/content languages. Seeded, app reads this list.
CREATE TABLE languages (
    code        text PRIMARY KEY,           -- 'uz-Latn','uz-Cyrl','ru','en'
    name        text NOT NULL,
    is_active   boolean NOT NULL DEFAULT true
);

-- Regions drive one ranking dimension (rank by region).
CREATE TABLE regions (
    code        text PRIMARY KEY,           -- 'tashkent','samarkand',...
    name        text NOT NULL
);

-- ---------------------------------------------------------------------------
--  Subjects  (geografiya, jahon tarixi, ... — 10 at launch)
-- ---------------------------------------------------------------------------
CREATE TABLE subjects (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    code        text NOT NULL UNIQUE,       -- stable slug: 'geografiya'
    icon        text,                        -- asset key (small icon, optional)
    image_url   text,                        -- cover image (R2 key) for the grid tile
    sort_order  int  NOT NULL DEFAULT 0,
    is_active   boolean NOT NULL DEFAULT true
);

CREATE TABLE subject_translations (
    subject_id  uuid NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
    lang        text NOT NULL REFERENCES languages(code),
    name        text NOT NULL,
    PRIMARY KEY (subject_id, lang)
);

-- ---------------------------------------------------------------------------
--  Topics  (hierarchical: a subject -> topics; topics can nest)
--  Navigation (subject -> grade/topic/entrance) is METADATA-DRIVEN. The client
--  asks "what exists for this subject?" and renders a responsive grid from the
--  answer. Math has many topics, another subject few — same screen, no hardcode.
-- ---------------------------------------------------------------------------
CREATE TABLE topics (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    subject_id  uuid NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
    parent_id   uuid REFERENCES topics(id) ON DELETE CASCADE,
    code        text NOT NULL,               -- 'mavzu-1' (unique within subject)
    sort_order  int  NOT NULL DEFAULT 0,
    is_active   boolean NOT NULL DEFAULT true,
    UNIQUE (subject_id, code)
);

CREATE TABLE topic_translations (
    topic_id    uuid NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    lang        text NOT NULL REFERENCES languages(code),
    title       text NOT NULL,
    PRIMARY KEY (topic_id, lang)
);

-- ---------------------------------------------------------------------------
--  Questions  (the heart — extensible to every future type)
-- ---------------------------------------------------------------------------
--  Allowed type values (validated in the app layer, NOT a DB enum, so new
--  types ship without a migration):
--      'mcq'          single correct option
--      'multi_select' several correct options (exact set)
--      'numeric'      numeric answer with tolerance
--      'open_keyword' free text matched against accepted answers (Uzbek-aware)
--      'matching'     match left items to right items
--      'ordering'     put items in correct order
--      'open_text'    AI-graded essay/short answer  (rubric)   <-- later
--
--      mcq/multi_select : {"correct_option_ids": ["..."]}
--      numeric          : {"value": 3.14, "tolerance": 0.01, "unit": "km"}
--      open_keyword     : {"accepted": ["..."], "match": "any"}
--      matching         : {"pairs": [["L1","R1"], ["L2","R2"]]}
--      ordering         : {"order": ["A","B","C"]}
--      open_text        : {"rubric": "...", "max_points": 5}
-- ---------------------------------------------------------------------------
CREATE TABLE questions (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    subject_id      uuid NOT NULL REFERENCES subjects(id),
    topic_id        uuid REFERENCES topics(id),
    grade           smallint,                       -- 8, 9, 10, 11 ... nullable
    exam_context    text[],                          -- {'school','entrance'} — multi-value
    type            text NOT NULL DEFAULT 'mcq',
    difficulty      smallint NOT NULL DEFAULT 2,     -- 1..5, feeds adaptive picking
    max_score       int  NOT NULL DEFAULT 1,
    status          text NOT NULL DEFAULT 'active',  -- 'draft'|'active'|'retired'
    schema_version  int  NOT NULL DEFAULT 1,
    grading_spec    jsonb NOT NULL,                  -- *** SERVER ONLY ***
    media           jsonb,                           -- {"image_url": "...", ...} for image questions (later)
    tags            jsonb,                           -- {"skill_tags":[...],"concept_tags":[...],"subtopic":"..."}
    source_ref      text,                            -- 'geo-g10, p.143, Mavzu 4'
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_questions_nav
    ON questions (subject_id, grade, topic_id, exam_context)
    WHERE status = 'active';
CREATE INDEX idx_questions_type ON questions (type);

CREATE TABLE question_translations (
    question_id uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    lang        text NOT NULL REFERENCES languages(code),
    stem        text NOT NULL,
    explanation text,                                -- shown after answering
    PRIMARY KEY (question_id, lang)
);

-- ---------------------------------------------------------------------------
--  Options  (renderable choices for mcq / multi_select / matching / ordering)
--  *** NOTE: there is deliberately NO is_correct column. ***
--  Correctness is exclusively in questions.grading_spec, keyed by option_key.
-- ---------------------------------------------------------------------------
CREATE TABLE options (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    question_id uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    option_key  text NOT NULL,               -- stable id used by grading_spec: 'a','b'.. or 'L1','R1'
    position    int  NOT NULL DEFAULT 0,
    side        text,                          -- matching: 'left'|'right'; else null
    media_url   text,
    UNIQUE (question_id, option_key)
);

CREATE TABLE option_translations (
    option_id   uuid NOT NULL REFERENCES options(id) ON DELETE CASCADE,
    lang        text NOT NULL REFERENCES languages(code),
    text        text NOT NULL,
    PRIMARY KEY (option_id, lang)
);

-- ---------------------------------------------------------------------------
--  Users  (one table, role enum: student | parent | admin)
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    role            text NOT NULL DEFAULT 'student',  -- 'student'|'parent'|'admin'
    phone           text UNIQUE,                       -- phone+OTP auth (UZ)
    display_name    text,
    region_code     text REFERENCES regions(code),
    grade           smallint,
    locale          text REFERENCES languages(code) DEFAULT 'uz-Latn',
    password_hash   text,                              -- argon2, admins only
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- Parent <-> student link (read-only parent dashboards).
CREATE TABLE guardianship (
    parent_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    student_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (parent_id, student_id)
);

-- Rotating refresh tokens (hashed, revocable).
CREATE TABLE refresh_tokens (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  text NOT NULL,
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE submissions (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    question_id     uuid NOT NULL REFERENCES questions(id),
    competition_id  uuid,                            -- FK added after competitions (see end)
    payload         jsonb NOT NULL,           -- what the student submitted
    score           int  NOT NULL,
    max_score       int  NOT NULL,
    is_correct      boolean NOT NULL,
    response_ms     int,                       -- server-measured timing (anti-cheat)
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_submissions_user_q ON submissions (user_id, question_id);

-- ---------------------------------------------------------------------------
--  Competitions  (scheduled live events — phase 3, defined now for stability)
-- ---------------------------------------------------------------------------
CREATE TABLE competitions (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    subject_id      uuid REFERENCES subjects(id),
    title           text NOT NULL,
    mode            text NOT NULL DEFAULT 'live',  -- 'live'|'async'
    starts_at       timestamptz NOT NULL,
    ends_at         timestamptz NOT NULL,
    entry_fee_uzs   int  NOT NULL DEFAULT 0,
    prize_pool_uzs  int  NOT NULL DEFAULT 0,
    status          text NOT NULL DEFAULT 'scheduled', -- scheduled|open|running|grading|finished
    config          jsonb,                          -- {question_count, per_question_seconds, ...}
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- Snapshot of standings for history (Redis sorted sets are the live source).
CREATE TABLE leaderboard_history (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    board_key   text NOT NULL,                  -- 'lb:subject:geografiya' etc.
    captured_at timestamptz NOT NULL DEFAULT now(),
    standings   jsonb NOT NULL                  -- [{user_id, score, rank}, ...]
);

-- ---------------------------------------------------------------------------
--  Payments ledger  (Payme / Click — phase 3; client NEVER asserts payment)
-- ---------------------------------------------------------------------------
CREATE TABLE transactions (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         uuid NOT NULL REFERENCES users(id),
    competition_id  uuid REFERENCES competitions(id),
    provider        text NOT NULL,              -- 'payme'|'click'
    provider_ref    text,                       -- provider transaction id (idempotency)
    amount_uzs      int  NOT NULL,
    state           text NOT NULL DEFAULT 'created', -- created|pending|paid|refunded|failed
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_ref)              -- replayed webhook can't double-credit
);

-- ---------------------------------------------------------------------------
--  Social: friendships + async challenges  (phase 2)
-- ---------------------------------------------------------------------------
CREATE TABLE friendships (
    requester_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    addressee_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status       text NOT NULL DEFAULT 'pending', -- pending|accepted|blocked
    created_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (requester_id, addressee_id)
);

CREATE TABLE challenges (
    id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    challenger_id uuid NOT NULL REFERENCES users(id),
    challengee_id uuid NOT NULL REFERENCES users(id),
    question_ids  uuid[] NOT NULL,               -- frozen set: both play identical Qs
    status        text NOT NULL DEFAULT 'pending', -- pending|active|completed|expired
    challenger_score int,
    challengee_score int,
    expires_at    timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_progress (
    user_id     uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    xp          int  NOT NULL DEFAULT 0,
    level       int  NOT NULL DEFAULT 1,
    streak_days int  NOT NULL DEFAULT 0,
    last_active date,
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE badges (
    code        text PRIMARY KEY,               -- 'streak_7','first_win',...
    criteria    jsonb NOT NULL                  -- evaluated server-side
);

CREATE TABLE user_badges (
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    badge_code  text NOT NULL REFERENCES badges(code),
    earned_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, badge_code)
);

-- Deferred FK: submissions.competition_id (competitions is defined above this point).
ALTER TABLE submissions
    ADD CONSTRAINT fk_submissions_competition
    FOREIGN KEY (competition_id) REFERENCES competitions(id);
