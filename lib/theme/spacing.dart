import 'package:flutter/material.dart';

/// 8-point spacing system.
///
///
/// Ishlatish: `Spacing.md` yoki `Gap.md` (vertikal/gorizontal avtomatik).
abstract final class Spacing {
  static const double xs = 4;

  /// 8 — bir-biriga tegishli elementlar (sarlavha + tavsif).
  static const double sm = 8;

  static const double ms = 12;

  static const double md = 16;

  static const double lg = 24;

  static const double xl = 32;

  static const double xxl = 48;

  static EdgeInsets page(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return EdgeInsets.symmetric(horizontal: w < 600 ? md : lg);
  }
}

/// Burchak radiuslari. 20 dan oshmaydi — kattaroq radius "o'yinchoq"
abstract final class Radii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 20;
  static const double pill = 999;

  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(pill));

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheetRadius =
      BorderRadius.vertical(top: Radius.circular(xl));
}

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
