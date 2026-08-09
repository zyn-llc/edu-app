-- =========================================================================
--  024_referral.sql — "Do'stlaringizni taklif qiling" uchun kuzatuv ustuni
-- =========================================================================
--
--  NEGA. Sinovchi so'radi: "invite friends" funksiyasi qayerda? Bunday
--  umumiy (bellashuvga emas, ilovaning o'ziga) taklif havolasi yo'q edi —
--  faqat 1v1 bellashuv uchun `?join=KOD` bor edi.
--
--  MUKOFOTSIZ, ATAYLAB. Coin economy'ning yopiq halqa printsipiga zid
--  bo'lmasligi kerak: "do'stingni taklif qil — tanga ol" darhol soxta
--  hisoblar (bitta odam o'n marta o'zi-o'ziga taklif) ochish stimulini
--  yaratadi — xuddi shu sabab bilan biz parol bilan ro'yxatdan o'tishga
--  taklif kodini majburiy qildik (023-dan keyingi sessiya). Mukofot
--  mexanikasi puxta o'ylab chiqilgandan keyin (masalan, faqat ikkinchi
--  tomon birinchi mashqni tugatgandan KEYIN) qo'shiladi.
--
--  Hozircha faqat KUZATUV: kim kimni taklif qilgani saqlanadi, shuning
--  uchun admin qaysi taklif havolalari haqiqatan ishlayotganini ko'ra
--  oladi (`/v1/admin/stats`). `referred_by` — taklif qilgan foydalanuvchi
--  nomi (username), FK EMAS: referrer keyin nomini o'chira olmaydi
--  (username_locked), lekin extra JOIN talab qilmasin va referrer hisobi
--  keyinchalik o'chirilib qolsa ham (hozircha o'chirish funksiyasi yo'q,
--  lekin kelajakka moslashuvchan) statistika buzilmasin — shuning uchun
--  qiymat SNAPSHOT sifatida saqlanadi, bog'lanish emas.
-- =========================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by TEXT;

-- Faqat referral bo'yicha statistika so'roviga tez javob berish uchun.
CREATE INDEX IF NOT EXISTS ix_users_referred_by
    ON users (referred_by) WHERE referred_by IS NOT NULL;
