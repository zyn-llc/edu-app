import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';


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


  static const lastUsername = 'auth.lastUsername';
}
