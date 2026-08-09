-- =============================================================================
--  028_notifications.sql — Telegram orqali qaytarish xabarlari.
--
--  NEGA KERAK. Ilovada streak, kunlik bonus, haftalik chiziq va bellashuv bor —
--  ya'ni qaytish uchun SABAB bor. Lekin qaytishga UNDAYDIGAN narsa yo'q edi:
--  do'sti bellashuvga chorlaganini o'quvchi faqat ilovani o'zi ochsa bilardi.
--  Yagona haqiqiy viral halqa jim turardi.
--
--  Kanal — Telegram, chunki u allaqachon ulangan: `users.telegram_id` bor,
--  bot bor, `services/telegram.send_message` bor. Push uchun FCM, sertifikat
--  va do'kon sozlamalari kerak bo'lardi; Telegram esa bugun ishlaydi.
--
--  JADVAL NIMA UCHUN. Faqat "yubordim" faktini yozish uchun. Usiz sutkalik
--  skript har safar bir xil xabarni qayta yuborardi — va spam eng tez
--  o'chiriladigan bot sababidir.
--
--    ./scripts/migrate.sh
-- =============================================================================

CREATE TABLE IF NOT EXISTS notifications (
    user_id     uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind        text        NOT NULL,
    -- Nimaga tegishli: bellashuv id si, yoki sana ('YYYY-MM-DD') — takror
    -- yubormaslik kaliti shu.
    ref_id      text        NOT NULL,
    sent_at     timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT notification_kind_ck CHECK (kind IN (
        'challenge_invite',    -- do'sting seni chorladi
        'challenge_expiring',  -- bellashuv muddati tugayapti
        'challenge_result',    -- raqib o'ynadi, natija tayyor
        'streak_at_risk'       -- seriya bugun uziladi
    )),

    -- "Bir xabar — bir marta" qoidasi INDEKSDA, skriptda emas. Skript ikki
    -- marta ishga tushsa (cron takrorlansa, qo'lda ishga tushirilsa) ikkinchi
    -- INSERT rad etiladi va xabar yuborilmaydi.
    PRIMARY KEY (user_id, kind, ref_id)
);

-- "Bu foydalanuvchiga bugun nima yubordik" — kunlik chegara uchun.
CREATE INDEX IF NOT EXISTS idx_notifications_user_sent
    ON notifications (user_id, sent_at DESC);

-- Xabarlarni butunlay o'chirish imkoniyati. NULL = hali tanlamagan (= yoqilgan):
-- mavjud foydalanuvchilarni migratsiya paytida jim ravishda o'chirib
-- qo'ymaslik uchun standart `true` emas, NULL.
ALTER TABLE users ADD COLUMN IF NOT EXISTS tg_notifications boolean;

-- Tekshirish:
--   \d notifications
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name='users' AND column_name='tg_notifications';
