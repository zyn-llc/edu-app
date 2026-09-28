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

  //  2026-09-28 da QAYTA TANLANDI. Ikki muammo bor edi:
  //
  //  1. A1 (144°) va A2 (176°) atigi 32° farq qilardi — 10 px nuqtada
  //     ular bir xil ko'rinardi va A1 so'zi A2 dek o'qilardi. Xarita
  //     to'g'ri edi, rang farqi yetarli emasdi. Endi qo'shnilar orasida
  //     kamida 42°, A1/A2 orasida 48° bor.
  //  2. Oq matn bilan kontrast AA dan past edi: A1 3.41:1, A2 3.68:1,
  //     C1 esa atigi 2.52:1. Tanlangan chip oq matn bilan bo'lgani uchun
  //     bu o'qilmaydigan matn degani. Hammasi endi >= 4.5:1.
  //
  //  Kontrast SIMMETRIK, shuning uchun bitta rang ikkala holatga yetadi:
  //  oq fonda matn bo'lib ham, to'ldirilgan chipda oq matn ostida ham.
  static const _map = <String, LevelStyle>{
    'A1': LevelStyle(Color(0xFF258649), Color(0xFF4FBE78)), // yashil    142°
    'A2': LevelStyle(Color(0xFF298092), Color(0xFF55B6CA)), // siyan     190°
    'B1': LevelStyle(Color(0xFF3640C2), Color(0xFF6973FA)), // ko'k      236°
    'B2': LevelStyle(Color(0xFF9836C2), Color(0xFFCE69FA)), // binafsha  282°
    'C1': LevelStyle(Color(0xFFA3682E), Color(0xFFDB9B5D)), // jigarrang  30°
    'C2': LevelStyle(Color(0xFFC23669), Color(0xFFFA699E)), // pushti    338°
  };

  static const _fallback =
      LevelStyle(Color(0xFF8A837A), Color(0xFFA39A8E));

  static LevelStyle of(String? level) =>
      _map[(level ?? '').toUpperCase()] ?? _fallback;

  static Color color(String? level, Brightness b) => of(level).color(b);

  /// Ro'yxat va filtrlar uchun — HAR DOIM shu tartibda.
  static const order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
}
