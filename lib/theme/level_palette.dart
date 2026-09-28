import 'package:flutter/material.dart';

/// CEFR darajasining RANGI — A1 dan C2 gacha.
///
/// NEGA KERAK. Daraja — til bo'limidagi asosiy o'lchov: har bir so'z, har
/// bir mavzu va har bir matn unga tegishli. Hammasi bir xil kulrang bo'lsa,
/// o'quvchi qaysi daraja bilan ishlayotganini har safar O'QIB aniqlashi
/// kerak. Rang buni bir qarashda beradi.
///
/// Tartib ISSIQLIK bo'yicha o'sadi: yashil (oson) -> pushti (eng qiyin).
/// Bu tasodifiy emas — o'quvchi ranglar ketma-ketligini darajalar
/// ketma-ketligi bilan bog'lab oladi.
///
/// Fanlar rangi (`subject_palette.dart`) dan ALOHIDA: u fanni ajratadi,
/// bu esa qiyinlikni bildiradi. Ikkalasini aralashtirsak, "ko'k" gohida
/// matematika, gohida B1 degani bo'lib qolardi.
class LevelStyle {
  final Color light;
  final Color dark;
  const LevelStyle(this.light, this.dark);

  Color color(Brightness b) => b == Brightness.dark ? dark : light;
}

class LevelPalette {
  LevelPalette._();

  static const _map = <String, LevelStyle>{
    'A1': LevelStyle(Color(0xFF2E9E5B), Color(0xFF41BA72)), // yashil
    'A2': LevelStyle(Color(0xFF17958C), Color(0xFF29ADA3)), // moviy-yashil
    'B1': LevelStyle(Color(0xFF2F6FB0), Color(0xFF4A8BD0)), // ko'k
    'B2': LevelStyle(Color(0xFF6A53C7), Color(0xFF8470DE)), // binafsha
    'C1': LevelStyle(Color(0xFFD9962A), Color(0xFFE8A53B)), // sariq
    'C2': LevelStyle(Color(0xFFC7436B), Color(0xFFDC5C82)), // pushti
  };

  static const _fallback =
      LevelStyle(Color(0xFF8A837A), Color(0xFFA39A8E));

  static LevelStyle of(String? level) =>
      _map[(level ?? '').toUpperCase()] ?? _fallback;

  static Color color(String? level, Brightness b) => of(level).color(b);

  /// Ro'yxat va filtrlar uchun — HAR DOIM shu tartibda.
  static const order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
}
