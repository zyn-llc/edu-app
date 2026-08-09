-- =============================================================================
--  025_challenge_lock_index.sql
--
--  POST /v1/submissions endi har bir yuborishda so'raydi: "bu savol shu
--  foydalanuvchining yakunlanmagan bellashuvidami?". Usiz bellashuv kaliti
--  oddiy mashq orqali oldindan o'qib olinardi (kalit javobda qaytardi), ya'ni
--  garov qo'yilgan har bir bellashuv yutilardi.
--
--  Indekssiz bu tekshiruv `challenges` ni HAR YUBORISHDA to'liq skanlaydi.
--  Qisman indeks (`WHERE status = 'active'`) kichik qoladi: yopilgan
--  bellashuvlar unga umuman tushmaydi.
--
--    ./scripts/migrate.sh
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_challenges_active_participants
    ON challenges (creator_id, opponent_id)
    WHERE status = 'active';

-- Tekshirish: quyidagi so'rov `Index Scan` ko'rsatishi kerak, `Seq Scan` emas.
--   EXPLAIN SELECT 1 FROM challenges c
--    WHERE c.status = 'active'
--      AND (c.creator_id = '00000000-0000-0000-0000-000000000001'
--           OR c.opponent_id = '00000000-0000-0000-0000-000000000001');
