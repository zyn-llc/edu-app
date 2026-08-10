import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:topagon/core/prefs.dart';
import 'package:topagon/main.dart';

///
/// ishlaydi — u yerda pastki `NavigationBar` chiziladi va `NavigationRail`
///
///     BoxConstraints.debugAssertIsValid → RenderFlex._computeSizes
///     → RenderIntrinsicHeight.performLayout
///
///
/// boshqa jim o'tolmaydi.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const TopagonApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('builds without layout errors at rail width (1440)', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('builds without layout errors at extended rail width (1920)',
      (tester) async {
    await pumpAt(tester, const Size(1920, 1080));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  // 27 dyuymli monitor. `WindowSize.extraLarge` markaziy ustunni 1440 px ga
  // kenglikda 1440/1920 dan BOSHQA vidjet daraxti quriladi. Qamrovsiz
  testWidgets('builds without layout errors on a wide monitor (2560)', (tester) async {
    await pumpAt(tester, const Size(2560, 1440));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('shows bottom navigation at phone width (390)',
      (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });
}
