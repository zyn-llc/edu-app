import 'package:flutter/material.dart';

/// Soya shkalasi.
///
/// ## Nega alohida fayl
///
/// Soyalar kodda tarqoq yozilganda ular hech qachon bir-biriga mos kelmaydi:
/// bir kartada `blurRadius: 8`, yonidagisida `18`, uchinchisida umuman yo'q.
/// Ko'z buni "tasodifiy" deb o'qiydi va interfeys arzon ko'rinadi.
///
/// ## Nega ikki qatlam
///
/// Haqiqiy soyada ikkita komponent bor: obyekt tagidagi zich, qisqa soya
/// (kontakt) va uzoqroqqa tarqaladigan yumshoq soya (ambient). Bitta
/// `BoxShadow` bilan yasalgan soya har doim "bulut" bo'lib ko'rinadi.
///
/// ## Qorong'i temada
///
/// Qora fonda qora soya ko'rinmaydi. U yerda chuqurlik soya bilan emas,
/// SIRT RANGI bilan beriladi (Material 3 tamoyili), shuning uchun qorong'i
/// temada soyalar deyarli nolga tushiriladi va o'rniga chegara ishlaydi.
abstract final class Shadows {
  /// Tinch holatdagi karta. Deyarli sezilmaydi, lekin kartani fondan
  /// ajratib turadi — foydalanuvchi "qatlam" borligini his qiladi.
  static List<BoxShadow> card(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) return const [];
    return const [
      BoxShadow(
        color: Color(0x0A000000), // 4%
        blurRadius: 10,
        offset: Offset(0, 2),
      ),
      BoxShadow(
        color: Color(0x05000000), // 2%
        blurRadius: 3,
        offset: Offset(0, 1),
      ),
    ];
  }

  /// Sichqoncha ostidagi karta — sezilarli ko'tariladi.
  ///
  /// 1 px dan 12 px gacha o'sish ataylab kuchli: hover holati "bor-yo'qligi
  /// noaniq" bo'lsa, u umuman ishlamaydi. Foydalanuvchi kursorni bir marta
  /// yurgizib, qaysi elementlar bosiladiganini bilib olishi kerak.
  static List<BoxShadow> lift(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) return const [];
    return const [
      BoxShadow(
        color: Color(0x1F000000), // 12%
        blurRadius: 24,
        offset: Offset(0, 12),
      ),
      BoxShadow(
        color: Color(0x0F000000), // 6%
        blurRadius: 6,
        offset: Offset(0, 2),
      ),
    ];
  }

  /// Rangli "porlash" — asosiy harakat tugmasi (FAB) uchun.
  ///
  /// Neytral soyadan farqli o'laroq, rangli soya elementni fonga BOG'LAYDI
  /// (rang yerga to'kilgandek) va shu bilan uni sahifaning eng muhim
  /// elementi qilib ko'rsatadi.
  static List<BoxShadow> glow(Color color, {double opacity = 0.35}) => [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  /// Modal / varaq uchun — chetlari aniq ko'rinsin.
  static List<BoxShadow> overlay(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Color(isDark ? 0x66000000 : 0x1A000000),
        blurRadius: 32,
        offset: const Offset(0, 16),
      ),
    ];
  }
}
