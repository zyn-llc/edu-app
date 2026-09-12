// Join-flow gating for live sections (backend migration 040).
//
// The branch this locks down: a section with a FIXED school must not ask the
// student for one, and must not send `school_id` — the server ignores it and
// files the result under its own school. A section without one must ask, and
// must block the button until both ids are chosen. Getting this wrong fails
// silently: the student still joins, but under the wrong school, and it only
// surfaces in the hokimiyat report.
//
// Ishga tushirish:
//     flutter test test/live_section_join_test.dart

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:topagon/auth/auth_models.dart';
import 'package:topagon/auth/auth_controller.dart';
import 'package:topagon/features/geo/geo_data.dart';
import 'package:topagon/features/live_sections/join_sheet.dart';
import 'package:topagon/features/live_sections/live_sections_data.dart';
import 'package:topagon/l10n/app_localizations.dart';
import 'package:topagon/theme/app_theme.dart';

// --------------------------------------------------------------------------- //
//  Pure gating logic                                                           //
// --------------------------------------------------------------------------- //
void main() {
  group('JoinRequirements', () {
    test('fixed school: only mahalla is required', () {
      final r = JoinRequirements.forSection(schoolFixed: true);
      expect(r.needsSchool, isFalse);
      expect(r.needsMahalla, isTrue);
      expect(r.missing(mahallaId: 'm1'), isEmpty);
      expect(r.isComplete(mahallaId: 'm1'), isTrue);
    });

    test('fixed school: a missing mahalla is still reported', () {
      final r = JoinRequirements.forSection(schoolFixed: true);
      expect(r.missing(), ['mahalla_id']);
      expect(r.isComplete(), isFalse);
    });

    test('fixed school: no school never counts as missing', () {
      final r = JoinRequirements.forSection(schoolFixed: true);
      expect(r.missing(schoolId: null, mahallaId: 'm1'), isEmpty);
    });

    test('open section: both are required, in form order', () {
      final r = JoinRequirements.forSection(schoolFixed: false);
      expect(r.missing(), ['school_id', 'mahalla_id']);
      expect(r.isComplete(schoolId: 's1'), isFalse);
      expect(r.isComplete(mahallaId: 'm1'), isFalse);
      expect(r.isComplete(schoolId: 's1', mahallaId: 'm1'), isTrue);
    });

    test('empty strings count as unselected', () {
      final r = JoinRequirements.forSection(schoolFixed: false);
      expect(r.isComplete(schoolId: '', mahallaId: ''), isFalse);
    });
  });

  group('buildRegisterBody', () {
    test('fixed school: school_id is NOT sent even if the client has one', () {
      final body = buildRegisterBody(
          schoolFixed: true, schoolId: 's-other', mahallaId: 'm1');
      expect(body.containsKey('school_id'), isFalse);
      expect(body['mahalla_id'], 'm1');
    });

    test('open section: school_id is sent', () {
      final body =
          buildRegisterBody(schoolFixed: false, schoolId: 's1', mahallaId: 'm1');
      expect(body['school_id'], 's1');
      expect(body['mahalla_id'], 'm1');
    });

    test('class label is trimmed, upper-cased, and dropped when blank', () {
      expect(
        buildRegisterBody(
            schoolFixed: true, mahallaId: 'm1', classLabel: ' 9a ')['class_label'],
        '9A',
      );
      expect(
        buildRegisterBody(
            schoolFixed: true, mahallaId: 'm1', classLabel: '   '),
        isNot(contains('class_label')),
      );
    });

    test('no empty-string keys are ever sent', () {
      final body =
          buildRegisterBody(schoolFixed: false, schoolId: '', mahallaId: '');
      expect(body, isEmpty);
    });
  });

  group('RegisterFieldError', () {
    DioException dio(int status, Object? body) => DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: status,
              data: body),
        );

    test('parses missing_fields from a 422', () {
      final e = RegisterFieldError.fromDio(dio(422, {
        'title': 'Missing fields',
        'missing_fields': ['school_id', 'mahalla_id'],
      }))!;
      expect(e.isMissing('school_id'), isTrue);
      expect(e.isMissing('mahalla_id'), isTrue);
      expect(e.isStale, isFalse);
    });

    test('invalid_fields marks the cache stale', () {
      final e = RegisterFieldError.fromDio(dio(422, {
        'title': 'Invalid fields',
        'invalid_fields': ['mahalla_id'],
      }))!;
      expect(e.isInvalid('mahalla_id'), isTrue);
      expect(e.isMissing('mahalla_id'), isFalse);
      expect(e.isStale, isTrue);
    });

    test('other statuses are not field errors', () {
      expect(RegisterFieldError.fromDio(dio(409, {'title': 'Registration closed'})),
          isNull);
      expect(RegisterFieldError.fromDio(dio(500, 'boom')), isNull);
    });

    test('a 422 without the lists is not treated as a field error', () {
      expect(RegisterFieldError.fromDio(dio(422, {'title': 'Unprocessable'})),
          isNull);
    });
  });

  // ------------------------------------------------------------------------- //
  //  Widget: which pickers appear                                              //
  // ------------------------------------------------------------------------- //
  group('JoinSheet', () {
    LiveSectionDetail detail({required bool schoolFixed}) => LiveSectionDetail(
          id: 'sec-1',
          title: 'Matematika sinovi',
          description: null,
          status: 'scheduled',
          startAt: DateTime.now().add(const Duration(hours: 1)),
          endAt: DateTime.now().add(const Duration(hours: 3)),
          isProctored: true,
          maxAttempts: 1,
          registered: false,
          schoolFixed: schoolFixed,
          school: schoolFixed
              ? const GeoSchool(
                  id: 'sch-1',
                  regionCode: 'toshkent_shahri',
                  districtId: 'd1',
                  district: 'Chilonzor',
                  number: 5,
                  name: null,
                )
              : null,
          blocks: const [],
        );

    Widget wrap(Widget child) => ProviderScope(
          overrides: [
            // The geo lists are overridden, so nothing touches the network or
            // the auth/SharedPreferences chain.
            regionsProvider.overrideWith(
                (ref) => [Region('toshkent_shahri', 'Toshkent shahri', 'Ташкент')]),
            districtsProvider.overrideWith((ref, arg) => const <GeoDistrict>[]),
            mahallasProvider.overrideWith((ref, arg) => const <GeoMahalla>[]),
            schoolsProvider.overrideWith((ref, arg) => const <GeoSchool>[]),
          ],
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
            home: Scaffold(body: child),
          ),
        );

    testWidgets('fixed school: no school picker, mahalla picker shown',
        (tester) async {
      await tester.pumpWidget(wrap(JoinSheet(detail: detail(schoolFixed: true))));
      await tester.pump();

      expect(find.byKey(const Key('join-school-picker')), findsNothing);
      expect(find.byKey(const Key('join-fixed-school')), findsOneWidget);
      expect(find.byKey(const Key('join-mahalla-picker')), findsOneWidget);
    });

    testWidgets('fixed school: the school is shown read-only', (tester) async {
      await tester.pumpWidget(wrap(JoinSheet(detail: detail(schoolFixed: true))));
      await tester.pump();

      expect(find.text('5-maktab'), findsOneWidget);
      // No editable field carries it — it is a ListTile, not an input.
      expect(find.widgetWithText(TextField, '5-maktab'), findsNothing);
    });

    testWidgets('open section: both pickers are shown', (tester) async {
      await tester
          .pumpWidget(wrap(JoinSheet(detail: detail(schoolFixed: false))));
      await tester.pump();

      expect(find.byKey(const Key('join-school-picker')), findsOneWidget);
      expect(find.byKey(const Key('join-mahalla-picker')), findsOneWidget);
      expect(find.byKey(const Key('join-fixed-school')), findsNothing);
    });

    testWidgets('join stays disabled until the required ids are chosen',
        (tester) async {
      for (final fixed in [true, false]) {
        await tester.pumpWidget(wrap(JoinSheet(detail: detail(schoolFixed: fixed))));
        await tester.pump();

        final button = tester
            .widget<FilledButton>(find.byKey(const Key('join-submit')));
        expect(button.onPressed, isNull,
            reason: 'nothing selected yet (schoolFixed=$fixed)');
      }
    });
  });
}
