-- =============================================================================
--  011_invite_codes.sql — telefonsiz kirish (yopiq beta).
--
--    Get-Content sql/011_invite_codes.sql | docker compose exec -T db psql -U edu -d edu
--
--  Nega: Eskiz shabloni moderatsiyada turganda ham 30 ta sinovchi ilovaga
--
--
-- =============================================================================

CREATE TABLE IF NOT EXISTS invite_codes (
    code        text PRIMARY KEY
                CHECK (code = upper(code) AND code ~ '^[A-Z0-9]{6,16}$'),
    label       text,                       -- "10-maktab 9-A", "Ustoz markazi"
    max_uses    integer NOT NULL DEFAULT 1 CHECK (max_uses >= 1),
    used_count  integer NOT NULL DEFAULT 0 CHECK (used_count >= 0),
    grade       smallint,                   -- to'ldirilsa yangi akkauntga yoziladi
    region_code text,
    is_active   boolean NOT NULL DEFAULT true,
    expires_at  timestamptz,                -- NULL = muddatsiz
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS invite_redemptions (
    code       text NOT NULL REFERENCES invite_codes(code) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (code, user_id)
);

CREATE INDEX IF NOT EXISTS idx_invite_redemptions_user
    ON invite_redemptions (user_id);

--     python scripts/make_invites.py --count 5 --uses 10 --label "Beta"
--
-- INSERT INTO invite_codes (code, label, max_uses, expires_at)
-- VALUES ('BETA2026', 'Yopiq beta', 50, now() + interval '30 days');

SELECT code, label, used_count || '/' || max_uses AS ishlatilgan, is_active
FROM invite_codes ORDER BY created_at DESC;
