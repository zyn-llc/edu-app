/// "Do'stlaringizni taklif qiling" — ilovaning O'ZIGA umumiy taklif havolasi.
///
/// Bellashuv havolasi (`challenge_invite.dart`, `?join=KOD`) bilan
/// ARALASHTIRMASLIK KERAK: u ikki kishilik 1v1 o'yinga taklif, bu esa
/// umuman ilovaga — hech qanday o'yin bilan bog'liq emas.
///
/// MUKOFOTSIZ, ATAYLAB (2026-08-07 qarori). Sabab: parol bilan
/// ro'yxatdan o'tishga taklif kodini majburiy qilganimizning aynan o'sha
/// sababi bu yerda ham bor — "taklif qil, mukofot ol" darhol soxta hisob
/// ochish stimulini yaratadi (bitta odam o'zi-o'ziga taklif havolasi
/// bilan cheksiz "do'st" qo'shishi mumkin). Mukofot puxta o'ylab
/// chiqilgandan keyin (masalan, faqat ikkinchi tomon birinchi mashqni
/// tugatgandan KEYIN, va IP/qurilma bo'yicha cheklov bilan) qo'shiladi.
/// Hozircha faqat KUZATUV: backend `users.referred_by` ga yozadi,
/// `/v1/admin/stats` da ko'rinadi.
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
/// `username` bo'lmasa (Telegram bilan kirgan, hali parol/nom qo'ymagan
/// foydalanuvchi) — oddiy asosiy havola qaytadi, RAQAMSIZ atributsiya bilan.
/// Ichki foydalanuvchi ID sini URL'ga chiqarmaymiz — u tashqariga chiqishi
/// shart bo'lmagan ma'lumot.
String friendInviteLink(String? username) =>
    (username != null && username.isNotEmpty)
        ? '$webBaseUrl/?ref=$username'
        : webBaseUrl;

/// Brauzer manzilidan `?ref=USERNAME` ni o'qiydi (faqat webda).
///
/// `main.dart` da ilova ko'tarilishidan oldin bir marta chaqiriladi —
/// xuddi `pendingJoinCodeFromUrl()` kabi.
String? pendingReferrerFromUrl() {
  if (!kIsWeb) return null;
  final raw = Uri.base.queryParameters['ref']?.trim();
  return (raw == null || raw.isEmpty || raw.length > 20) ? null : raw;
}

/// Havoladan kelgan, hali ishlatilmagan taklif qiluvchi nomi.
///
/// `main.dart` da bir marta to'ldiriladi. `pendingJoinCodeProvider`
/// (`challenge_invite.dart`) bilan bir xil naqsh, lekin ALOHIDA
/// provider — ikkalasi bir vaqtda kelishi mumkin emas (`?join=` va
/// `?ref=` turli sahifalarga tegishli), lekin kontseptual jihatdan
/// mustaqil: biri o'yin, biri butun ilova haqida.
final pendingReferrerProvider = StateProvider<String?>((_) => null);

/// Ulashish varag'i. `ChallengeInviteSheet` bilan bir xil naqsh —
/// foydalanuvchi ikkalasini ham tanish deb his qilsin.
class InviteFriendsSheet extends StatelessWidget {
  const InviteFriendsSheet({super.key, required this.username});

  /// `null` bo'lishi mumkin — pastda tushuntirilgan.
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
