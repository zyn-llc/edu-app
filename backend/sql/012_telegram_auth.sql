-- =============================================================================
--  012_telegram_auth.sql — Telegram orqali kirish.
--
--    Get-Content sql/012_telegram_auth.sql | docker compose exec -T db psql -U edu -d edu
--
--
--  telegram_id bigint: Telegram ID'lari 2^31 dan oshib ketgan, integer yetmaydi.
-- =============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS telegram_id bigint;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_telegram_id
    ON users (telegram_id) WHERE telegram_id IS NOT NULL;

SELECT
    count(*)                                        AS jami,
    count(*) FILTER (WHERE phone IS NOT NULL)       AS telefon_bilan,
    count(*) FILTER (WHERE telegram_id IS NOT NULL) AS telegram_bilan,
    count(*) FILTER (WHERE phone IS NULL AND telegram_id IS NULL) AS taklif_kodi_bilan
FROM users;
