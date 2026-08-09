import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/breakpoints.dart';
import '../../l10n/app_localizations.dart';
import '../challenges/challenge_invite.dart';
import '../challenges/challenges_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../parent/parent_screen.dart';
import '../../theme/app_colors.dart';
import '../notes/notes_screen.dart';
import '../settings/settings_screen.dart';
import 'dashboard_screen.dart';

/// Ochiq tab indeksi: 0 Asosiy · 1 Reyting · 2 Bellashuv · 3 Ota-ona.
///
/// NEGA PROVIDER, oddiy `setState` emas (2026-08-08). Bosh ekranning pastidagi
/// bloklar — bellashuv kartasi va footer havolalari — boshqa tablarga olib
/// borishi kerak. Ular `HomeShell` ning BOLASI emas (`IndexedStack` ichida
/// alohida ekran), ya'ni uning `State` iga qo'ng'iroq qila olmaydi. Callback'ni
/// besh qavat pastga uzatish o'rniga bitta provider.
final homeTabProvider = StateProvider<int>((_) => 0);

/// Ilovaning ildiz qobig'i.
///
/// Telefonda pastda `NavigationBar`, kengroq ekranda chapda `NavigationRail`.
/// Ikkalasi ham AYNAN bir xil `IndexedStack` ni boshqaradi — shuning uchun
/// brauzer oynasi kengaytirilganda ochiq tab va uning holati (scroll, forma)
/// saqlanib qoladi.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

/// Bitta manzil. Rekord (`(IconData, IconData, String)`) o'rniga sinf:
/// `dest.icon` `dest.$1` dan ancha o'qiluvchan va kelajakda maydon
/// qo'shilsa chaqiruv joylari buzilmaydi.
class _Dest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _Dest(this.icon, this.selectedIcon, this.label);
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _screens = <Widget>[
    DashboardScreen(),
    LeaderboardScreen(),
    ChallengesScreen(),
    ParentScreen(),
  ];

  static const _challengesTab = 2;

  /// Qaysi tablar KAMIDA BIR MARTA ochilgan.
  ///
  /// Oddiy `IndexedStack` to'rtala ekranni ilova ochilishi bilan quradi.
  /// Ikkita yomon oqibati bor:
  ///
  ///  1. **To'rtta tarmoq so'rovi bir vaqtda.** Reyting, bellashuv va
  ///     ota-ona ma'lumotlari foydalanuvchi ularni ko'rmasdan turib
  ///     yuklanadi — 2 GB RAM li VPS va sekin TAS-IX kanalida bu sezilarli.
  ///  2. **Kirish animatsiyalari behuda ishlaydi.** Ular ko'rinmas ekranda
  ///     tugab qoladi va foydalanuvchi tabni ochganda kontent shunchaki
  ///     "paydo bo'ladi".
  ///
  /// Yechim: ekran birinchi marta ochilganda quriladi, keyin `IndexedStack`
  /// uni holati bilan saqlab qoladi (qayta yuklanmaydi).
  final Set<int> _visited = {};

  @override
  void initState() {
    super.initState();
    // Bellashuv havolasi bilan kirilgan bo'lsa darhol o'sha tabni ochamiz.
    if (ref.read(pendingJoinCodeProvider) != null) {
      ref.read(homeTabProvider.notifier).state = _challengesTab;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final size = context.windowSize;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final tab = ref.watch(homeTabProvider);
    // Ochilgan tabni belgilab qo'yamiz. `build` ichida mutatsiya ataylab:
    // amal idempotent va qayta qurishni keltirib chiqarmaydi, `IndexedStack`
    // bolalari esa shu qatordan KEYIN quriladi — ya'ni birinchi kadrda ham
    // to'g'ri ekran ko'rinadi.
    _visited.add(tab);

    final dests = <_Dest>[
      _Dest(Icons.home_outlined, Icons.home, l.navHome),
      _Dest(Icons.leaderboard_outlined, Icons.leaderboard, l.navLeaderboard),
      _Dest(Icons.emoji_events_outlined, Icons.emoji_events, l.navChallenges),
      _Dest(Icons.family_restroom_outlined, Icons.family_restroom, l.navParent),
    ];

    final body = IndexedStack(
      index: tab,
      children: [
        for (var i = 0; i < _screens.length; i++)
          _visited.contains(i) ? _screens[i] : const SizedBox.shrink(),
      ],
    );

    if (!size.useRail) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: _select,
          destinations: [
            for (final d in dests)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    final extended = size.useExtendedRail;

    return Scaffold(
      body: Row(
        children: [
          // `NavigationRail` cheksiz balandlikda quriladi, shuning uchun
          // kichik ekranda toshib ketmasligi uchun scroll bilan o'raymiz.
          // Yon panel FONI.
          //
          // Ilgari u `scheme.surface` — kontent bilan AYNAN bir xil oq edi,
          // ya'ni panel alohida hudud sifatida umuman ko'rinmasdi: to'rtta
          // yozuv bo'shliqda osilib turardi. Juda yumshoq apelsin tint
          // (yuqoridan pastga so'nadi) uni brend hududiga aylantiradi,
          // lekin kontentdan diqqatni tortmaydi.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.primaryTint,
                  palette.primaryTint.withValues(alpha: 0.25),
                ],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: tab,
                      onDestinationSelected: _select,
                      extended: extended,
                      // Fon yuqorida chizilgan — rail o'zi shaffof bo'lishi
                      // kerak, aks holda gradientni bosib qo'yadi.
                      backgroundColor: Colors.transparent,
                      // MUHIM: `extended: true` bo'lganda `labelType` NULL
                      // bo'lishi SHART — aks holda Flutter assert bilan
                      // yiqiladi ("Cannot set both extended and labelType").
                      labelType:
                          extended ? null : NavigationRailLabelType.selected,
                      leading: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: _RailBrand(),
                      ),
                      // Qisqa yo'llar — manzillardan darhol keyin.
                      //
                      // `Expanded` bilan pastga QOQIB QO'YIB BO'LMAYDI: rail
                      // `IntrinsicHeight` ichida turadi (kalta ekranda
                      // toshib ketmasligi uchun), intrinsic o'lchov esa
                      // flex bolani hisoblay olmaydi va butun ilova oq
                      // ekranga aylanadi:
                      //   BoxConstraints.debugAssertIsValid → RenderFlex
                      //   → RenderIntrinsicHeight.performLayout
                      // Bu `flutter analyze` ko'rmaydigan, faqat ISH
                      // VAQTIDA chiqadigan xato — shuning uchun
                      // `test/rail_desktop_test.dart` qo'shildi.
                      trailing: _RailShortcuts(extended: extended),
                      destinations: [
                        for (final d in dests)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          // 1920 px monitorda kontent butun ekran bo'ylab cho'zilib ketmasin:
          // uzun qatorda ko'z bir satrdan ikkinchisiga o'ta olmaydi. Rail
          // rejimida bitta shu joyda cheklaymiz — har bir tab ekranini
          // alohida o'rash shart emas.
          Expanded(child: ContentWidth(maxWidth: 1100, child: body)),
        ],
      ),
    );
  }

  void _select(int i) {
    _visited.add(i);
    ref.read(homeTabProvider.notifier).state = i;
  }
}

