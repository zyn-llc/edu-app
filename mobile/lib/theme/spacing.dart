import 'package:flutter/material.dart';

/// 8-point spacing system.
///
/// Nega konstanta: hozir kodda 18, 22, 14, 26 aralash ishlatilgan. Ko'z buni
/// "tasodifiy" deb o'qiydi — professional ilovada masofalar bitta shkaladan
/// olinadi. Bu yerdan olingan har bir qiymat 4 ga karrali.
///
/// Ishlatish: `Spacing.md` yoki `Gap.md` (vertikal/gorizontal avtomatik).
abstract final class Spacing {
  /// 4 — ikonka bilan matn orasi, chip ichidagi zich joy.
  static const double xs = 4;

  /// 8 — bir-biriga tegishli elementlar (sarlavha + tavsif).
  static const double sm = 8;

  /// 12 — ro'yxat elementlari orasi.
  static const double ms = 12;

  /// 16 — standart ichki padding, kartalar orasi.
  static const double md = 16;

  /// 24 — blok ichidagi bo'limlar orasi, karta ichki padding.
  static const double lg = 24;

  /// 32 — mustaqil bo'limlar orasi.
  static const double xl = 32;

  /// 48 — sahifa yuqorisi/pasti, katta bo'shliqlar.
  static const double xxl = 48;

  /// Ekran chetidan padding. Telefonda 16, kengroq ekranda 24.
  static EdgeInsets page(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return EdgeInsets.symmetric(horizontal: w < 600 ? md : lg);
  }
}

/// Burchak radiuslari. 20 dan oshmaydi — kattaroq radius "o'yinchoq"
/// taassurotini beradi va Material 3 tavsiyasidan chiqadi.
abstract final class Radii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 20;
  static const double pill = 999;

  /// "Tabletka" shakli — chip va nishonlar uchun.
  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(pill));

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheetRadius =
      BorderRadius.vertical(top: Radius.circular(xl));
}

/// Bo'shliq qo'yish uchun qisqa yozuv.
///
/// `const SizedBox(height: 16)` o'rniga `const Gap.md()`. Yo'nalish o'zi
/// aniqlanadi: Column ichida vertikal, Row ichida gorizontal bo'ladi, chunki
/// ikkala o'lchamga ham bir xil qiymat beriladi va Flex faqat o'z o'qidagini
/// hisobga oladi.
class Gap extends StatelessWidget {
  final double size;
  const Gap(this.size, {super.key});

  const Gap.xs({super.key}) : size = Spacing.xs;
  const Gap.sm({super.key}) : size = Spacing.sm;
  const Gap.ms({super.key}) : size = Spacing.ms;
  const Gap.md({super.key}) : size = Spacing.md;
  const Gap.lg({super.key}) : size = Spacing.lg;
  const Gap.xl({super.key}) : size = Spacing.xl;
  const Gap.xxl({super.key}) : size = Spacing.xxl;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}
