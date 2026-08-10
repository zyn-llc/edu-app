import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/spacing.dart';

const webBaseUrl = String.fromEnvironment('WEB_BASE_URL',
    defaultValue: 'https://topagon.uz');

//
// shakli bor:
//
//

/// Bellashuvga qo'shilish havolasi: `https://topagon.uz/?join=ABC123`.
///
String challengeJoinLink(String code) => '$webBaseUrl/?join=$code';

String challengeShareMessage(L10n l, String code) =>
    '${l.challengeInviteText}\n\n${challengeJoinLink(code)}';

///
/// `HomeShell` uni bellashuv varag'ida ishlatadi.
String? pendingJoinCodeFromUrl() {
  if (!kIsWeb) return null;
  final code = Uri.base.queryParameters['join'];
  if (code == null) return null;
  final clean = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return clean.isEmpty ? null : clean;
}

///
/// `main.dart` da bir marta to'ldiriladi, `ChallengesScreen` uni o'qib
final pendingJoinCodeProvider = StateProvider<String?>((_) => null);

class ChallengeInviteSheet extends StatelessWidget {
  const ChallengeInviteSheet({super.key, required this.code});

  final String code;

  static Future<void> show(BuildContext context, String code) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 520),
        builder: (_) => ChallengeInviteSheet(code: code),
      );

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final link = challengeJoinLink(code);

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
            Text(l.challengeCreatedTitle,
                style: text.headlineSmall, textAlign: TextAlign.center),
            const Gap.sm(),
            Text(l.challengeShareLinkHint,
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
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const Gap.sm(),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(
                  'https://t.me/share/url'
                  '?url=${Uri.encodeComponent(link)}'
                  '&text=${Uri.encodeComponent(l.challengeInviteText)}',
                );
                final ok = await launchUrl(uri,
                    mode: LaunchMode.externalApplication);
                if (!ok) {
                  await Clipboard.setData(
                      ClipboardData(text: challengeShareMessage(l, code)));
                  await snack(l.challengeLinkCopied);
                }
              },
              icon: const Icon(Icons.send_rounded),
              label: Text(l.challengeShareTelegram),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
            ),
            const Gap.md(),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${l.challengeShareCode}:  ',
                    style: text.bodySmall),
                SelectableText(code,
                    style: text.titleMedium?.copyWith(letterSpacing: 3)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: l.copy,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    await snack(l.challengeCodeCopied(code));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
