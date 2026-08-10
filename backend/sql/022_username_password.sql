
ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(20);

CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_uq
    ON users (lower(username))
    WHERE username IS NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'users_username_shape'
    ) THEN
        ALTER TABLE users ADD CONSTRAINT users_username_shape
            CHECK (username IS NULL OR username ~ '^[A-Za-z0-9_]{3,20}$');
    END IF;
END $$;
