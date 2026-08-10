-- =============================================================================
--  028_notifications.sql — Telegram orqali qaytarish xabarlari.
--
--  Yagona haqiqiy viral halqa jim turardi.
--
--
--
--    ./scripts/migrate.sh
-- =============================================================================

CREATE TABLE IF NOT EXISTS notifications (
    user_id     uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind        text        NOT NULL,
    -- Nimaga tegishli: bellashuv id si, yoki sana ('YYYY-MM-DD') — takror
    ref_id      text        NOT NULL,
    sent_at     timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT notification_kind_ck CHECK (kind IN (
        'challenge_invite',    -- do'sting seni chorladi
        'challenge_expiring',  -- bellashuv muddati tugayapti
        'challenge_result',    -- raqib o'ynadi, natija tayyor
        'streak_at_risk'       -- seriya bugun uziladi
    )),

    -- INSERT rad etiladi va xabar yuborilmaydi.
    PRIMARY KEY (user_id, kind, ref_id)
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_sent
    ON notifications (user_id, sent_at DESC);

ALTER TABLE users ADD COLUMN IF NOT EXISTS tg_notifications boolean;

--   \d notifications
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name='users' AND column_name='tg_notifications';
