// Javob variantining HOLATLARI.
//
// Bu yerdagi xato jim: ekran ishlaydi, shunchaki o'quvchi to'g'ri javobni
// ko'rmaydi yoki xato javob to'g'ridek ko'rinadi. Shuning uchun har bir
// holat alohida qulflanadi.
//
// Ishga tushirish:
//     flutter test test/answer_state_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:topagon/l10n/app_localizations.dart';
import 'package:topagon/mascot/mascot.dart';
import 'package:topagon/theme/app_colors.dart' show AppPalette;
import 'package:topagon/theme/app_theme.dart';
import 'package:topagon/widgets/answer_tile.dart';

Widget wrap(Widget child, {double width = 375}) => MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('uz'),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('uz'), Locale('ru')],
      home: Scaffold(body: SizedBox(width: width, child: child)),
    );

/// Plitkaning chizilgan foni va chegarasi.
(Color?, Color?) painted(WidgetTester tester) {
  final c = tester.widget<AnimatedContainer>(find.descendant(
      of: find.byType(AnswerTile), matching: find.byType(AnimatedContainer)));
  final d = c.decoration as BoxDecoration;
  return (d.color, d.border?.top.color);
}

Widget tile(AnswerState s) => AnswerTile(
      letter: 'B',
      text: 'В больнице',
      state: s,
      onTap: () {},
    );

void main() {
  group('AnswerTile', () {
    testWidgets('renders the letter and the option text', (tester) async {
      await tester.pumpWidget(wrap(tile(AnswerState.idle)));
      expect(find.text('B'), findsOneWidget);
      expect(find.text('В больнице'), findsOneWidget);
    });

    testWidgets('idle carries no verdict icon', (tester) async {
      await tester.pumpWidget(wrap(tile(AnswerState.idle)));
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets('picked is not yet a verdict', (tester) async {
      // Tekshirishdan OLDIN tanlov to'g'ri ham, xato ham emas — belgi
      // chiqsa, o'quvchi javobni bosishdan oldin bilib olardi.
      await tester.pumpWidget(wrap(tile(AnswerState.picked)));
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets('correct shows a check', (tester) async {
      await tester.pumpWidget(wrap(tile(AnswerState.correct)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets('wrong shows a cross', (tester) async {
      await tester.pumpWidget(wrap(tile(AnswerState.wrong)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('correct and wrong are told apart by colour, not just icon',
        (tester) async {
      await tester.pumpWidget(wrap(tile(AnswerState.correct)));
      await tester.pumpAndSettle();
      final (okFill, okBorder) = painted(tester);

      await tester.pumpWidget(wrap(tile(AnswerState.wrong)));
      await tester.pumpAndSettle();
      final (badFill, badBorder) = painted(tester);

      expect(okBorder, isNot(badBorder));
      expect(okFill, isNot(badFill));
    });

    testWidgets('the fill is a light tint, never a solid accent',
        (tester) async {
      // Eski dizaynning asosiy muammosi: butun qator to'q sariqqa
      // bo'yalardi va matn kontrastini yo'qotardi.
      for (final s in [AnswerState.correct, AnswerState.wrong]) {
        await tester.pumpWidget(wrap(tile(s)));
        await tester.pumpAndSettle();
        final (fill, border) = painted(tester);
        expect(fill!.a, lessThan(0.25),
            reason: '$s fill must stay a light tint');
        expect(border!.a, greaterThan(0.5),
            reason: '$s border must be solid enough to read');
      }
    });

    testWidgets('option text stays dark in every state', (tester) async {
      // Kulrang matn "o'chirilgan" degan ma'no beradi; variant esa
      // o'qilishi kerak bo'lgan asosiy matn.
      for (final s in AnswerState.values) {
        await tester.pumpWidget(wrap(tile(s)));
        await tester.pumpAndSettle();
        final ctx = tester.element(find.byType(AnswerTile));
        final palette = Theme.of(ctx).extension<AppPalette>()!;
        final style = tester.widget<Text>(find.text('В больнице')).style!;
        expect(style.color, isNot(palette.muted), reason: '$s');
        expect(style.color, isNot(palette.faint), reason: '$s');
      }
    });

    testWidgets('is at least 56px tall for a finger', (tester) async {
      await tester.pumpWidget(wrap(tile(AnswerState.idle)));
      expect(tester.getSize(find.byType(AnswerTile)).height,
          greaterThanOrEqualTo(56));
    });

    testWidgets('a null onTap makes it inert after checking', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(const AnswerTile(
          letter: 'A', text: 'В школе', state: AnswerState.correct,
          onTap: null)));
      await tester.tap(find.byType(AnswerTile), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('tapping an enabled tile fires once', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(AnswerTile(
          letter: 'A', text: 'В школе', state: AnswerState.idle,
          onTap: () => taps++)));
      await tester.tap(find.byType(AnswerTile));
      expect(taps, 1);
    });

    testWidgets('long option text wraps instead of overflowing at 360px',
        (tester) async {
      await tester.pumpWidget(wrap(
        const AnswerTile(
          letter: 'D',
          text: 'Потому что городской транспорт ходит намного чаще, '
              'чем раньше, и людям стало удобнее',
          state: AnswerState.idle,
          onTap: null,
        ),
        width: 360,
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('FeedbackBanner', () {
    testWidgets('correct shows the cheering owl and the XP chip',
        (tester) async {
      await tester.pumpWidget(wrap(const FeedbackBanner(
          correct: true, title: 'To’g’ri!', xp: 10)));
      expect(find.text('To’g’ri!'), findsOneWidget);
      expect(find.text('+10 XP'), findsOneWidget);
      final owl = tester.widget<OwlMascot>(find.byType(OwlMascot));
      expect(owl.mood, OwlMood.excited);
    });

    testWidgets('wrong names the right answer and encourages', (tester) async {
      await tester.pumpWidget(wrap(const FeedbackBanner(
          correct: false, title: 'Noto’g’ri, to’g’ri javob: B')));
      expect(find.text('Noto’g’ri, to’g’ri javob: B'), findsOneWidget);
      final owl = tester.widget<OwlMascot>(find.byType(OwlMascot));
      expect(owl.mood, OwlMood.encouraging);
      // Xato javobda XP berilmaydi.
      expect(find.textContaining('XP'), findsNothing);
    });

    testWidgets('shows the evidence sentence when there is one',
        (tester) async {
      await tester.pumpWidget(wrap(const FeedbackBanner(
        correct: true,
        title: 'To’g’ri!',
        evidenceLabel: 'Matndan dalil',
        evidence: 'Мой отец работает врачом.',
      )));
      expect(find.text('Matndan dalil'), findsOneWidget);
      expect(find.text('Мой отец работает врачом.'), findsOneWidget);
    });

    testWidgets('omits the evidence block when there is none', (tester) async {
      await tester.pumpWidget(wrap(const FeedbackBanner(
          correct: false, title: 'Noto’g’ri', evidenceLabel: 'Matndan dalil')));
      expect(find.text('Matndan dalil'), findsNothing);
    });
  });
}
