-- 021: profil avatari.
--
-- Rasm yuklash EMAS. Avatar = ism bosh harfi + foydalanuvchi tanlagan rang.
-- Sabab: fayl yuklash uchun obyekt saqlash (S3/MinIO), o'lcham o'zgartirish,
-- moderatsiya va CDN kerak — bularning hech biri hozir yo'q, deadline esa
-- 8-avgust. Bosh harf + rang foydalanuvchini reytingda va ota-ona panelida
-- ajratib turish uchun yetarli, xarajati esa bitta ustun.
--
-- Qiymat: 0..11 oralig'idagi palitra indeksi. Rang KODLARI klientda
-- (`lib/widgets/avatar.dart` — `AvatarPalette`), chunki ular temaga bog'liq:
-- qorong'i rejimda boshqa ottenka kerak. Bazada faqat indeks turadi.
-- NULL = hali tanlanmagan; klient ism hash'idan barqaror rang oladi.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS avatar_color SMALLINT;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_avatar_color_range;

ALTER TABLE users
    ADD CONSTRAINT users_avatar_color_range
    CHECK (avatar_color IS NULL OR (avatar_color >= 0 AND avatar_color <= 11));
