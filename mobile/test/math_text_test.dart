import 'package:flutter_test/flutter_test.dart';

import 'package:topagon/core/math_text.dart';

void main() {
  group('layout commands are stripped', () {
    test(r'\displaystyle is stripped', () {
      final out = renderMathText(r'Hisoblang: \displaystyle \int_0^2 x^3 dx.');
      expect(out, isNot(contains(r'\displaystyle')));
      expect(out, isNot(contains('displaystyle')));
      expect(out, contains('∫'));
      expect(out, contains('x³'));
    });

    test(r'\limits and \textstyle too', () {
      expect(renderMathText(r'\sum\limits_{i=1}^{n} i'),
          isNot(contains('limits')));
      expect(renderMathText(r'\textstyle \frac{1}{2}'),
          isNot(contains('textstyle')));
    });
  });

  group('decorative commands keep their content', () {
    test(r'\overline{AB} -> AB', () {
      expect(renderMathText(r'\overline{AB} kesma'), 'AB kesma');
    });

    test(r'\mathbb{R} -> R', () {
      expect(renderMathText(r'x \in \mathbb{R}'), contains('R'));
      expect(renderMathText(r'x \in \mathbb{R}'), isNot(contains('mathbb')));
    });
  });

  group('safety net for unknown commands', () {
    test('a long unknown command is dropped entirely', () {
      final out = renderMathText(r'\qandaydirBuyruq{} x + 1');
      expect(out, isNot(contains('qandaydir')));
      expect(out, contains('x + 1'));
    });

    test('a stray backslash before one or two letters keeps them', () {
      expect(renderMathText(r'2\x + 3'), contains('2x'));
      expect(renderMathText(r'\xy = 5'), contains('xy'));
    });

    test('a capitalised Greek letter survives', () {
      expect(renderMathText(r'\Delta x'), contains('Δ'));
      expect(renderMathText(r'\Omega'), contains('Ω'));
      expect(renderMathText(r'\alpha + \beta'), contains('α'));
    });
  });

  group('real question text from the database', () {
    const realStems = [
      r'(99-1-27) Hisoblang: $\displaystyle\int_0^2 x^3\,dx$.',
      r'Hisoblang: $\displaystyle\int_0^2 2x\,dx$.',
      r'Hisoblang: $\displaystyle\int_{-2}^3 |1-x|\,dx$.',
      r'Integralni hisoblang: $\displaystyle\int_{-1}^{2} 2\,dx$.',
      r'(96-7-31) Hisoblang: $\displaystyle\int_0^2 (1-2x)^2\,dx$.',
      r'Hisoblang: $10^{-\lg 4}$.',
      r'Tenglamani yeching: $\lg(2-5x)=1$.',
    ];

    test('no backslash is left in any of them', () {
      for (final s in realStems) {
        final out = renderMathText(s);
        expect(out, isNot(contains(r'\')), reason: 'kirish: $s');
      }
    });

    test('the source citation goes, the integral sign stays', () {
      final out = renderMathText(realStems[0]);
      expect(out, isNot(contains('99-1-27')));
      expect(out, startsWith('Hisoblang'));
      expect(out, contains('∫'));
      expect(out, contains('x³'));
    });
  });

  group('existing behaviour is unchanged', () {
    test('a fraction is marked with a sentinel and flattened', () {
      expect(flattenFractions(renderMathText(r'$\frac{1}{5}$')), '1/5');
    });

    test('roots', () {
      expect(renderMathText(r'\sqrt{16}'), '√(16)');
    });

    test('text without LaTeX is left alone', () {
      const plain = 'Toshkent shahri qaysi yilda tashkil topgan?';
      expect(renderMathText(plain), plain);
    });

    test('function names and powers', () {
      expect(renderMathText(r'\sin^2 x'), contains('sin'));
      expect(renderMathText(r'x^2'), 'x²');
    });

    test('empty and null are safe', () {
      expect(renderMathText(null), '');
      expect(renderMathText(''), '');
    });
  });
}
