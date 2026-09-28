import 'package:flutter/widgets.dart';

/// The EduOwl mascot moods, mapped to the expression sheet you provided.
/// Drop the PNGs (or a Rive file) into assets/mascot/ with these names.
enum OwlMood { happy, thinking, excited, encouraging, wow, tip, achievement, oops }

extension on OwlMood {
  String get asset => 'assets/mascot/owl_$name.png';
}

/// Shows the right owl for the moment:
///   result correct -> excited/wow, streak -> encouraging, empty -> thinking,
///   error -> oops, hint -> tip, badge earned -> achievement.
///
/// Falls back gracefully to [OwlMood.happy] art if a specific pose is missing,
/// so the app never crashes on a not-yet-added asset.
class OwlMascot extends StatelessWidget {
  final OwlMood mood;
  final double size;

  const OwlMascot(this.mood, {super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      mood.asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Image.asset(
        OwlMood.happy.asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
      ),
    );
  }
}

/// Boyqushning MA'NOVIY holati — ekran nima demoqchi ekaniga qarab.
///
/// NEGA [OwlMood] USTIGA ALOHIDA QATLAM. `OwlMood` — bu MAVJUD rasmlar
/// ro'yxati; `OwlState` esa ekranning niyati. Ikkisini ajratganda ekranlar
/// "qaysi fayl bor" degan savolga emas, "hozir nima bo'lyapti" degan
/// savolga javob beradi va yangi poza qo'shilganda faqat shu xarita
/// o'zgaradi.
///
/// HOZIRCHA YETISHMAYDIGAN POZALAR: `sleeping` va `reading`.
/// Ular eng yaqin mavjud rasmga tushadi (tinch / o'ylayotgan) — bu
/// ataylab: yo'q faylga ishora qilib, `errorBuilder` orqali `happy` ga
/// qaytish "hammasi zo'r" degan noto'g'ri kayfiyat berardi. Rasm
/// qo'shilgach, quyidagi ikki qatorni almashtirish kifoya.
enum OwlState {
  /// Kutayotgan, hech narsa bo'lmayotgan holat.
  idle,

  /// Yaxshi natija, lekin bayram emas.
  happy,

  /// Ish tugagan, dam olish vaqti ("bugun takrorlash yo'q").
  sleeping,

  /// Matn o'qiyotgan, jimgina diqqat.
  reading,

  /// Bayram: to'g'ri javob, daraja tugadi.
  cheering,

  /// Topilmadi, tushunarsiz, xato.
  confused,
}

extension OwlStateArt on OwlState {
  OwlMood get mood => switch (this) {
        OwlState.idle => OwlMood.tip,
        OwlState.happy => OwlMood.happy,
        // YETISHMAYDI: tinch uxlayotgan poza. Eng yaqini — `tip`.
        OwlState.sleeping => OwlMood.tip,
        // YETISHMAYDI: kitob o'qiyotgan poza. Eng yaqini — `thinking`.
        OwlState.reading => OwlMood.thinking,
        OwlState.cheering => OwlMood.excited,
        OwlState.confused => OwlMood.thinking,
      };

  /// Rasm hali chizilmaganmi — hisobotda va testda ishlatiladi.
  bool get artIsMissing =>
      this == OwlState.sleeping || this == OwlState.reading;
}
