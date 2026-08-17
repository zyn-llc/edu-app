CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;      
CREATE TABLE languages (
    code        text PRIMARY KEY,           
    name        text NOT NULL,
    is_active   boolean NOT NULL DEFAULT true
);


CREATE TABLE regions (
    code        text PRIMARY KEY,           
    name        text NOT NULL
);


CREATE TABLE subjects (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    code        text NOT NULL UNIQUE,       
    icon        text,                        
    image_url   text,                        
    sort_order  int  NOT NULL DEFAULT 0,
    is_active   boolean NOT NULL DEFAULT true
);

CREATE TABLE subject_translations (
    subject_id  uuid NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
    lang        text NOT NULL REFERENCES languages(code),
    name        text NOT NULL,
    PRIMARY KEY (subject_id, lang)
);

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

CREATE TABLE questions (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    subject_id      uuid NOT NULL REFERENCES subjects(id),
    topic_id        uuid REFERENCES topics(id),
    grade           smallint,                       
    exam_context    text[],                          
    type            text NOT NULL DEFAULT 'mcq',
    difficulty      smallint NOT NULL DEFAULT 2,     
    max_score       int  NOT NULL DEFAULT 1,
    status          text NOT NULL DEFAULT 'active',  
    schema_version  int  NOT NULL DEFAULT 1,
    grading_spec    jsonb NOT NULL,                 
    media           jsonb,                           
    tags            jsonb,                           
    source_ref      text,                          
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
    explanation text,                                
    PRIMARY KEY (question_id, lang)
);

CREATE TABLE options (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    question_id uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    option_key  text NOT NULL,               
    position    int  NOT NULL DEFAULT 0,
    side        text,                          
    media_url   text,
    UNIQUE (question_id, option_key)
);

CREATE TABLE option_translations (
    option_id   uuid NOT NULL REFERENCES options(id) ON DELETE CASCADE,
    lang        text NOT NULL REFERENCES languages(code),
    text        text NOT NULL,
    PRIMARY KEY (option_id, lang)
);


CREATE TABLE users (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    role            text NOT NULL DEFAULT 'student',  
    phone           text UNIQUE,                       
    display_name    text,
    region_code     text REFERENCES regions(code),
    grade           smallint,
    locale          text REFERENCES languages(code) DEFAULT 'uz-Latn',
    password_hash   text,                             
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE guardianship (
    parent_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    student_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (parent_id, student_id)
);


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
    competition_id  uuid,                            
    payload         jsonb NOT NULL,           
    score           int  NOT NULL,
    max_score       int  NOT NULL,
    is_correct      boolean NOT NULL,
    response_ms     int,                       
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_submissions_user_q ON submissions (user_id, question_id);


CREATE TABLE competitions (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    subject_id      uuid REFERENCES subjects(id),
    title           text NOT NULL,
    mode            text NOT NULL DEFAULT 'live',  -- 'live'|'async'
    starts_at       timestamptz NOT NULL,
    ends_at         timestamptz NOT NULL,
    entry_fee_uzs   int  NOT NULL DEFAULT 0,
    prize_pool_uzs  int  NOT NULL DEFAULT 0,
    status          text NOT NULL DEFAULT 'scheduled', d
    config          jsonb,                          
    created_at      timestamptz NOT NULL DEFAULT now()
);


CREATE TABLE leaderboard_history (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    board_key   text NOT NULL,                  
    captured_at timestamptz NOT NULL DEFAULT now(),
    standings   jsonb NOT NULL                 
);

CREATE TABLE transactions (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         uuid NOT NULL REFERENCES users(id),
    competition_id  uuid REFERENCES competitions(id),
    provider        text NOT NULL,             
    provider_ref    text,                       
    amount_uzs      int  NOT NULL,
    state           text NOT NULL DEFAULT 'created',
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_ref)             
);

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
    question_ids  uuid[] NOT NULL,               
    status        text NOT NULL DEFAULT 'pending', 
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
    code        text PRIMARY KEY,              
    criteria    jsonb NOT NULL                  
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