/// Rail tepasidagi kichik logo. Faqat desktopda ko'rinadi — telefonda
/// yuqori panel joyni behuda egallagan bo'lardi.
///
/// 2026-08-07: haqiqiy logotip keldi (`assets/logo.png`, `pubspec.yaml` da
/// bundle qilingan). Ilgari bu joyda `Icons.school_rounded` turardi —
/// brendga aloqasi yo'q vaqtinchalik belgi edi.
class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    return const CircleAvatar(
      radius: 18,
      backgroundImage: AssetImage('assets/logo.png'),
    );
  }
}

/// Yon panelning pastidagi qisqa yo'llar: Daftarim va Sozlamalar.
///
/// Ular tab EMAS — `IndexedStack` da o'z ekrani yo'q va shu holda qolishi
/// kerak: to'rtta asosiy bo'lim ustiga yana ikkita qo'shish navigatsiyani
/// og'irlashtiradi. Lekin desktopda ularga kirishning yagona yo'li bosh
/// ekran footeri edi, ya'ni boshqa tabda turgan odam ularni topa olmasdi.
class _RailShortcuts extends StatelessWidget {
  const _RailShortcuts({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final palette = Theme.of(context).extension<AppPalette>()!;

    final items = <(IconData, String, VoidCallback)>[
      (Icons.menu_book_rounded, l.notesTitle, () => NotesScreen.open(context)),
      (Icons.settings_rounded, l.settings, () {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()));
      }),
    ];

    // HECH QANDAY `Expanded` VA `double.infinity` — bu vidjet
    // `NavigationRail` ning `trailing` i sifatida `IntrinsicHeight` ichiga
    // tushadi. Intrinsic o'lchov cheksiz kenglikni ham, flex bolani ham
    // hisoblay olmaydi va butun ilova OQ EKRANGA aylanadi:
    //     BoxConstraints forces an infinite width
    // Bu `flutter analyze` ko'rmaydigan, faqat ish vaqtida chiqadigan
    // xato — `test/rail_desktop_test.dart` shuning uchun bor.
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(color: palette.hairline, indent: 12, endIndent: 12),
          for (final (icon, label, onTap) in items)
            // Yoyilgan panelda ikonka + matn, tor panelda faqat ikonka —
            // manzillarning o'zi ham xuddi shu qoidaga bo'ysunadi. Ikkala
            // holatda ham kenglik BOLA bo'yicha aniqlanadi.
            extended
                ? TextButton.icon(
                    onPressed: onTap,
                    icon: Icon(icon, size: 20, color: palette.muted),
                    label: Text(label,
                        style: TextStyle(fontSize: 13, color: palette.muted)),
                  )
                : IconButton(
                    onPressed: onTap,
                    tooltip: label,
                    icon: Icon(icon, size: 20, color: palette.muted),
                  ),
        ],
      ),
    );
  }
}
