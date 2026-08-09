import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/spacing.dart';

/// Ilova web manzili. Bellashuv havolasi shu ildizdan quriladi.
///
/// `--dart-define=WEB_BASE_URL=...` bilan almashtiriladi (lokal sinov uchun
/// `http://localhost:PORT`). Standart qiymat — prod domeni.
const webBaseUrl = String.fromEnvironment('WEB_BASE_URL',
    defaultValue: 'https://topagon.uz');

// TELEGRAM_BOT_USERNAME konstantasi OLIB TASHLANDI (2026-08-08 ko'rigi).
//
// U hech qayerda ishlatilmasdi, lekin mavjudligi taklif oqimida IKKINCHI
// havola bo'lgandek taassurot berardi. Endi butun ilovada bitta manzil
// shakli bor:
//
//     https://topagon.uz/?join=KOD    — bellashuvga qo'shilish
//     https://topagon.uz/?ref=NOM     — do'stni taklif qilish
//
// Telegram tugmasi ham AYNAN shu havolani ulashadi (t.me/share/url), ya'ni
// "Telegram havolasi" va "ilova havolasi" degan ikki xil narsa yo'q.
// Bot manzili faqat yordam bo'limida (`kSupportTelegram`) qoladi — u
// butunlay boshqa maqsad.

/// Bellashuvga qo'shilish havolasi: `https://topagon.uz/?join=ABC123`.
///
/// Nega so'rov parametri, `/j/CODE` emas: Flutter Web SPA'da yo'l asosidagi
/// manzil nginx'da alohida `try_files` qoidasini talab qiladi, so'rov
/// parametri esa hech qanday server sozlamasisiz ishlaydi. Deploy oldidan
/// bitta narsa kam — deadline yaqin.
String challengeJoinLink(String code) => '$webBaseUrl/?join=$code';

/// Telegramda ulashish uchun tayyor matn.
String challengeShareMessage(L10n l, String code) =>
    '${l.challengeInviteText}\n\n${challengeJoinLink(code)}';

/// Brauzer manzilidan `?join=KOD` ni o'qiydi (faqat webda).
///
/// Ilova ishga tushganda bir marta chaqiriladi. Kod topilsa qaytariladi va
/// `HomeShell` uni bellashuv varag'ida ishlatadi.
String? pendingJoinCodeFromUrl() {
  if (!kIsWeb) return null;
  final code = Uri.base.queryParameters['join'];
  if (code == null) return null;
  final clean = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return clean.isEmpty ? null : clean;
}

/// Havoladan kelgan, hali ishlatilmagan bellashuv kodi.
///
/// `main.dart` da bir marta to'ldiriladi, `ChallengesScreen` uni o'qib
/// tozalaydi. Provider'da saqlanadi, chunki foydalanuvchi havolani bosganda
/// hali kirmagan bo'lishi mumkin — kod kirgunicha kutib turadi.
final pendingJoinCodeProvider = StateProvider<String?>((_) => null);

/// Bellashuv yaratilgandan keyin chiqadigan ulashish varag'i.
///
/// TARIX: ilgari bu yerda faqat kod va "Nusxalash" tugmasi bo'lardi. Kodni
/// olgan do'st esa ilovani topib, o'rnatib, bellashuv bo'limiga kirib, kodni
/// qo'lda kiritishi kerak edi — har qadamda odam yo'qoladi. Havola bu
/// zanjirni bitta bosishga qisqartiradi.
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

            // Havola — asosiy element. Kod pastda, zaxira sifatida.
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
                // Telegram'ning rasmiy ulashish oynasi. Ilova o'rnatilgan
                // bo'lsa u ochiladi, aks holda web versiyasi — ikkalasi ham
                // shu bitta manzil bilan ishlaydi.
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

            // Zaxira yo'l: havola ishlamasa (masalan, do'stda ilova bor va
            // u qo'lda kiritmoqchi) — kodning o'zi.
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
