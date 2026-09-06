import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'spacing.dart';

/// Yorug' va qorong'i temalar. Apelsin rangi ikkalasida ham yagona `primary`.
///
///
///
///
/// | Slot             | O'lcham | Og'irlik | Qayerda                    |
/// |------------------|---------|----------|----------------------------|
/// | headlineMedium   | 26      | w700     | katta blok sarlavhasi      |
/// | titleLarge       | 18      | w700     | karta sarlavhasi           |
/// | labelSmall       | 12      | w600     | belgi (badge), sana        |
///
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static TextTheme _typography(TextTheme base, Color ink, Color muted) {
    final t = GoogleFonts.manropeTextTheme(base);
    return t.copyWith(
      displayLarge: t.displayLarge?.copyWith(
          fontSize: 40, fontWeight: FontWeight.w800, height: 1.12,
          letterSpacing: -1.0, color: ink),
      displayMedium: t.displayMedium?.copyWith(
          fontSize: 36, fontWeight: FontWeight.w800, height: 1.14,
          letterSpacing: -0.8, color: ink),
      displaySmall: t.displaySmall?.copyWith(
          fontSize: 32, fontWeight: FontWeight.w800, height: 1.16,
          letterSpacing: -0.6, color: ink),
      headlineLarge: t.headlineLarge?.copyWith(
          fontSize: 28, fontWeight: FontWeight.w700, height: 1.2,
          letterSpacing: -0.5, color: ink),
      headlineMedium: t.headlineMedium?.copyWith(
          fontSize: 26, fontWeight: FontWeight.w700, height: 1.22,
          letterSpacing: -0.4, color: ink),
      headlineSmall: t.headlineSmall?.copyWith(
          fontSize: 22, fontWeight: FontWeight.w700, height: 1.26,
          letterSpacing: -0.3, color: ink),
      titleLarge: t.titleLarge?.copyWith(
          fontSize: 18, fontWeight: FontWeight.w700, height: 1.3,
          letterSpacing: -0.2, color: ink),
      titleMedium: t.titleMedium?.copyWith(
          fontSize: 16, fontWeight: FontWeight.w600, height: 1.35,
          letterSpacing: -0.1, color: ink),
      titleSmall: t.titleSmall?.copyWith(
          fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: ink),
      // sezilarli osonlashtiradi.
      bodyLarge: t.bodyLarge?.copyWith(
          fontSize: 15, fontWeight: FontWeight.w400, height: 1.5, color: ink),
      bodyMedium: t.bodyMedium?.copyWith(
          fontSize: 14, fontWeight: FontWeight.w400, height: 1.45, color: ink),
      bodySmall: t.bodySmall?.copyWith(
          fontSize: 13, fontWeight: FontWeight.w400, height: 1.4, color: muted),
      labelLarge: t.labelLarge?.copyWith(
          fontSize: 14, fontWeight: FontWeight.w600, height: 1.2,
          letterSpacing: 0, color: ink),
      labelMedium: t.labelMedium?.copyWith(
          fontSize: 13, fontWeight: FontWeight.w500, height: 1.2, color: muted),
      labelSmall: t.labelSmall?.copyWith(
          fontSize: 12, fontWeight: FontWeight.w600, height: 1.2,
          letterSpacing: 0.2, color: muted),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
      onPrimary: isDark ? AppColors.darkOnPrimary : AppColors.lightOnPrimary,
      secondary: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
      onSecondary: isDark ? AppColors.darkOnPrimary : AppColors.lightOnPrimary,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      onSurface: isDark ? AppColors.darkInk : AppColors.lightInk,
      error: const Color(0xFFD64545),
      onError: Colors.white,
    );

    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    final textTheme = _typography(base.textTheme, scheme.onSurface, palette.muted);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      textTheme: textTheme,
      extensions: [palette],

      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardRadius,
          side: BorderSide(color: palette.hairline),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: palette.surfaceAlt,
          disabledForegroundColor: palette.faint,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          // 48 dp — Material'ning minimal teginish maydoni. Undan kichigi
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.ms),
          shape: const RoundedRectangleBorder(borderRadius: Radii.buttonRadius),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: palette.hairline),
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.ms),
          shape: const RoundedRectangleBorder(borderRadius: Radii.buttonRadius),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(0, 44),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: palette.primaryTint,
        side: BorderSide(color: palette.hairline),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.ms, vertical: Spacing.sm),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(Radii.pill))),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        hintStyle: textTheme.bodyMedium?.copyWith(color: palette.faint),
        labelStyle: textTheme.labelMedium,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.md),
        border: OutlineInputBorder(
          borderRadius: Radii.buttonRadius,
          borderSide: BorderSide(color: palette.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.buttonRadius,
          borderSide: BorderSide(color: palette.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.buttonRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.primaryTint,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? textTheme.labelSmall?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w700)
                : textTheme.labelSmall),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : palette.muted)),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: palette.primaryTint,
        selectedLabelTextStyle: textTheme.labelMedium
            ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: textTheme.labelMedium
            ?.copyWith(color: palette.muted, fontWeight: FontWeight.w400),
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 24),
        unselectedIconTheme: IconThemeData(color: palette.muted, size: 24),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        extendedTextStyle:
            textTheme.labelLarge?.copyWith(color: scheme.onPrimary),
        shape: const RoundedRectangleBorder(borderRadius: Radii.buttonRadius),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
          side: BorderSide(color: palette.hairline),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetRadius),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkSurfaceAlt : AppColors.lightInk,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
            color: isDark ? AppColors.darkInk : Colors.white),
        shape: const RoundedRectangleBorder(borderRadius: Radii.buttonRadius),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: palette.surfaceAlt,
        circularTrackColor: palette.surfaceAlt,
        linearMinHeight: 8,
      ),

      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        iconColor: palette.muted,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.xs),
        shape: const RoundedRectangleBorder(borderRadius: Radii.buttonRadius),
      ),

      dividerTheme: DividerThemeData(
          color: palette.hairline, thickness: 1, space: 1),

      hoverColor: palette.primaryTint.withValues(alpha: 0.5),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
