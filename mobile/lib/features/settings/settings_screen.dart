import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/elevation.dart';
import '../../theme/spacing.dart';
import '../../theme/app_colors.dart';
import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';
import '../../core/app_settings.dart';
import '../../widgets/avatar.dart';
import '../auth/login_sheet.dart';
import '../profile/profile_screen.dart';
import '../referral/invite_friends.dart';
import 'support_section.dart';
import '../../core/breakpoints.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final p = Theme.of(context).extension<AppPalette>()!;
    final themeMode = ref.watch(themeModeProvider);
    final lang = ref.watch(localeCodeProvider);
    final soundOn = ref.watch(soundEnabledProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(l.settings),
      ),
      body: ContentWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _section(l.accountSection, p),
            _AccountCard(),
            if (auth.isAuthenticated) ...[
              const SizedBox(height: 10),
              _InviteFriendsCard(),
            ],
            const SizedBox(height: 22),
            _section(l.themeLabel, p),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(l.themeSystem)),
                ButtonSegment(value: ThemeMode.light, label: Text(l.themeLight)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l.themeDark)),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).state = s.first,
            ),
            const SizedBox(height: 22),
            _section(l.languageLabel, p),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'uz-Latn', label: Text('O\'zbek')),
                ButtonSegment(value: 'ru', label: Text('Русский')),
              ],
              selected: {lang == 'ru' ? 'ru' : 'uz-Latn'},
              onSelectionChanged: (s) =>
                  ref.read(localeCodeProvider.notifier).state = s.first,
            ),
            if (lang == 'ru') ...[
              const SizedBox(height: 10),
              Text(L10n.of(context).ruContentBody,
                  style: TextStyle(fontSize: 13, height: 1.4, color: p.muted)),
            ],
            const SizedBox(height: 22),
            // alohida sarlavha ortiqcha.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.soundLabel),
              value: soundOn,
              onChanged: (v) =>
                  ref.read(soundEnabledProvider.notifier).state = v,
            ),
            if (auth.isAuthenticated) const _TelegramNotifySwitch(),
            const SizedBox(height: 22),
            _section(l.supportSection, p),
            const SupportSection(),
          ],
        ),
      ),
    );
  }

  Widget _section(String text, AppPalette p) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
      );
}

/// Telegram xabarlari kaliti.
///
/// huquqning narxi: to'xtata olmaydigan odam botni bloklaydi, o'shanda esa
///
class _TelegramNotifySwitch extends ConsumerStatefulWidget {
  const _TelegramNotifySwitch();

  @override
  ConsumerState<_TelegramNotifySwitch> createState() =>
      _TelegramNotifySwitchState();
}

class _TelegramNotifySwitchState extends ConsumerState<_TelegramNotifySwitch> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = Theme.of(context).extension<AppPalette>()!;
    final user = ref.watch(authControllerProvider).user;
    final on = user?.tgNotifications ?? true;

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(l.notifyTelegramLabel),
      subtitle: Text(l.notifyTelegramHint,
          style: TextStyle(fontSize: 12.5, height: 1.35, color: p.muted)),
      value: on,
      onChanged: _saving
          ? null
          : (v) async {
              setState(() => _saving = true);
              try {
                await ref
                    .read(authControllerProvider.notifier)
                    .updateTelegramNotifications(v);
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
    );
  }
}

class _InviteFriendsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final p = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;
    final username = ref.watch(authControllerProvider).user?.username;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: p.hairline),
        boxShadow: Shadows.card(context),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: scheme.primary.withValues(alpha: 0.14),
            child: Icon(Icons.group_add_rounded, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.inviteFriendsButton,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                Text(l.inviteFriendsSubtitle,
                    style: TextStyle(fontSize: 12, color: p.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: l.inviteFriendsButton,
            icon: Icon(Icons.ios_share_rounded, color: scheme.primary),
            onPressed: () => InviteFriendsSheet.show(context, username),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final p = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authControllerProvider);

    final container = BoxDecoration(
      color: scheme.surface,
      borderRadius: Radii.cardRadius,
      border: Border.all(color: p.hairline),
      boxShadow: Shadows.card(context),
    );

    if (!auth.isAuthenticated) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: container,
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
              child: Icon(Icons.person_outline, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(l.accountGuest,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            FilledButton(
              onPressed: () => LoginSheet.show(context),
              child: Text(l.authLoginTitle),
            ),
          ],
        ),
      );
    }

    final user = auth.user!;
    final name =
        user.displayName?.isNotEmpty == true ? user.displayName! : l.you;
    final roleLabel = user.isParent ? l.roleParent : l.roleStudent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: container,
      child: Row(
        children: [
          UserAvatar(
              name: user.displayName, colorIndex: user.avatarColor, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                // qolardi.
                Text(
                    user.phone == null || user.phone!.isEmpty
                        ? roleLabel
                        : '$roleLabel · ${user.phone}',
                    style: TextStyle(fontSize: 12, color: p.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: l.profileTitle,
            icon: Icon(Icons.edit_outlined, color: scheme.primary),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
          TextButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).logout(),
            child: Text(l.logout),
          ),
        ],
      ),
    );
  }
}
