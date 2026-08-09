import 'package:flutter_test/flutter_test.dart';

import 'package:topagon/core/math_text.dart';

/// `renderMathText` — savol matni o'quvchiga qanday ko'rinishini hal qiladi.
///
/// NEGA BU TEST KECH YOZILDI. Funksiyada 280 qator mantiq bor edi va bitta
/// ham test yo'q edi. Natijada `\displaystyle` bazadagi 48 ta savolda XOM
/// holda chiqib turdi — o'quvchi "Hisoblang: \displaystyle ∫₀² x³ dx" ni
/// ko'rdi. Xato `flutter analyze` dan ham, boshqa testlardan ham o'tdi,
/// chunki uni ushlaydigan narsa yo'q edi.
///
/// Shu sababli bu yerda ikki xil tekshiruv bor:
///   1. Bazada HAQIQATAN uchraydigan buyruqlar (chastota bilan o'lchangan);
///   2. Umumiy qoida: noma'lum buyruq matnda qolib ketmasin.
void main() {
  group('joylashuv buyruqlari matnda qolmaydi', () {
    test(r'\displaystyle olib tashlanadi', () {
      final out = renderMathText(r'Hisoblang: \displaystyle \int_0^2 x^3 dx.');
      expect(out, isNot(contains(r'\displaystyle')));
      expect(out, isNot(contains('displaystyle')));
      expect(out, contains('∫'));
      expect(out, contains('x³'));
    });

    test(r'\limits va \textstyle ham', () {
      expect(renderMathText(r'\sum\limits_{i=1}^{n} i'),
          isNot(contains('limits')));
      expect(renderMathText(r'\textstyle \frac{1}{2}'),
          isNot(contains('textstyle')));
    });
  });

  group('bezak buyruqlari mazmunni saqlaydi', () {
    test(r'\overline{AB} -> AB', () {
      expect(renderMathText(r'\overline{AB} kesma'), 'AB kesma');
    });

    test(r'\mathbb{R} -> R', () {
      expect(renderMathText(r'x \in \mathbb{R}'), contains('R'));
      expect(renderMathText(r'x \in \mathbb{R}'), isNot(contains('mathbb')));
    });
  });

  group('noma\'lum buyruqlar uchun himoya to\'ri', () {
    test('uzun noma\'lum buyruq butunlay tashlanadi', () {
      // Nomini ko'rsatish ("qandaydirBuyruq") ko'rsatmaslikdan yomonroq.
      final out = renderMathText(r'\qandaydirBuyruq{} x + 1');
      expect(out, isNot(contains('qandaydir')));
      expect(out, contains('x + 1'));
    });

    test('bir-ikki harfli adashgan teskari chiziq harfni SAQLAYDI', () {
      // Bazada `\x`, `\xy` kabi 60 ga yaqin joy bor — bu LaTeX buyrug'i
      // emas, manbadan kelgan chiziq. Tashlansa o'zgaruvchi yo'qoladi.
      expect(renderMathText(r'2\x + 3'), contains('2x'));
      expect(renderMathText(r'\xy = 5'), contains('xy'));
    });

    test('bosh harfli yunon harfi YO\'QOLMAYDI', () {
      // Himoya to'ri qo'shilganda eng katta xavf shu edi: `\Delta`
      // jadvalda bo'lmasa, jimgina o'chib ketardi.
      expect(renderMathText(r'\Delta x'), contains('Δ'));
      expect(renderMathText(r'\Omega'), contains('Ω'));
      expect(renderMathText(r'\alpha + \beta'), contains('α'));
    });
  });

  group('bazadan olingan haqiqiy savol matnlari', () {
    // Prod bazasidan ko'chirilgan. O'ylab topilgan misol emas: xato aynan
    // shu qatorlarda ko'rindi va o'quvchi ularni shu holda o'qidi.
    const realStems = [
      r'(99-1-27) Hisoblang: $\displaystyle\int_0^2 x^3\,dx$.',
      r'Hisoblang: $\displaystyle\int_0^2 2x\,dx$.',
      r'Hisoblang: $\displaystyle\int_{-2}^3 |1-x|\,dx$.',
      r'Integralni hisoblang: $\displaystyle\int_{-1}^{2} 2\,dx$.',
      r'(96-7-31) Hisoblang: $\displaystyle\int_0^2 (1-2x)^2\,dx$.',
      r'Hisoblang: $10^{-\lg 4}$.',
      r'Tenglamani yeching: $\lg(2-5x)=1$.',
    ];

    test('birortasida teskari chiziq qolmaydi', () {
      for (final s in realStems) {
        final out = renderMathText(s);
        expect(out, isNot(contains(r'\')), reason: 'kirish: $s');
      }
    });

    test('manba iqtiboti olinadi, integral belgisi qoladi', () {
      final out = renderMathText(realStems[0]);
      expect(out, isNot(contains('99-1-27')));
      expect(out, startsWith('Hisoblang'));
      expect(out, contains('∫'));
      expect(out, contains('x³'));
    });
  });

  group('mavjud xatti-harakat buzilmagan', () {
    test('kasr sentinel bilan belgilanadi va yassilanadi', () {
      expect(flattenFractions(renderMathText(r'$\frac{1}{5}$')), '1/5');
    });

    test('ildiz', () {
      expect(renderMathText(r'\sqrt{16}'), '√(16)');
    });

    test('LaTeX yo\'q bo\'lsa matn o\'zgarmaydi', () {
      const plain = 'Toshkent shahri qaysi yilda tashkil topgan?';
      expect(renderMathText(plain), plain);
    });

    test('funksiya nomi va daraja', () {
      expect(renderMathText(r'\sin^2 x'), contains('sin'));
      expect(renderMathText(r'x^2'), 'x²');
    });

    test('bo\'sh va null xavfsiz', () {
      expect(renderMathText(null), '');
      expect(renderMathText(''), '');
    });
  });
}
