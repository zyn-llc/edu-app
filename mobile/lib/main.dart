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

  // Bellashuv havolasi: `https://topagon.uz/?join=KOD`. Manzil FAQAT shu
  // yerda, ilova ko'tarilishidan oldin o'qiladi — keyinroq Flutter Web
  // manzilni o'zgartirib yuborishi mumkin.
  final joinCode = pendingJoinCodeFromUrl();
  // Umumiy taklif havolasi: `https://topagon.uz/?ref=USERNAME`. `?join=`
  // dan farqli o'laroq bellashuvga emas, ilovaning o'ziga taklif.
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
      // Oldin bu yerda qattiq `maxWidth: 460` turardi — ilova desktopda va
      // webda telefon shaklidagi tor ustunga qamalib qolar edi. Endi kenglik
      // cheklovi yo'q: `HomeShell` keng ekranda `NavigationRail` ga o'tadi,
      // matnli ichki ekranlar esa `ContentWidth` bilan o'raladi.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          // Tizim shrifti juda katta qilib qo'yilsa (Androidda 2.0 gacha
          // mumkin) tugmalardagi matn sig'may, layout overflow beradi.
          // 1.3 — o'qish uchun yetarli, dizaynni buzmaydigan chegara.
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
