import 'package:flutter/material.dart';

/// Brand + neutral colors for light and dark, mirroring design-tokens.json.
/// Subject accent colors live in subject_palette.dart.
///
/// Rule: `primary` (orange) is the UNIVERSAL chrome color on every screen.
/// Subject colors are accents only and never recolor chrome.
class AppColors {
  AppColors._();

  // ---- Light ----
  static const lightPrimary = Color(0xFFF8721C);
  static const lightPrimaryPressed = Color(0xFFE0590A);
  static const lightPrimaryTint = Color(0xFFFFF1E6);
  static const lightOnPrimary = Color(0xFFFFFFFF);

  // 2026-08-06: iliq krem fon (#FBF7F2) neytral kulrangga o'zgartirildi.
  //
  // NEGA. Iliq fonda oq karta deyarli ko'rinmasdi — ikkalasining yorqinligi
  // juda yaqin edi, natijada interfeys "yassi" (flat) tuyulardi va soya ham
  // yordam bermasdi. #F8F9FA neytral va biroz sovuqroq: ustidagi TOZA OQ
  // karta aniq ajralib turadi, apelsin brend rangi esa undan yanada yorqin
  // ko'rinadi (sovuq fon issiq aksentni kuchaytiradi).
  static const lightBackground = Color(0xFFF8F9FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFF1F3F5);
  static const lightHairline = Color(0xFFE7EAEE);
  static const lightInk = Color(0xFF191C1F);
  static const lightMuted = Color(0xFF6B7280);
  static const lightFaint = Color(0xFFA6AEB8);

  static const lightSuccess = Color(0xFF2E9E5B);
  static const lightWarning = Color(0xFFC98A00);
  static const lightDanger = Color(0xFFD8452F);

  // ---- Dark ----
  static const darkPrimary = Color(0xFFFF8A3D);
  static const darkPrimaryPressed = Color(0xFFE9762B);
  static const darkPrimaryTint = Color(0xFF33241A);
  static const darkOnPrimary = Color(0xFF1A1206);

  static const darkBackground = Color(0xFF131110);
  static const darkSurface = Color(0xFF1E1A17);
  static const darkSurfaceAlt = Color(0xFF262019);
  static const darkHairline = Color(0xFF312A24);
  static const darkInk = Color(0xFFF3EEE7);
  static const darkMuted = Color(0xFFA39A8E);
  static const darkFaint = Color(0xFF5E564C);

  static const darkSuccess = Color(0xFF4FC98A);
  static const darkWarning = Color(0xFFF5B93C);
  static const darkDanger = Color(0xFFFF6F5A);

  // ---- Podium (ikkala temada bir xil — medal ranglari brenddan mustaqil) ----
  static const gold = Color(0xFFE0A106);
  static const silver = Color(0xFF9AA3AC);
  static const bronze = Color(0xFFB4703A);
}

/// Extra semantic colors exposed on ThemeData via ThemeExtension, so widgets
/// read `Theme.of(context).extension<AppPalette>()` instead of hard-coding hex.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color surfaceAlt;
  final Color hairline;
  final Color muted;
  final Color faint;
  final Color primaryTint;
  final Color primaryPressed;

  /// Semantik ranglar. Ilgari `Colors.green` / `Colors.red` kodda tarqoq
  /// yozilgan edi — qorong'i temada ular juda yorqin chiqadi va brend
  /// palitrasidan chiqib ketadi.
  final Color success;
  final Color warning;
  final Color danger;

  const AppPalette({
    required this.surfaceAlt,
    required this.hairline,
    required this.muted,
    required this.faint,
    required this.primaryTint,
    required this.primaryPressed,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const light = AppPalette(
    surfaceAlt: AppColors.lightSurfaceAlt,
    hairline: AppColors.lightHairline,
    muted: AppColors.lightMuted,
    faint: AppColors.lightFaint,
    primaryTint: AppColors.lightPrimaryTint,
    primaryPressed: AppColors.lightPrimaryPressed,
    success: AppColors.lightSuccess,
    warning: AppColors.lightWarning,
    danger: AppColors.lightDanger,
  );

  static const dark = AppPalette(
    surfaceAlt: AppColors.darkSurfaceAlt,
    hairline: AppColors.darkHairline,
    muted: AppColors.darkMuted,
    faint: AppColors.darkFaint,
    primaryTint: AppColors.darkPrimaryTint,
    primaryPressed: AppColors.darkPrimaryPressed,
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
    danger: AppColors.darkDanger,
  );

  @override
  AppPalette copyWith({
    Color? surfaceAlt,
    Color? hairline,
    Color? muted,
    Color? faint,
    Color? primaryTint,
    Color? primaryPressed,
    Color? success,
    Color? warning,
    Color? danger,
  }) =>
      AppPalette(
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        hairline: hairline ?? this.hairline,
        muted: muted ?? this.muted,
        faint: faint ?? this.faint,
        primaryTint: primaryTint ?? this.primaryTint,
        primaryPressed: primaryPressed ?? this.primaryPressed,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
      );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      primaryTint: Color.lerp(primaryTint, other.primaryTint, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
