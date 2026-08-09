import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';

/// Rus tili tanlanganda chiqadigan ogohlantirish.
///
/// ## Muammo
///
/// Interfeys ruschaga tarjima qilingan, lekin SAVOLLAR bazasida ruscha
/// tarjima umuman yo'q — `question_translations` da faqat `uz` yozuvlari bor.
/// Server mos tarjimani topmaganda o'zbekchasini qaytaradi (fallback).
///
/// Natijada rus tilini tanlagan foydalanuvchi ruscha menyu va o'zbekcha
/// savollarni ko'radi. Bu eng yomon variant: u ilova buzuq deb o'ylaydi va
/// nima bo'layotganini tushunmaydi.
///
/// ## Qaror
///
/// Yashirin fallback o'rniga OCHIQ xabar. Foydalanuvchi holatni biladi va
/// bir bosishda o'zbek tiliga qaytishi mumkin. Ruscha kontent tayyor
/// bo'lgach, bu vidjetni chaqirishni olib tashlash kifoya.
class RuContentNotice extends ConsumerWidget {
  const RuContentNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeCodeProvider);
    if (lang != 'ru') return const SizedBox.shrink();

    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: palette.primaryTint,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.translate_rounded, size: 20, color: scheme.primary),
            const Gap.sm(),
            Expanded(
              child: Text(l.ruContentTitle,
                  style: text.titleMedium?.copyWith(color: scheme.primary)),
            ),
          ]),
          const Gap.sm(),
          Text(l.ruContentBody, style: text.bodySmall),
          const Gap.ms(),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () {
                // Faqat `localeCodeProvider` ni o'zgartiramiz — `main.dart`
                // dagi `ref.listen` uni `SharedPreferences` ga yozadi va
                // `MaterialApp` locale'ni almashtiradi.
                ref.read(localeCodeProvider.notifier).state = 'uz-Latn';
              },
              child: Text(l.ruSwitchBack),
            ),
          ),
        ],
      ),
    );
  }
}
