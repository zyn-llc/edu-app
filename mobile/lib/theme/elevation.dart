import 'package:flutter/material.dart';

/// Soya shkalasi.
///
///
///
///
///
/// ## Qorong'i temada
///
abstract final class Shadows {
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

  ///
  /// Neytral soyadan farqli o'laroq, rangli soya elementni fonga BOG'LAYDI
  static List<BoxShadow> glow(Color color, {double opacity = 0.35}) => [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

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
