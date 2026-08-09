// Ilova ko'tarilishining eng oddiy smoke testi.
//
// Eski fayl Flutter shablonidagi counter testi edi va mavjud bo'lmagan
// `MyApp` ni chaqirardi — `flutter analyze` va `flutter test` shu sababli
// yiqilardi. Bu versiya haqiqiy ildiz vidjetni ko'taradi.
//
// Test MOCK backend bilan ishlaydi: tarmoqqa chiqmaydi.
//
// MUHIM: `--dart-define=MOCK=true` BILAN ishga tushiring, aks holda `Dio`
// haqiqiy so'rov qilishga urinadi:
//
//     flutter test --dart-define=MOCK=true
//
// Mock javobi 220 ms kechikish bilan keladi (`mock_backend.dart`), shuning
// uchun test oxirida shu taymer tugaguncha kutish kerak — bo'lmasa
// "A Timer is still pending even after the widget tree was disposed".

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:topagon/core/prefs.dart';
import 'package:topagon/main.dart';

void main() {
  testWidgets("Topag'on ko'tariladi va pastki navigatsiya chiqadi",
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const TopagonApp(),
    ));

    // Birinchi freym: providerlar hali yuklanmoqda, exception bo'lmasligi kerak.
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Mock javoblari kelib, ekran to'liq qurilgan holat. `pumpAndSettle`
    // EMAS: ilovada uzluksiz animatsiyalar bor (fan ikonkalari, FAB
    // porlashi) va u hech qachon "tinchimaydi" — test timeout bilan
    // yiqilardi.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // `flutter_animate` har bir `Animate` uchun `Timer(Duration.zero)`
    // qo'yadi (`_AnimateState._restart`) va ular grid LAYOUT paytida, ya'ni
    // yuqoridagi freymdan KEYIN yaratiladi. Yana bir freym — ular ishga
    // tushib bo'shaydi, aks holda test oxirida "Timer is still pending".
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
  });
}
