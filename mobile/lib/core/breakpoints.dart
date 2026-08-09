import 'package:flutter/material.dart';

/// Material 3 "window size class" — ekran kengligiga qarab layout tanlash.
///
/// Nega enum, `MediaQuery.width > 600` emas: kenglik tekshiruvi kodda o'nlab
/// joyda takrorlansa, chegaralarni bir joydan o'zgartirib bo'lmaydi. Bu yerda
/// chegara BITTA marta yozilgan.
///
/// Chegaralar M3 spetsifikatsiyasidan (dp):
///   compact     < 600   telefon, portret
///   medium      600–839 katta telefon landshaft, kichik planshet
///   expanded    840–1199 planshet landshaft, kichik brauzer oynasi
///   large       1200–1599 desktop
///   extraLarge  >= 1600  keng monitor
enum WindowSize {
  compact,
  medium,
  expanded,
  large,
  extraLarge;

  static WindowSize fromWidth(double w) {
    if (w < 600) return WindowSize.compact;
    if (w < 840) return WindowSize.medium;
    if (w < 1200) return WindowSize.expanded;
    if (w < 1600) return WindowSize.large;
    return WindowSize.extraLarge;
  }

  /// Telefon rejimi: pastda `NavigationBar`, bitta ustun.
  bool get isCompact => this == WindowSize.compact;

  /// `compact` dan katta hamma narsa: chapda `NavigationRail`.
  ///
  /// M3 tavsiyasi — rail aynan `medium` dan boshlanadi. Telefon landshaftda
  /// ekran balandligi 400 dp atrofida bo'ladi va pastki bar kontentning
  /// deyarli choragini yeydi; rail esa vertikal joyni bo'shatadi.
  bool get useRail => this != WindowSize.compact;

  /// Rail yorliqlar bilan yoyilganmi. Faqat haqiqatan keng ekranda —
  /// aks holda rail kontentdan joy o'g'irlaydi.
  bool get useExtendedRail =>
      this == WindowSize.large || this == WindowSize.extraLarge;

  /// Fan kartochkalari gridi uchun ustunlar soni.
  int get gridColumns => switch (this) {
        WindowSize.compact => 2,
        WindowSize.medium => 3,
        WindowSize.expanded => 4,
        WindowSize.large => 5,
        WindowSize.extraLarge => 6,
      };
}

extension WindowSizeX on BuildContext {
  /// Joriy oyna sinfi. `MediaQuery.sizeOf` ishlatiladi — `MediaQuery.of` emas:
  /// birinchisi faqat o'lcham o'zgarganda qayta quradi, ikkinchisi klaviatura
  /// ochilganda ham (`viewInsets`) butun daraxtni qayta quradi.
  WindowSize get windowSize => WindowSize.fromWidth(MediaQuery.sizeOf(this).width);

  bool get isCompact => windowSize.isCompact;
  bool get useRail => windowSize.useRail;
}

/// Kontentni o'qish uchun qulay kenglikda markazlashtiradi.
///
/// Nega kerak: 1920 px monitorda savol matni butun ekran bo'ylab cho'zilsa,
/// ko'z bir qatordan ikkinchisiga o'ta olmaydi (tipografiyada qulay uzunlik
/// ~60–75 belgi). Shu sababli ichki ekranlar shu vidjetga o'raladi.
///
/// Telefonda hech narsa qilmaydi — `maxWidth` ekran kengligidan katta.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;

  /// 720 — matn ustunlari uchun. Grid/dashboard kabi keng kontent uchun
  /// chaqiruv joyida kattaroq qiymat bering (masalan 1100).
  final double maxWidth;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
