-- 022: foydalanuvchi nomi + parol bilan kirish
--
-- NEGA. Hozirgi uch yo'l ham "har safar qaytadan" hissini beradi:
--   * telefon+OTP — prodda o'chirilgan (Eskiz moderatsiyada),
--   * taklif kodi — bir martalik, qayta kirishga yaramaydi,
--   * Telegram   — ishlaydi, lekin har kirishda brauzerdan Telegram'ga o'tish,
--                  «Start» bosish va qaytish kerak. Foydalanuvchi buni har
--                  safar YANGI ro'yxatdan o'tish deb qabul qiladi.
--
-- Parol bu muammoni yopadi: bitta ekran, ikkita maydon, tashqi ilova yo'q.
--
-- `password_hash` ustuni 001 dan beri bor edi (admin hisoblari uchun), shu
-- sababli bu yerda faqat `username` qo'shiladi.
--
-- KATTA-KICHIK HARF. Foydalanuvchi «Zizu» deb yozib qo'yib, keyin «zizu» deb
-- kirmoqchi bo'ladi. Shu sababli noyoblik `lower(username)` bo'yicha
-- indekslanadi va qidiruv ham `lower()` bilan boradi. Ustunning o'zida
-- foydalanuvchi yozgani saqlanadi (profilda chiroyli ko'rinsin).

ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(20);

-- Faqat NOT NULL qatorlar indeksga tushadi: `username` yo'q hisoblar
-- (Telegram, taklif kodi) cheklovga umuman aralashmaydi.
CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_uq
    ON users (lower(username))
    WHERE username IS NOT NULL;

-- Ruxsat etilgan shakl serverda ham tekshiriladi, lekin bazada ham
-- qulflanadi: kelajakda boshqa yo'ldan yozilib qolmasin.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'users_username_shape'
    ) THEN
        ALTER TABLE users ADD CONSTRAINT users_username_shape
            CHECK (username IS NULL OR username ~ '^[A-Za-z0-9_]{3,20}$');
    END IF;
END $$;
