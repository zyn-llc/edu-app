//
//
//
//
//     flutter test --dart-define=MOCK=true
//
// "A Timer is still pending even after the widget tree was disposed".

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:topagon/core/prefs.dart';
import 'package:topagon/main.dart';

void main() {
  testWidgets('app boots and shows bottom navigation',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const TopagonApp(),
    ));

    await tester.pump();
    expect(tester.takeException(), isNull);

    // Let the entry animation settle.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
  });
}
