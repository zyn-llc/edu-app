import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the [SharedPreferences] instance. Overridden in main() once it has been
/// loaded, so the rest of the app can read it synchronously. Works on mobile and
/// web (web backs it with localStorage).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

/// Preference keys, in one place so they can't drift.
class PrefKeys {
  static const themeMode = 'settings.themeMode'; // 'system' | 'light' | 'dark'
  static const locale = 'settings.locale'; //       'uz-Latn' | 'ru'
  static const sound = 'settings.sound'; //          bool
  static const accessToken = 'auth.access';
  static const refreshToken = 'auth.refresh';

  /// Shu qurilmada oxirgi marta muvaffaqiyatli ishlatilgan foydalanuvchi nomi.
  ///
  /// Kirish ekrani uni oldindan to'ldiradi. Sinovchilar aynan shundan
  /// shikoyat qilishdi: hisob bor, lekin har safar nomni eslab, qaytadan
  /// terish kerak — va bitta harf xato bo'lsa «nom yoki parol noto'g'ri»
  /// chiqadi, o'quvchi esa parolni ayblaydi.
  ///
  /// PAROL SAQLANMAYDI, faqat nom. Nom maxfiy emas — u reytingda va
  /// bellashuv havolasida allaqachon ko'rinadi.
  static const lastUsername = 'auth.lastUsername';
}
