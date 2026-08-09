import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:topagon/core/prefs.dart';
import 'package:topagon/main.dart';

/// DESKTOP kengligida ilova ko'tariladimi.
///
/// NEGA ALOHIDA TEST. `widget_test.dart` standart test o'lchamida (800x600)
/// ishlaydi — u yerda pastki `NavigationBar` chiziladi va `NavigationRail`
/// yo'li UMUMAN sinalmaydi. Natijada rail'ga `Expanded` qo'yilgan
/// o'zgarish barcha testlardan va `flutter analyze` dan o'tib, prodda OQ
/// EKRAN berdi:
///
///     BoxConstraints.debugAssertIsValid → RenderFlex._computeSizes
///     → RenderIntrinsicHeight.performLayout
///
/// Sabab: rail `IntrinsicHeight` ichida (kalta ekranda toshmasligi uchun),
/// intrinsic o'lchov esa flex bolani hisoblay olmaydi.
///
/// Bu test ikkala kenglikni ham qamrab oladi, ya'ni shu turdagi xato
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
    // Freymlar ketma-ketligi `widget_test.dart` dagi bilan bir xil va
    // xuddi shu sababdan: mock javobi 220 ms kechikadi, `flutter_animate`
    // esa har `Animate` uchun taymer qo'yadi va ular grid LAYOUT paytida
    // tug'iladi — ya'ni birinchi freymdan keyin. Ularni bo'shatmasa test
    // "A Timer is still pending" bilan yiqiladi.
    // `pumpAndSettle` ISHLAMAYDI: ilovada uzluksiz animatsiyalar bor.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('rail kengligida (1440) layout xatosiz quriladi', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('yoyilgan rail kengligida (1920) layout xatosiz quriladi',
      (tester) async {
    await pumpAt(tester, const Size(1920, 1080));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('telefon kengligida (390) pastki navigatsiya chiqadi',
      (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });
}
