-- 021: profil avatari.
--
--

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS avatar_color SMALLINT;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_avatar_color_range;

ALTER TABLE users
    ADD CONSTRAINT users_avatar_color_range
    CHECK (avatar_color IS NULL OR (avatar_color >= 0 AND avatar_color <= 11));
