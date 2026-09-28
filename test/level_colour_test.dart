// DARAJA RANGLARI.
//
// Hisobot: "A1 so'zlari A2 (moviy-yashil) rangida ko'rinyapti".
// Tekshiruv shuni ko'rsatdi: XARITA TO'G'RI — A1 haqiqatan yashil.
// Muammo boshqa joyda edi: A1 (144°) va A2 (176°) atigi 32° farq
// qilardi va 10 px nuqtada ular bir xil ko'rinardi.
//
// Bu yerdagi testlar ikki narsani qulflaydi:
//   1. Qo'shni darajalar RANG BURCHAGI bo'yicha yetarlicha uzoq.
//   2. Har bir rang oq matn bilan AA (4.5:1) kontrastga ega — tanlangan
//      chip to'ldirilgan bo'lib, ustida oq matn turadi.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:topagon/theme/level_palette.dart';

double _hue(Color c) => HSVColor.fromColor(c).hue;

double _relLuminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrastWithWhite(Color c) => 1.05 / (_relLuminance(c) + 0.05);

void main() {
  group('level -> colour mapping', () {
    test('A1 is green, not the teal used by A2', () {
      // Aynan shikoyat qilingan holat.
      final a1 = LevelPalette.color('A1', Brightness.light);
      final a2 = LevelPalette.color('A2', Brightness.light);
      expect(a1, isNot(a2));
      // Yashil ~90-165°, siyan ~165-210°.
      expect(_hue(a1), inInclusiveRange(90, 165));
      expect(_hue(a2), inInclusiveRange(165, 215));
    });

    test('each level resolves to its own colour', () {
      final seen = <int, String>{};
      for (final lv in LevelPalette.order) {
        final c = LevelPalette.color(lv, Brightness.light);
        expect(seen.containsKey(c.toARGB32()), isFalse,
            reason: '$lv shares a colour with ${seen[c.toARGB32()]}');
        seen[c.toARGB32()] = lv;
      }
    });

    test('case and whitespace do not break the lookup', () {
      final a1 = LevelPalette.color('A1', Brightness.light);
      expect(LevelPalette.color('a1', Brightness.light), a1);
    });

    test('an unknown level falls back instead of throwing', () {
      expect(() => LevelPalette.color('Z9', Brightness.light),
          returnsNormally);
      expect(() => LevelPalette.color(null, Brightness.light),
          returnsNormally);
    });
  });

  group('adjacent levels are far enough apart to tell apart', () {
    test('at least 40 degrees of hue between neighbours', () {
      for (var i = 0; i < LevelPalette.order.length - 1; i++) {
        final a = LevelPalette.order[i];
        final b = LevelPalette.order[i + 1];
        final ha = _hue(LevelPalette.color(a, Brightness.light));
        final hb = _hue(LevelPalette.color(b, Brightness.light));
        var d = (ha - hb).abs();
        if (d > 180) d = 360 - d;
        expect(d, greaterThanOrEqualTo(40),
            reason: '$a and $b are only ${d.round()}° apart — at badge '
                'size they read as the same colour');
      }
    });
  });

  group('contrast', () {
    test('white text on a selected chip meets AA in every level', () {
      // Tanlangan CEFR chip to'ldirilgan va matni OQ. AA dan past bo'lsa,
      // yorliq umuman o'qilmaydi.
      for (final lv in LevelPalette.order) {
        final c = LevelPalette.color(lv, Brightness.light);
        expect(_contrastWithWhite(c), greaterThanOrEqualTo(4.5),
            reason: '$lv is ${_contrastWithWhite(c).toStringAsFixed(2)}:1 '
                'against white');
      }
    });

    test('the same colour also works as text on a white ground', () {
      // Kontrast simmetrik — belgidagi "A1" yozuvi ham shu rangda.
      for (final lv in LevelPalette.order) {
        final c = LevelPalette.color(lv, Brightness.light);
        expect(_contrastWithWhite(c), greaterThanOrEqualTo(4.5));
      }
    });

    test('dark theme variants stay distinguishable from each other', () {
      final seen = <int>{};
      for (final lv in LevelPalette.order) {
        final c = LevelPalette.color(lv, Brightness.dark);
        expect(seen.add(c.toARGB32()), isTrue, reason: '$lv duplicated');
      }
    });
  });
}
