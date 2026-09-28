// Til bo'limining O'LCHAMGA moslashuvi va tegish maydonlari.
//
// Bu yerdagi xatolar ko'rinadi, lekin faqat MA'LUM bir kenglikda: telefon
// emulyatorida hammasi joyida, 360 px li arzon telefonda esa tugma matni
// kesilib qoladi yoki qator ekrandan chiqib ketadi.
//
// Ishga tushirish:
//     flutter test test/language_layout_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:topagon/l10n/app_localizations.dart';
import 'package:topagon/mascot/mascot.dart';
import 'package:topagon/theme/app_theme.dart';
import 'package:topagon/theme/level_palette.dart';
import 'package:topagon/widgets/language_kit.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('uz'),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('uz'), Locale('ru')],
      home: Scaffold(body: child),
    );

Future<void> atWidth(WidgetTester tester, double w, Widget child) async {
  tester.view.physicalSize = Size(w, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(child));
  await tester.pump();
}

void main() {
  group('LevelChip', () {
    testWidgets('every CEFR level renders and has its own colour',
        (tester) async {
      await atWidth(
        tester,
        375,
        Wrap(children: [for (final lv in LevelPalette.order) LevelChip(lv)]),
      );
      for (final lv in LevelPalette.order) {
        expect(find.text(lv), findsOneWidget);
      }
      // Ranglar takrorlanmasligi kerak — aks holda daraja rangdan
      // o'qilmaydi va chip bezakka aylanadi.
      final colours = {
        for (final lv in LevelPalette.order)
          LevelPalette.color(lv, Brightness.light).toARGB32()
      };
      expect(colours.length, LevelPalette.order.length);
    });
  });

  group('StatTile row', () {
    testWidgets('three tiles fit on a 360px phone without overflowing',
        (tester) async {
      // 360 px — bozordagi eng tor keng tarqalgan ekran.
      await atWidth(
        tester,
        360,
        const Row(
          children: [
            Expanded(
                child: StatTile(
                    icon: Icons.local_fire_department_outlined,
                    value: '12',
                    label: 'Bugun',
                    color: Colors.orange)),
            SizedBox(width: 8),
            Expanded(
                child: StatTile(
                    icon: Icons.menu_book_outlined,
                    value: '340',
                    label: 'Lug’atimda',
                    color: Colors.teal)),
            SizedBox(width: 8),
            Expanded(
                child: StatTile(
                    icon: Icons.verified_outlined,
                    value: '58',
                    label: 'Yodlangan',
                    color: Colors.purple)),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Lug’atimda'), findsOneWidget);
    });
  });

  group('TopicTile', () {
    Widget tile({TopicStatus status = TopicStatus.notStarted}) => TopicTile(
          title: 'Ravishlar: chastota va o’rni',
          subtitle: 'Adverbs of frequency + position',
          meta: '50 ta savol',
          status: status,
          progress: 0.4,
          level: 'A1',
          onTap: () {},
        );

    testWidgets('shows the Uzbek title with the English term beneath',
        (tester) async {
      await atWidth(tester, 375, tile());
      expect(find.text('Ravishlar: chastota va o’rni'), findsOneWidget);
      expect(find.text('Adverbs of frequency + position'), findsOneWidget);
    });

    testWidgets('a long title does not overflow a narrow screen',
        (tester) async {
      await atWidth(tester, 360, tile());
      expect(tester.takeException(), isNull);
    });

    testWidgets('done shows a check, not started shows no check',
        (tester) async {
      await atWidth(tester, 375, tile(status: TopicStatus.done));
      expect(find.byIcon(Icons.check), findsOneWidget);

      await atWidth(tester, 375, tile());
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('there is no radio affordance anywhere', (tester) async {
      // Radio "bittasini tanlang" degan ma'no beradi; bu qator esa holatni
      // KO'RSATADI. Eski ekrandagi asosiy tushunmovchilik shu edi.
      for (final st in TopicStatus.values) {
        await atWidth(tester, 375, tile(status: st));
        expect(find.byType(Radio), findsNothing);
        expect(find.byType(RadioListTile), findsNothing);
      }
    });

    testWidgets('the row is at least 48px tall for a finger', (tester) async {
      await atWidth(tester, 375, tile());
      final size = tester.getSize(find.byType(TopicTile));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('LevelProgressBar', () {
    testWidgets('shows the count and survives a zero total', (tester) async {
      await atWidth(
        tester,
        375,
        const Column(children: [
          LevelProgressBar(level: 'A1', done: 12, total: 34),
          // Bo'sh daraja — nolga bo'lish bo'lmasligi kerak.
          LevelProgressBar(level: 'C2', done: 0, total: 0),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('12/34'), findsOneWidget);
      expect(find.text('0/0'), findsOneWidget);
    });
  });

  group('ContentWidth', () {
    // BOLANI o'lchaymiz, `ConstrainedBox` ni emas: daraxtda Scaffold'ning
    // o'z `ConstrainedBox` lari ham bor va `.first` o'shalarni topadi.
    const child = SizedBox(key: Key('cw-child'), height: 10, width: 4000);

    testWidgets('caps the content on a desktop width', (tester) async {
      await atWidth(tester, 1280, const ContentWidth(child: child));
      final w = tester.getSize(find.byKey(const Key('cw-child'))).width;
      expect(w, lessThanOrEqualTo(kContentMaxWidth));
    });

    testWidgets('uses the full width on a phone', (tester) async {
      await atWidth(tester, 375, const ContentWidth(child: child));
      final w = tester.getSize(find.byKey(const Key('cw-child'))).width;
      expect(w, 375);
      expect(tester.takeException(), isNull);
    });
  });

  group('OwlEmptyState', () {
    testWidgets('renders an owl and the message', (tester) async {
      await atWidth(
        tester,
        375,
        const OwlEmptyState(
          state: OwlState.sleeping,
          title: 'Bugun takrorlaydigan so’z yo’q. Zo’r!',
          message: 'Yangi so’z qo’shsangiz, u navbatga tushadi.',
        ),
      );
      expect(find.byType(OwlMascot), findsOneWidget);
      expect(find.text('Bugun takrorlaydigan so’z yo’q. Zo’r!'),
          findsOneWidget);
    });

    testWidgets('sleeping and reading fall back to drawn poses',
        (tester) async {
      // Bu ikki poza hali chizilmagan. Ular mavjud rasmga tushishi kerak,
      // yo'q faylga emas — aks holda `errorBuilder` ularni `happy` ga
      // aylantirib, noto'g'ri kayfiyat berardi.
      expect(OwlState.sleeping.artIsMissing, isTrue);
      expect(OwlState.reading.artIsMissing, isTrue);
      expect(OwlState.sleeping.mood, isNot(OwlMood.happy));
      expect(OwlState.reading.mood, isNot(OwlMood.happy));
      for (final s in OwlState.values) {
        expect(OwlMood.values.contains(s.mood), isTrue,
            reason: '$s maps to a real pose');
      }
    });
  });

  group('PrimaryButton', () {
    testWidgets('is at least 48px tall and fires once', (tester) async {
      var taps = 0;
      await atWidth(
        tester,
        360,
        PrimaryButton(
            label: 'Takrorlashni boshlash',
            expand: true,
            onPressed: () => taps++),
      );
      expect(tester.getSize(find.byType(FilledButton)).height,
          greaterThanOrEqualTo(48));
      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
    });

    testWidgets('disabled does not fire', (tester) async {
      await atWidth(tester, 375,
          const PrimaryButton(label: 'Boshlash', onPressed: null));
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(tester.takeException(), isNull);
    });
  });
}
