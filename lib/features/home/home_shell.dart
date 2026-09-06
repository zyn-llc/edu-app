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

final homeTabProvider = StateProvider<int>((_) => 0);

/// Ilovaning ildiz qobig'i.
///
/// saqlanib qoladi.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

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

  ///
  /// Ikkita yomon oqibati bor:
  ///
  ///
  final Set<int> _visited = {};

  @override
  void initState() {
    super.initState();
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
          // Yon panel FONI.
          //
          // yozuv bo'shliqda osilib turardi. Juda yumshoq apelsin tint
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
                      backgroundColor: Colors.transparent,
                      // Setting both extended and labelType throws.
                      labelType:
                          extended ? null : NavigationRailLabelType.selected,
                      leading: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: _RailBrand(),
                      ),
                      //
                      //   BoxConstraints.debugAssertIsValid → RenderFlex
                      //   → RenderIntrinsicHeight.performLayout
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
          // Cap the content width; full-monitor line lengths read badly.
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final maxW = size.contentMaxWidth;
                final bounded = c.maxWidth > maxW;
                return ContentWidth(
                  maxWidth: maxW,
                  child: bounded
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.symmetric(
                              vertical:
                                  BorderSide(color: palette.hairline, width: 1),
                            ),
                          ),
                          child: body,
                        )
                      : body,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _select(int i) {
    _visited.add(i);
    ref.read(homeTabProvider.notifier).state = i;
  }
}

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

    // `NavigationRail` ning `trailing` i sifatida `IntrinsicHeight` ichiga
    // tushadi. Intrinsic o'lchov cheksiz kenglikni ham, flex bolani ham
    //     BoxConstraints forces an infinite width
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(color: palette.hairline, indent: 12, endIndent: 12),
          for (final (icon, label, onTap) in items)
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
