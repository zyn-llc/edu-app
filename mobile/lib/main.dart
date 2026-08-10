import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_localizations.dart';
import 'api/api_client.dart';
import 'core/app_settings.dart';
import 'core/prefs.dart';
import 'features/challenges/challenge_invite.dart';
import 'features/home/home_shell.dart';
import 'features/referral/invite_friends.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Restore persisted settings as the initial provider state.
  final savedTheme = switch (prefs.getString(PrefKeys.themeMode)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  final savedLocale = prefs.getString(PrefKeys.locale) ?? 'uz-Latn';
  final savedSound = prefs.getBool(PrefKeys.sound) ?? true;

  // Read the deep-link codes before the router can rewrite the URL.
  final joinCode = pendingJoinCodeFromUrl();
  final referrer = pendingReferrerFromUrl();

  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      themeModeProvider.overrideWith((_) => savedTheme),
      localeCodeProvider.overrideWith((_) => savedLocale),
      soundEnabledProvider.overrideWith((_) => savedSound),
      pendingJoinCodeProvider.overrideWith((_) => joinCode),
      pendingReferrerProvider.overrideWith((_) => referrer),
    ],
    child: const TopagonApp(),
  ));
}

class TopagonApp extends ConsumerWidget {
  const TopagonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Persist settings whenever they change (write-through to SharedPreferences).
    final prefs = ref.watch(sharedPreferencesProvider);
    ref.listen<ThemeMode>(themeModeProvider, (_, m) {
      prefs.setString(PrefKeys.themeMode, m.name);
    });
    ref.listen<String>(localeCodeProvider, (_, c) {
      prefs.setString(PrefKeys.locale, c);
    });
    ref.listen<bool>(soundEnabledProvider, (_, v) {
      prefs.setBool(PrefKeys.sound, v);
    });

    final themeMode = ref.watch(themeModeProvider);
    final lang = ref.watch(localeCodeProvider);
    return MaterialApp(
      onGenerateTitle: (ctx) => L10n.of(ctx).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: Locale(lang == 'ru' ? 'ru' : 'uz'),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('uz'), Locale('ru')],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeShell(),
    );
  }
}
