CREATE TABLE IF NOT EXISTS feedback (
    id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id      uuid REFERENCES users(id) ON DELETE SET NULL,  -- NULL = guest
    message      text NOT NULL,
    contact      text,             -- optional phone/telegram the user typed
    app_version  text,
    status       text NOT NULL DEFAULT 'new' CHECK (status IN ('new','seen')),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_feedback_status ON feedback (status, created_at DESC);
