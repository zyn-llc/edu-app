-- =============================================================================
--  011_invite_codes.sql — telefonsiz kirish (yopiq beta).
--
--    Get-Content sql/011_invite_codes.sql | docker compose exec -T db psql -U edu -d edu
--
--  Nega: Eskiz shabloni moderatsiyada turganda ham 30 ta sinovchi ilovaga
--  kira olishi kerak. `users.phone` allaqachon NULL bo'lishi mumkin va UNIQUE
--  (001_init.sql:163), shuning uchun users jadvaliga tegilmaydi.
--
--  Ikki xil ishlatish:
--    * max_uses = 1  -> shaxsiy kod. Kim kirganini aniq bilasan.
--    * max_uses = 40 -> bitta o'quv markazi uchun bitta kod. Amalda tezroq.
--
--  Kod formati: 8 ta belgi, chalkash harflarsiz (0/O, 1/I/L yo'q).
--  Klientga `K7M4-X9QP` ko'rinishida ko'rsatiladi, bazada `K7M4X9QP`.
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

-- Kim qaysi kod bilan kirgani. Bittalik kod uchun ham yozamiz: keyin
-- "qaysi markazdan kelgan o'quvchi qancha qoldi" degan savolga javob shu yerda.
CREATE TABLE IF NOT EXISTS invite_redemptions (
    code       text NOT NULL REFERENCES invite_codes(code) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (code, user_id)
);

CREATE INDEX IF NOT EXISTS idx_invite_redemptions_user
    ON invite_redemptions (user_id);

-- ---- namuna: bitta guruh kodi ----------------------------------------------
-- Kodlarni qo'lda emas, scripts/make_invites.py orqali generatsiya qil:
--     python scripts/make_invites.py --count 5 --uses 10 --label "Beta"
--
-- INSERT INTO invite_codes (code, label, max_uses, expires_at)
-- VALUES ('BETA2026', 'Yopiq beta', 50, now() + interval '30 days');

-- ---- tekshiruv --------------------------------------------------------------
SELECT code, label, used_count || '/' || max_uses AS ishlatilgan, is_active
FROM invite_codes ORDER BY created_at DESC;
