-- Run once against an existing database:
--   docker compose exec -T db psql -U edu -d edu < sql/003_app_support.sql

-- 1) Group subjects: exact sciences first, then humanities.
UPDATE subjects SET sort_order = CASE code
    WHEN 'matematika'        THEN 1
    WHEN 'geometriya'        THEN 2
    WHEN 'fizika'            THEN 3
    WHEN 'kimyo'             THEN 4
    WHEN 'biologiya'         THEN 5
    WHEN 'geografiya'        THEN 6
    WHEN 'ona_tili'          THEN 7
    WHEN 'jahon_tarixi'      THEN 8
    WHEN 'ozbekiston_tarixi' THEN 9
    WHEN 'huquq'             THEN 10
    ELSE sort_order END;

-- 2) Temporary "guest" user so practice submissions save before auth is built.
--    Replaced by the real JWT user once the auth module lands.
INSERT INTO users (id, role, display_name, locale)
VALUES ('00000000-0000-0000-0000-000000000001', 'student', 'Mehmon', 'uz-Latn')
ON CONFLICT (id) DO NOTHING;
