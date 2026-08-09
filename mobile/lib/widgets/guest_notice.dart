import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../features/auth/login_sheet.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';

/// Mehmon uchun ogohlantirish: natija saqlanmayapti.
///
/// NEGA KERAK: `api/v1/content.py` da XP, tanga va streak faqat
/// `if not is_guest:` shoxida beriladi — mehmon uchun ATAYLAB hech narsa
/// yozilmaydi (mehmon umumiy akkaunt, aks holda bitta hisobda hamma
/// foydalanuvchining XP'si aralashib ketardi).
///
/// Lekin ilova buni hech qachon aytmasdi. Foydalanuvchi 10 ta savol yechib,
/// XP ham, tanga ham o'zgarmaganini ko'rib, ilovani buzuq deb o'ylardi.
/// Bu — bug emas, MULOQOT muammosi, va u konversiyaga to'g'ridan-to'g'ri
/// ta'sir qiladi: aynan shu daqiqada ro'yxatdan o'tishga undash kerak.
///
/// Kirgan foydalanuvchida hech narsa ko'rsatilmaydi (`SizedBox.shrink`).
class GuestNotice extends ConsumerWidget {
  const GuestNotice({super.key, this.compact = false});

  /// Quiz ichida ko'rsatilganda — bitta qator, tugmasiz.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth.isAuthenticated || auth.initializing) {
      return const SizedBox.shrink();
    }

    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: palette.primaryTint,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: scheme.primary),
          const Gap.ms(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.guestProgressTitle,
                    style: text.titleMedium?.copyWith(color: scheme.primary)),
                const Gap.xs(),
                Text(l.guestProgressHint, style: text.bodySmall),
                if (!compact) ...[
                  const Gap.ms(),
                  FilledButton(
                    onPressed: () => LoginSheet.show(context,
                        reason: l.guestProgressHint),
                    child: Text(l.guestProgressCta),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
