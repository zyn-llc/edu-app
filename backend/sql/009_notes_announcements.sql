-- =============================================================================
--  009_notes_announcements.sql — daftar (notes) + yangiliklar (announcements).
--
--    Get-Content sql/009_notes_announcements.sql | docker compose exec -T db psql -U edu -d edu
--
-- =============================================================================

-- ---- notes ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notes (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    question_id uuid REFERENCES questions(id) ON DELETE SET NULL,
    subject_id  uuid REFERENCES subjects(id) ON DELETE SET NULL,
    title       text,
    body        text NOT NULL CHECK (length(body) BETWEEN 1 AND 8000),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notes_user_updated
    ON notes (user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_notes_user_question
    ON notes (user_id, question_id) WHERE question_id IS NOT NULL;

-- ---- announcements ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS announcements (
    id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    kind         text NOT NULL DEFAULT 'news'
                 CHECK (kind IN ('news','update','maintenance','promo')),
    grade        smallint,          -- NULL = hamma sinflarga
    is_active    boolean NOT NULL DEFAULT true,
    published_at timestamptz NOT NULL DEFAULT now(),   -- kelajak sana = rejalashtirilgan
    expires_at   timestamptz,       -- NULL = muddatsiz
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS announcement_translations (
    announcement_id uuid NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
    lang            text NOT NULL,
    title           text NOT NULL,
    body            text NOT NULL,
    PRIMARY KEY (announcement_id, lang)
);

-- Feed so'rovi: aktiv + allaqachon chiqqan + muddati o'tmagan, yangisi tepada.
CREATE INDEX IF NOT EXISTS idx_announcements_feed
    ON announcements (is_active, published_at DESC);

--
-- WITH a AS (
--   INSERT INTO announcements (kind, published_at)
--   VALUES ('news', now()) RETURNING id
-- )
-- INSERT INTO announcement_translations (announcement_id, lang, title, body)
-- SELECT id, 'uz', 'Bilim ishga tushdi!',
-- UNION ALL
-- SELECT id, 'ru', 'Bilim запущен!',
--        'Более 14 000 вопросов, 9 предметов. Удачи!' FROM a;

SELECT 'notes' AS jadval, count(*) FROM notes
UNION ALL
SELECT 'announcements', count(*) FROM announcements;
