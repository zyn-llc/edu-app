-- =============================================================================
--  027_drop_unused_tables.sql — 001_init.sql dagi yozilmagan jadvallarni olib
--  tashlaydi.
--
--  ⚠️  BU MIGRATSIYA JADVAL O'CHIRADI. Qaytarib bo'lmaydi.
--      ISHGA TUSHIRISHDAN OLDIN ZAXIRA OL:
--          ./scripts/backup.sh
--
--  NEGA. 001_init.sql loyihaning BOSHIDA, mahsulot qanday bo'lishi
--  rejalashtirilganiga qarab yozilgan. Quyidagi jadvallarga hech qachon
--  birorta ham INSERT yozilmagan va ular birorta ham kodda ishlatilmaydi:
--
--      competitions      musobaqa moduli yozilmadi — uning o'rniga
--                        `challenges` (1v1 bellashuv) qilindi
--      transactions      to'lov moduli yo'q, va bo'lmaydi ham: noncoin
--                        ataylab pulga aylanmaydi (005_coins.sql izohi)
--      friendships       do'stlik grafi yo'q — bellashuv kod orqali ishlaydi
--      badges            nishonlar tizimi yozilmadi
--      user_badges       ↑ shu bilan birga
--
--  Bo'sh jadval zararsizdek tuyuladi, lekin u yolg'on hujjat: sxemani
--  o'qigan odam mahsulotda musobaqa, to'lov va do'stlar bor deb o'ylaydi.
--
--  `leaderboard_history` O'CHIRILMAYDI — u reyting snapshot'i uchun kerak
--  bo'ladi (reyting hozir faqat Redis'da yashaydi, ya'ni volume yo'qolsa
--  butunlay yo'qoladi).
--
--  TEKSHIRUV. Migratsiya jadval BO'SH ekaniga ishonch hosil qilmaguncha
--  o'chirmaydi: agar biror sababdan ma'lumot bo'lsa, `RAISE EXCEPTION`
--  bilan to'xtaydi va sen buni qo'lda ko'rasan.
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

-- `submissions.competition_id` — endi hech qachon to'ldirilmaydigan ustun.
-- FK `competitions` bilan birga CASCADE orqali ketadi; ustunning o'zi ham
-- ketishi kerak, aks holda ORM'dagi `Submission.competition_id` ni nima uchun
-- borligini hech kim tushuntira olmaydi.
ALTER TABLE submissions DROP COLUMN IF EXISTS competition_id;

-- Tekshirish:
--   \dt
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'submissions' ORDER BY 1;
