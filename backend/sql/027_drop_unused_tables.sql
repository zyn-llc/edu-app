-- =============================================================================
--
--          ./scripts/backup.sh
--
--
--                        ataylab pulga aylanmaydi (005_coins.sql izohi)
--
--  o'qigan odam mahsulotda musobaqa, to'lov va do'stlar bor deb o'ylaydi.
--
--
--
--    ./scripts/backup.sh && ./scripts/migrate.sh
-- =============================================================================

DO $$
DECLARE
    t    text;
    n    bigint;
    tabs text[] := ARRAY['user_badges', 'badges', 'friendships',
                         'transactions', 'competitions'];
BEGIN
    FOREACH t IN ARRAY tabs LOOP
        IF to_regclass('public.' || t) IS NULL THEN
            RAISE NOTICE '% — allaqachon yo''q, o''tkazib yuborildi', t;
            CONTINUE;
        END IF;

        EXECUTE format('SELECT count(*) FROM %I', t) INTO n;
        IF n > 0 THEN
            RAISE EXCEPTION
                '% jadvalida % ta qator bor — o''chirilmadi. Uni ko''rib chiq: SELECT * FROM %I LIMIT 20;',
                t, n, t;
        END IF;

        EXECUTE format('DROP TABLE %I CASCADE', t);
        RAISE NOTICE '% o''chirildi (bo''sh edi)', t;
    END LOOP;
END $$;

-- borligini hech kim tushuntira olmaydi.
ALTER TABLE submissions DROP COLUMN IF EXISTS competition_id;

--   \dt
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'submissions' ORDER BY 1;
