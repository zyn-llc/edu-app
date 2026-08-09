# Bilim — Flutter app

Mobile client for the education quiz & competition platform. Material 3, Riverpod,
universal warm-orange + black theme (light + dark), Uzbek + Russian.

## What's in this drop (design system + first screen)

```
mobile/
├── design-tokens.json        single source of truth (import into Figma via Tokens Studio)
├── pubspec.yaml              deps, fonts, l10n, assets
├── l10n.yaml                 localization config (template = Uzbek)
└── lib/
    ├── main.dart             app root: light/dark theme, uz/ru locales
    ├── theme/
    │   ├── app_colors.dart   light + dark tokens + AppPalette extension
    │   ├── subject_palette.dart  per-subject accent colors + icons
    │   └── app_theme.dart    Material 3 ThemeData (light + dark)
    ├── l10n/
    │   ├── app_uz.arb        Uzbek strings (template)
    │   └── app_ru.arb        Russian strings
    ├── mascot/mascot.dart    EduOwl mood → asset mapping
    ├── api/api_client.dart   Dio + Accept-Language, base URLs
    └── features/subjects/
        ├── subjects.dart            model + repository + providers
        └── subject_grid_screen.dart the home grid (image-led, progress, accents)
```

## Run

```bash
cd mobile
flutter pub get        # also runs gen-l10n -> lib/l10n/app_localizations.dart
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator -> host
```

`10.0.2.2` is the Android emulator's alias for your machine's localhost (where the
FastAPI backend runs). For a physical device use your LAN IP or the deployed API.

## Drop in the mascot assets

Put the EduOwl expression PNGs (or a Rive file) in `assets/mascot/` named:

```
owl_happy.png  owl_thinking.png  owl_excited.png  owl_encouraging.png
owl_wow.png    owl_tip.png       owl_achievement.png  owl_oops.png
```

The `OwlMascot` widget falls back to `owl_happy.png` (then an empty box) if a
pose is missing, so the app never breaks on a not-yet-added asset.

## The one design rule encoded here

`primary` (orange) is the universal chrome color on every screen. Subject colors
(`SubjectPalette`) are accents only — covers, identity chips, progress fills.
This split lives in code so it can't drift from the design.

## Next

Screens to implement against the same system: auth (phone+OTP), subject picker
(grade/goal/topic), session setup, quiz (server timer), result (with mascot),
leaderboard, profile. The mockups for all of these are approved.
