/* =========================================================================
   flutter_service_worker.js — O'Z-O'ZINI O'CHIRUVCHI service worker
   =========================================================================

   MUAMMO (2026-08-06 da sinovda aniqlangan).

   Flutter Web standart holda service worker yaratadi va u butun ilovani
   keshlaydi. Natijada yangi build serverga chiqqanidan keyin ham
   foydalanuvchi ESKI versiyani ko'raveradi:

     * `Ctrl+Shift+R` yordam bermaydi — SW so'rovni tarmoqqa umuman
       o'tkazmaydi, keshdan javob beradi;
     * yangi SW o'rnatiladi, lekin u faqat BARCHA tablar yopilgandan keyin
       faollashadi ("waiting" holati);
     * ya'ni sinovchi ilovani ochiq qoldirsa, u yangilanishni umuman
       ko'rmaydi.

   30 ta sinovchi va kuniga bir necha marta yangilanadigan beta uchun bu
   qabul qilib bo'lmaydigan holat: har tuzatishdan keyin har bir odamga
   "keshni tozalang" deb aytish kerak bo'lardi.

   YECHIM.

   1. Build `--pwa-strategy=none` bilan qilinadi — Flutter yangi SW
      yaratmaydi va `flutter_bootstrap.js` uni ro'yxatdan o'tkazmaydi.
   2. Lekin sinovchilar brauzerida ESKI SW allaqachon ro'yxatdan o'tgan.
      U o'zini o'zi o'chirmaydi — uni o'chirish uchun shu manzilda BIRON
      fayl turishi va o'zini bekor qilishi kerak. Quyidagi kod aynan shuni
      qiladi: barcha keshlarni o'chiradi, o'zini ro'yxatdan chiqaradi va
      ochiq tablarni yangilaydi.

   Bu fayl `web/` papkasida turgani uchun build chiqishiga o'zgarishsiz
   ko'chiriladi (Flutter uni qayta yozmaydi, chunki `--pwa-strategy=none`
   da o'zi SW generatsiya qilmaydi).

   QACHON O'CHIRISH MUMKIN. Barcha sinovchilar ilovani bir marta ochib
   chiqqach (~1 hafta) bu fayl keraksiz bo'ladi. Uni o'chirsangiz zarar
   yo'q — yangi foydalanuvchilarda SW umuman ro'yxatdan o'tmaydi.

   OFFLINE REJIM HAQIDA. SW o'chirilgani uchun ilova internetsiz
   ishlamaydi. Bu yo'qotish emas: ilova har bir savolni va har bir javobni
   serverga yuboradi, ya'ni offline rejimda unda qilish mumkin bo'lgan ish
   yo'q edi.
   ========================================================================= */

self.addEventListener('install', function (event) {
  // Kutmasdan darhol faollashamiz — "waiting" holatida qolib ketmaslik uchun.
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    (async function () {
      // 1. Flutter yaratgan barcha keshlarni o'chiramiz.
      const names = await caches.keys();
      await Promise.all(names.map(function (n) { return caches.delete(n); }));

      // 2. O'zimizni ro'yxatdan chiqaramiz.
      await self.registration.unregister();

      // 3. Ochiq tablarni yangilaymiz — foydalanuvchi hech narsa
      //    qilmasdan yangi versiyani oladi.
      const clients = await self.clients.matchAll({ type: 'window' });
      clients.forEach(function (client) {
        if ('navigate' in client) client.navigate(client.url);
      });
    })()
  );
});

// Hech qanday so'rovni ushlamaymiz — hammasi to'g'ridan-to'g'ri tarmoqqa.
self.addEventListener('fetch', function () {});
