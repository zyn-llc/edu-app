library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/spacing.dart';
import '../challenges/challenge_invite.dart' show webBaseUrl;

/// `https://topagon.uz/?ref=<username>`.
///
String friendInviteLink(String? username) =>
    (username != null && username.isNotEmpty)
        ? '$webBaseUrl/?ref=$username'
        : webBaseUrl;

///
/// xuddi `pendingJoinCodeFromUrl()` kabi.
String? pendingReferrerFromUrl() {
  if (!kIsWeb) return null;
  final raw = Uri.base.queryParameters['ref']?.trim();
  return (raw == null || raw.isEmpty || raw.length > 20) ? null : raw;
}

///
/// `main.dart` da bir marta to'ldiriladi. `pendingJoinCodeProvider`
final pendingReferrerProvider = StateProvider<String?>((_) => null);

class InviteFriendsSheet extends StatelessWidget {
  const InviteFriendsSheet({super.key, required this.username});

  final String? username;

  static Future<void> show(BuildContext context, String? username) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 520),
        builder: (_) => InviteFriendsSheet(username: username),
      );

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final link = friendInviteLink(username);

    Future<void> snack(String msg) async {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
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
                    color: scheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Icon(Icons.group_add_rounded,
                    size: 30, color: scheme.primary),
              ),
            ),
            const Gap.sm(),
            Text(l.inviteFriendsTitle,
                style: text.headlineSmall, textAlign: TextAlign.center),
            const Gap.sm(),
            Text(l.inviteFriendsHint,
                style: text.bodySmall, textAlign: TextAlign.center),
            const Gap.md(),
            Container(
              padding: const EdgeInsets.all(Spacing.ms),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: Radii.cardRadius,
              ),
              child: SelectableText(
                link,
                style: text.bodyMedium?.copyWith(color: scheme.primary),
                textAlign: TextAlign.center,
              ),
            ),
            const Gap.ms(),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                await snack(l.challengeLinkCopied);
              },
              icon: const Icon(Icons.link_rounded),
              label: Text(l.challengeCopyLink),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
            ),
            const Gap.sm(),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(
                  'https://t.me/share/url'
                  '?url=${Uri.encodeComponent(link)}'
                  '&text=${Uri.encodeComponent(l.inviteFriendsShareText)}',
                );
                final ok = await launchUrl(uri,
                    mode: LaunchMode.externalApplication);
                if (!ok) {
                  await Clipboard.setData(ClipboardData(
                      text: '${l.inviteFriendsShareText}\n\n$link'));
                  await snack(l.challengeLinkCopied);
                }
              },
              icon: const Icon(Icons.send_rounded),
              label: Text(l.challengeShareTelegram),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
            ),
          ],
        ),
      ),
    );
  }
}
