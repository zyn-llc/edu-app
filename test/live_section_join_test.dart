// Join-flow gating for live sections.
//
// Three rules are locked down here, each of which broke production once:
//
//   1. (040) A section with a FIXED school must not ask the student for one
//      and must not send one — the server files the result under its own
//      school. Getting this wrong fails silently: the student still joins,
//      but under the wrong school, and it only surfaces in the hokimiyat
//      report.
//   2. (041) A section may limit itself to named classes. Then the class is
//      required and must come from that list, so the form offers a dropdown
//      rather than a text box that can only produce a 422.
//   3. (2026-09-19) District, mahalla and school number are TYPED, not
//      picked. The reference tables were empty in production, so the old
//      cascade dead-ended and nobody could register at all.
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
    const full = (
      region: 'toshkent_shahri',
      district: 'Chilonzor',
      mahalla: 'Qatortol',
    );

    test('open section: every field including the school number', () {
      final r = JoinRequirements.forSection(schoolFixed: false);
      expect(r.needsSchoolNumber, isTrue);
      expect(r.missing(), [
        'region_code',
        'district_name',
        'mahalla_name',
        'school_number',
      ]);
      expect(
        r.isComplete(
            regionCode: full.region,
            districtName: full.district,
            mahallaName: full.mahalla,
            schoolNumber: 5),
        isTrue,
      );
    });

    test('fixed school: the school number is never asked for', () {
      final r = JoinRequirements.forSection(schoolFixed: true);
      expect(r.needsSchoolNumber, isFalse);
      expect(r.missing(), ['region_code', 'district_name', 'mahalla_name']);
      expect(
        r.isComplete(
            regionCode: full.region,
            districtName: full.district,
            mahallaName: full.mahalla),
        isTrue,
      );
    });

    test('whitespace-only names do not count', () {
      final r = JoinRequirements.forSection(schoolFixed: true);
      expect(
        r.missing(
            regionCode: full.region, districtName: '   ', mahallaName: '  '),
        ['district_name', 'mahalla_name'],
      );
    });

    test('a one-letter district is rejected before it reaches the server', () {
      // Two characters is the server's own CHECK; anything shorter would
      // just fill the reference tables with rubbish.
      final r = JoinRequirements.forSection(schoolFixed: true);
      expect(
        r.missing(
            regionCode: full.region, districtName: 'C', mahallaName: 'Qq'),
        ['district_name'],
      );
    });

    test('school numbers outside the database CHECK are rejected', () {
      final r = JoinRequirements.forSection(schoolFixed: false);
      for (final n in [0, -3, 10000]) {
        expect(
          r.missing(
              regionCode: full.region,
              districtName: full.district,
              mahallaName: full.mahalla,
              schoolNumber: n),
          ['school_number'],
          reason: 'school number $n is impossible',
        );
      }
    });

    // 041 -------------------------------------------------------------- //

    test('no class limit: the class stays optional', () {
      final r = JoinRequirements.forSection(schoolFixed: true);
      expect(r.needsClass, isFalse);
      expect(
        r.isComplete(
            regionCode: full.region,
            districtName: full.district,
            mahallaName: full.mahalla),
        isTrue,
      );
    });

    test('class-restricted: the class is required, reported last', () {
      final r = JoinRequirements.forSection(
          schoolFixed: false, classRestricted: true);
      expect(r.needsClass, isTrue);
      // Same order as the server's missing_fields, so highlighting lines up.
      expect(r.missing(), [
        'region_code',
        'district_name',
        'mahalla_name',
        'school_number',
        'class_label',
      ]);
      expect(
        r.isComplete(
            regionCode: full.region,
            districtName: full.district,
            mahallaName: full.mahalla,
            schoolNumber: 5),
        isFalse,
      );
      expect(
        r.isComplete(
            regionCode: full.region,
            districtName: full.district,
            mahallaName: full.mahalla,
            schoolNumber: 5,
            classLabel: '9-A'),
        isTrue,
      );
    });
  });

  group('normalizeGeoName', () {
    test('collapses whitespace but keeps the display case', () {
      // The server stores the display form and dedupes on lower(name), so
      // the client must not lower-case it here.
      expect(normalizeGeoName('  Chilonzor   5 '), 'Chilonzor 5');
      expect(normalizeGeoName(null), '');
    });
  });

  group('buildRegisterBody', () {
    test('fixed school: no school_number is sent even if one was typed', () {
      final body = buildRegisterBody(
          schoolFixed: true,
          regionCode: 'toshkent_shahri',
          districtName: 'Chilonzor',
          mahallaName: 'Qatortol',
          schoolNumber: 7);
      expect(body.containsKey('school_number'), isFalse);
      expect(body['district_name'], 'Chilonzor');
      expect(body['mahalla_name'], 'Qatortol');
    });

    test('open section: the school number is sent', () {
      final body = buildRegisterBody(
          schoolFixed: false,
          regionCode: 'toshkent_shahri',
          districtName: 'Chilonzor',
          mahallaName: 'Qatortol',
          schoolNumber: 5);
      expect(body['school_number'], 5);
      expect(body['region_code'], 'toshkent_shahri');
    });

    test('names are whitespace-normalised, not lower-cased', () {
      final body = buildRegisterBody(
          schoolFixed: true,
          regionCode: 'toshkent_shahri',
          districtName: '  Chilonzor   tumani ',
          mahallaName: ' Qatortol  ');
      expect(body['district_name'], 'Chilonzor tumani');
      expect(body['mahalla_name'], 'Qatortol');
    });

    test('class label is trimmed, upper-cased, and dropped when blank', () {
      expect(
        buildRegisterBody(schoolFixed: true, classLabel: ' 9a ')['class_label'],
        '9A',
      );
      expect(
        buildRegisterBody(schoolFixed: true, classLabel: '   '),
        isNot(contains('class_label')),
      );
    });

    test('no empty-string keys are ever sent', () {
      expect(buildRegisterBody(schoolFixed: false), isEmpty);
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
        'missing_fields': ['district_name', 'mahalla_name'],
      }))!;
      expect(e.isMissing('district_name'), isTrue);
      expect(e.isMissing('mahalla_name'), isTrue);
      expect(e.isStale, isFalse);
    });

    test('invalid_fields marks the value unusable', () {
      final e = RegisterFieldError.fromDio(dio(422, {
        'title': 'Invalid fields',
        'invalid_fields': ['region_code'],
      }))!;
      expect(e.isInvalid('region_code'), isTrue);
      expect(e.isMissing('region_code'), isFalse);
      expect(e.isStale, isTrue);
    });

    test('other statuses are not field errors', () {
      expect(
          RegisterFieldError.fromDio(dio(409, {'title': 'Registration closed'})),
          isNull);
      expect(RegisterFieldError.fromDio(dio(500, 'boom')), isNull);
    });

    test('a 422 without the lists is not treated as a field error', () {
      expect(RegisterFieldError.fromDio(dio(422, {'title': 'Unprocessable'})),
          isNull);
    });
  });

  // ------------------------------------------------------------------------- //
  //  Widget: which fields appear                                               //
  // ------------------------------------------------------------------------- //
  group('JoinSheet', () {
    LiveSectionDetail detail({
      required bool schoolFixed,
      List<String> classes = const [],
    }) =>
        LiveSectionDetail(
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
          classes: classes,
          blocks: const [],
        );

    Widget wrap(Widget child, {List<GeoDistrict> districts = const []}) =>
        ProviderScope(
          overrides: [
            // Nothing touches the network or the auth/SharedPreferences
            // chain. `districts` is empty by default — that is exactly the
            // production state this redesign exists for.
            regionsProvider.overrideWith((ref) =>
                [Region('toshkent_shahri', 'Toshkent shahri', 'Ташкент')]),
            districtsProvider.overrideWith((ref, arg) => districts),
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

    testWidgets('open section: district, mahalla and school number are typed',
        (tester) async {
      await tester
          .pumpWidget(wrap(JoinSheet(detail: detail(schoolFixed: false))));
      await tester.pump();

      expect(find.byKey(const Key('join-region')), findsOneWidget);
      expect(find.byKey(const Key('join-district')), findsOneWidget);
      expect(find.byKey(const Key('join-mahalla')), findsOneWidget);
      expect(find.byKey(const Key('join-school-number')), findsOneWidget);
      expect(find.byKey(const Key('join-fixed-school')), findsNothing);
    });

    testWidgets('fixed school: shown read-only, no school number asked',
        (tester) async {
      await tester
          .pumpWidget(wrap(JoinSheet(detail: detail(schoolFixed: true))));
      await tester.pump();

      expect(find.byKey(const Key('join-fixed-school')), findsOneWidget);
      expect(find.byKey(const Key('join-school-number')), findsNothing);
      expect(find.text('5-maktab'), findsOneWidget);
      // It is a ListTile, not an input — nothing editable carries it.
      expect(find.widgetWithText(TextField, '5-maktab'), findsNothing);
    });

    testWidgets('an empty reference list still lets the form be filled in',
        (tester) async {
      // The regression this whole redesign is about: with zero districts the
      // old cascade offered nothing and the button could never enable.
      await tester.pumpWidget(wrap(
        JoinSheet(
          detail: detail(schoolFixed: true),
          initialRegionCode: 'toshkent_shahri',
        ),
      ));
      await tester.pump();

      FilledButton submit() =>
          tester.widget<FilledButton>(find.byKey(const Key('join-submit')));
      expect(submit().onPressed, isNull);

      await tester.enterText(find.byKey(const Key('join-district')), 'Chilonzor');
      await tester.pump();
      expect(submit().onPressed, isNull, reason: 'mahalla still empty');

      await tester.enterText(find.byKey(const Key('join-mahalla')), 'Qatortol');
      await tester.pump();

      expect(submit().onPressed, isNotNull,
          reason: 'typing alone must be enough to register');
    });

    testWidgets('open section: join stays blocked until a school number is in',
        (tester) async {
      await tester.pumpWidget(wrap(
        JoinSheet(
          detail: detail(schoolFixed: false),
          initialRegionCode: 'toshkent_shahri',
        ),
      ));
      await tester.pump();

      FilledButton submit() =>
          tester.widget<FilledButton>(find.byKey(const Key('join-submit')));

      await tester.enterText(find.byKey(const Key('join-district')), 'Chilonzor');
      await tester.enterText(find.byKey(const Key('join-mahalla')), 'Qatortol');
      await tester.pump();
      expect(submit().onPressed, isNull);

      await tester.enterText(find.byKey(const Key('join-school-number')), '5');
      await tester.pump();
      expect(submit().onPressed, isNotNull);
    });

    testWidgets('known districts are offered as chips so spellings converge',
        (tester) async {
      await tester.pumpWidget(wrap(
        JoinSheet(
          detail: detail(schoolFixed: true),
          initialRegionCode: 'toshkent_shahri',
        ),
        districts: const [
          GeoDistrict(
              id: 'd1', regionCode: 'toshkent_shahri', name: 'Chilonzor'),
        ],
      ));
      await tester.pump();

      final chip = find.widgetWithText(ActionChip, 'Chilonzor');
      expect(chip, findsOneWidget);

      await tester.tap(chip);
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byKey(const Key('join-district'))).controller!.text,
        'Chilonzor',
      );
    });

    testWidgets('no chips are shown when the reference list is empty',
        (tester) async {
      await tester.pumpWidget(wrap(
        JoinSheet(
          detail: detail(schoolFixed: true),
          initialRegionCode: 'toshkent_shahri',
        ),
      ));
      await tester.pump();

      expect(find.byKey(const Key('join-district-suggestions')), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
    });

    // 041 -------------------------------------------------------------- //

    testWidgets('no class limit: the free-text class field is shown',
        (tester) async {
      await tester
          .pumpWidget(wrap(JoinSheet(detail: detail(schoolFixed: true))));
      await tester.pump();

      expect(find.byKey(const Key('join-class-label')), findsOneWidget);
      expect(find.byKey(const Key('join-class-picker')), findsNothing);
    });

    testWidgets('class-restricted: a dropdown replaces the free-text field',
        (tester) async {
      await tester.pumpWidget(wrap(JoinSheet(
          detail: detail(schoolFixed: true, classes: const ['9-A', '9-B']))));
      await tester.pump();

      // A free text box here would only ever produce a 422 the student
      // cannot act on, so it must be gone.
      expect(find.byKey(const Key('join-class-label')), findsNothing);
      expect(find.byKey(const Key('join-class-picker')), findsOneWidget);
    });

    testWidgets('class-restricted: the dropdown offers exactly the allowed '
        'classes', (tester) async {
      await tester.pumpWidget(wrap(JoinSheet(
          detail: detail(schoolFixed: true, classes: const ['9-A', '9-B']))));
      await tester.pump();

      final picker = find.byKey(const Key('join-class-picker'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();

      expect(find.text('9-A'), findsWidgets);
      expect(find.text('9-B'), findsWidgets);
      expect(find.text('10-A'), findsNothing);
    });

    testWidgets('class-restricted: the class is one more gate, not a '
        'replacement', (tester) async {
      await tester.pumpWidget(wrap(JoinSheet(
          detail: detail(schoolFixed: true, classes: const ['9-A']))));
      await tester.pump();

      FilledButton submit() =>
          tester.widget<FilledButton>(find.byKey(const Key('join-submit')));

      final picker = find.byKey(const Key('join-class-picker'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('9-A').last);
      await tester.pumpAndSettle();

      // Region, district and mahalla are still missing.
      expect(submit().onPressed, isNull);
    });
  });
}
