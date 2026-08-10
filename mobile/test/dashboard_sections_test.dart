//
//
// Ishga tushirish:
//     flutter test

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:topagon/auth/auth_models.dart';
import 'package:topagon/features/home/activity_sections.dart';
import 'package:topagon/features/subjects/subjects.dart';
import 'package:topagon/l10n/app_localizations.dart';
import 'package:topagon/theme/app_theme.dart';
import 'package:topagon/widgets/app_footer.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('uz'),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('uz'), Locale('ru')],
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    );

final _subjects = [
  Subject(
    id: 's1',
    code: 'matematika',
    name: 'Matematika',
    questionCount: 500,
    topicCount: 20,
    answered: 40,
    correct: 32,
    accuracy: 0.8,
    lastPracticedAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
];

Progress _progress({
  int answeredToday = 0,
  int correctToday = 0,
  int xpToday = 0,
  List<DayStat> week = const [],
}) =>
    Progress(
      xp: 840,
      level: 9,
      streakDays: 3,
      answered: 84,
      correct: 66,
      accuracy: 0.78,
      answeredToday: answeredToday,
      correctToday: correctToday,
      xpToday: xpToday,
      answered7d: 84,
      correct7d: 66,
      accuracy7d: 0.78,
      xp7d: 660,
      activeDays7d: 4,
      week: week,
    );

List<DayStat> _week(List<int> answered) {
  final today = DateTime.now();
  return [
    for (var i = 0; i < answered.length; i++)
      DayStat(
        date: today.subtract(Duration(days: answered.length - 1 - i)),
        answered: answered[i],
        correct: (answered[i] * 0.8).round(),
        isToday: i == answered.length - 1,
      ),
  ];
}

/// Ikki freym: birinchisi vidjetni quradi, ikkinchisi `flutter_animate`
/// qo'ygan `Timer(Duration.zero)` larni bo'shatadi (`enterStaggered`).
/// Aks holda test oxirida "A Timer is still pending".
///
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('DailyGoalCard', () {
    testWidgets('no progress is shown for a guest', (tester) async {
      await tester.pumpWidget(
          _wrap(DailyGoalCard(subjects: _subjects, progress: null)));
      await _settle(tester);

      expect(find.text('Bugungi maqsad'), findsOneWidget);
      expect(find.textContaining('/ $kDailyTarget'), findsNothing);
    });

    testWidgets('shows today\'s count and the questions left', (tester) async {
      await tester.pumpWidget(_wrap(DailyGoalCard(
        subjects: _subjects,
        progress: _progress(answeredToday: 12, correctToday: 9, xpToday: 90),
      )));
      await _settle(tester);

      expect(find.text('12 / 20'), findsOneWidget);
      expect(find.text('Yana 8 ta savol'), findsOneWidget);
      expect(find.text('+90 XP'), findsOneWidget);
      // 9/12 = 75%
      expect(find.text('75% aniqlik'), findsOneWidget);
      expect(find.text('3 kunlik seriya'), findsOneWidget);
    });

    testWidgets('the button disappears once the goal is met', (tester) async {
      await tester.pumpWidget(_wrap(DailyGoalCard(
        subjects: _subjects,
        progress: _progress(answeredToday: 22, correctToday: 20, xpToday: 200),
      )));
      await _settle(tester);

      expect(find.text('Bugungi maqsad bajarildi'), findsOneWidget);
      expect(find.text('Ertangi maqsad: 20 ta savol'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('WeekStrip', () {
    testWidgets('draws nothing when week is empty (older server)',
        (tester) async {
      await tester.pumpWidget(_wrap(WeekStrip(progress: _progress())));
      await _settle(tester);

      expect(find.text('Bu hafta'), findsNothing);
    });

    testWidgets('shows seven days and the total', (tester) async {
      await tester.pumpWidget(_wrap(WeekStrip(
        progress: _progress(week: _week([8, 0, 14, 20, 0, 0, 12])),
      )));
      await _settle(tester);

      expect(find.text('Bu hafta'), findsOneWidget);
      expect(find.text('84 ta savol'), findsOneWidget);
      expect(find.text('+660 XP'), findsOneWidget);
      expect(find.text('4 kun faol'), findsOneWidget);
      // Faol kunlar belgilanadi: 8, 14, 20, 12 — to'rtta (nol kunlar bo'sh
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
    });
  });

  group('AppFooter', () {
    // chap chetga yopishib qolardi — footerning o'ng yarmi bo'sh turardi.
    testWidgets('columns spread across the width on a wide screen',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const AppFooter.full()));
      await _settle(tester);

      final platforma = tester.getTopLeft(find.text('PLATFORMA')).dx;
      final bizBilan = tester.getTopLeft(find.text('BIZ BILAN')).dx;

      expect(platforma, lessThan(550));
      expect(bizBilan, greaterThan(700));
    });

    testWidgets('brand and columns stack on a narrow screen', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const AppFooter.full()));
      await _settle(tester);

      final brandY = tester.getTopLeft(find.text('Topag‘on')).dy;
      final colY = tester.getTopLeft(find.text('PLATFORMA')).dy;
      expect(colY, greaterThan(brandY));
    });
  });

  group('ContinueCard', () {
    testWidgets('not selectable before any practice', (tester) async {
      final fresh = [
        const Subject(id: 's2', code: 'biologiya', name: 'Biologiya',
            questionCount: 100),
      ];
      expect(ContinueCard.pick(fresh), isNull);
    });

    testWidgets('shows the last subject and its accuracy', (tester) async {
      await tester.pumpWidget(_wrap(ContinueCard(subjects: _subjects)));
      await _settle(tester);

      expect(find.text('Matematika'), findsOneWidget);
      expect(find.text('40 ta savol · 80% aniqlik'), findsOneWidget);
    });
  });
}
