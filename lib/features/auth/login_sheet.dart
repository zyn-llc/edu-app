import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/spacing.dart';
import 'invite_screen.dart';
import 'password_screen.dart';
import 'phone_screen.dart';
import 'telegram_screen.dart';

class LoginSheet extends ConsumerWidget {
  const LoginSheet({super.key, this.reason});

  final String? reason;

  static Future<bool> show(BuildContext context, {String? reason}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => LoginSheet(reason: reason),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final methods = ref.watch(authMethodsProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: palette.primaryTint, shape: BoxShape.circle),
                child: Icon(Icons.login_rounded,
                    size: 30, color: scheme.primary),
              ),
            ),
            const Gap.md(),
            Text(l.authLoginTitle,
                style: text.headlineSmall, textAlign: TextAlign.center),
            const Gap.sm(),
            Text(reason ?? l.authLoginBenefit,
                style: text.bodySmall, textAlign: TextAlign.center),
            const Gap.lg(),
            methods.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => _options(context, const AuthMethods()),
              data: (m) => _options(context, m),
            ),
            const Gap.sm(),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.guestLater),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Widget screen) async {
    final navigator = Navigator.of(context);
    final ok = await navigator.push<bool>(
        MaterialPageRoute(builder: (_) => screen));
    if (ok == true && navigator.canPop()) navigator.pop(true);
  }

  Widget _options(BuildContext context, AuthMethods m) =>
      _Options(methods: m, open: _open);
}

class _Options extends StatefulWidget {
  const _Options({required this.methods, required this.open});

  final AuthMethods methods;
  final Future<void> Function(BuildContext, Widget) open;

  @override
  State<_Options> createState() => _OptionsState();
}

class _OptionsState extends State<_Options> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final m = widget.methods;

    if (!m.any) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: Text(l.authNoMethods, textAlign: TextAlign.center),
      );
    }

    //                holda qo'yadi.
    final tiles = <Widget>[
      if (m.telegram)
        _Tile(
          icon: Icons.send_rounded,
          title: l.authTelegramButton,
          subtitle: l.authTelegramSubtitle,
          primary: true,
          onTap: () => widget.open(context, const TelegramLoginScreen()),
        ),
      if (m.password)
        _Tile(
          icon: Icons.lock_outline_rounded,
          title: l.pwButton,
          subtitle: m.passwordRegisterRequiresInvite
              ? l.pwButtonSubtitleExisting
              : l.pwButtonSubtitle,
          primary: !m.telegram,
          onTap: () => widget.open(context, const PasswordScreen()),
        ),
      if (m.invite)
        _Tile(
          icon: Icons.confirmation_number_outlined,
          title: l.authInviteButton,
          subtitle: l.authInviteSubtitle,
          primary: !m.password && !m.telegram,
          onTap: () => widget.open(context, const InviteScreen()),
        ),
      if (m.phone)
        _Tile(
          icon: Icons.phone_iphone_rounded,
          title: l.authPhoneButton,
          subtitle: l.authPhoneSubtitle,
          primary: !m.password && !m.telegram && !m.invite,
          onTap: () => widget.open(context, const PhoneScreen()),
        ),
    ];

    final visibleCount = tiles.length >= 2 ? 2 : tiles.length;
    final visible = tiles.sublist(0, visibleCount);
    final rest = tiles.sublist(visibleCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const Gap.sm(),
          visible[i],
        ],
        if (rest.isNotEmpty && !_expanded) ...[
          const Gap.sm(),
          TextButton(
            onPressed: () => setState(() => _expanded = true),
            child: Text(l.authOtherMethods),
          ),
        ],
        if (_expanded)
          for (final t in rest) ...[const Gap.sm(), t],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final fg = primary ? scheme.onPrimary : scheme.onSurface;

    return Material(
      color: primary ? scheme.primary : palette.surfaceAlt,
      borderRadius: Radii.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.ms),
          child: Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: Spacing.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: fg.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: fg.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
