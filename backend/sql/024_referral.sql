-- =========================================================================
-- =========================================================================
--
--  NEGA. Sinovchi so'radi: "invite friends" funksiyasi qayerda? Bunday
--
--  MUKOFOTSIZ, ATAYLAB. Coin economy'ning yopiq halqa printsipiga zid
--
-- =========================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by TEXT;

CREATE INDEX IF NOT EXISTS ix_users_referred_by
    ON users (referred_by) WHERE referred_by IS NOT NULL;
