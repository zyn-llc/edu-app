// Kartochka ag'darilishi va talaffuz qoidasi.
//
// TALAFFUZDAGI ASOSIY QOIDA: til uchun ovoz bo'lmasa — JIM TURAMIZ.
// Nemischa so'zni inglizcha ovoz bilan o'qitish noto'g'ri talaffuzni
// O'RGATADI, ya'ni jim turishdan yomonroq. Bu xato eshitilmaguncha
// bilinmaydi, shuning uchun test bilan qulflanadi.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:topagon/core/pronounce.dart';
import 'package:topagon/features/vocab/flip_card.dart';

void main() {
  group('FlipCard', () {
    Widget wrap(bool showBack) => MaterialApp(
          home: Scaffold(
            body: FlipCard(
              showBack: showBack,
              front: const Text('front'),
              back: const Text('back'),
            ),
          ),
        );

    testWidgets('shows the front when not flipped', (tester) async {
      await tester.pumpWidget(wrap(false));
      expect(find.text('front'), findsOneWidget);
      expect(find.text('back'), findsNothing);
    });

    testWidgets('starts already flipped when asked to', (tester) async {
      // Bu holat mavjud: kartochka qayta qurilganda holat saqlanishi kerak.
      await tester.pumpWidget(wrap(true));
      await tester.pumpAndSettle();
      expect(find.text('back'), findsOneWidget);
      expect(find.text('front'), findsNothing);
    });

    testWidgets('swaps sides only after the halfway point', (tester) async {
      await tester.pumpWidget(wrap(false));
      await tester.pumpWidget(wrap(true));

      // Boshida hali old tomon.
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('front'), findsOneWidget);

      // Oxirida orqa tomon.
      await tester.pumpAndSettle();
      expect(find.text('back'), findsOneWidget);
      expect(find.text('front'), findsNothing);
    });

    testWidgets('flips back again', (tester) async {
      await tester.pumpWidget(wrap(true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(wrap(false));
      await tester.pumpAndSettle();
      expect(find.text('front'), findsOneWidget);
    });

    testWidgets('only one side is in the tree at a time', (tester) async {
      // Ikkalasi ham daraxtda qolsa, ekran o'qish dasturlari orqa tomonni
      // ag'darilmasdan oldin o'qib yuborardi.
      await tester.pumpWidget(wrap(false));
      await tester.pumpAndSettle();
      expect(find.text('front'), findsOneWidget);
      expect(find.text('back'), findsNothing);
    });
  });

  group('PronounceService language guard', () {
    late ProviderContainer c;

    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('a language with no mapping is never spoken', () async {
      // Bu tekshiruv platformaga UMUMAN tegmaydi: xarita bo'sh bo'lsa
      // darhol `false`. Shuning uchun test'da TTS kerak emas.
      final s = c.read(pronounceServiceProvider);
      expect(await s.supports('uz'), isFalse);
      expect(await s.supports('fr'), isFalse);
      expect(await s.supports(''), isFalse);
    });

    test('say() on an unmapped language completes silently', () async {
      // Xato tashlamasligi kerak — talaffuz qo'shimcha imkoniyat, ilova
      // uning yo'qligidan yiqilmasligi shart.
      final s = c.read(pronounceServiceProvider);
      await expectLater(s.say('salom', 'uz'), completes);
      await expectLater(s.say('', 'en'), completes);
    });

    test('the three module languages are the mapped ones', () async {
      // Modulda en / de / ru bor; boshqasi qo'shilsa, xarita ham
      // yangilanishi kerak va bu test buni eslatadi.
      final s = c.read(pronounceServiceProvider);
      for (final unmapped in ['uz', 'fr', 'es', 'tr']) {
        expect(await s.supports(unmapped), isFalse,
            reason: '$unmapped modulda yo\'q');
      }
    });
  });
}
