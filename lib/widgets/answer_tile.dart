import 'package:flutter/material.dart';

import '../mascot/mascot.dart';
import '../theme/app_colors.dart' show AppPalette;
import '../theme/spacing.dart';

/// Javob varianti va javobdan keyingi xabar.
///
/// RANG QOIDASI — TO'LDIRILGAN YORQIN FON ISHLATILMAYDI.
/// Ilgari to'g'ri variant to'liq to'q sariq bo'lib bo'yalardi: ustidagi
/// matn kontrastini yo'qotardi, qator "yonib ketgandek" ko'rinardi va
/// butun varaq bitta katta rangli dog'ga aylanardi.
///
/// Har bir holat endi uch qismdan iborat:
///     YENGIL FON  +  RANGLI CHEGARA  +  QORA MATN
///
/// Matn hech qachon kulrang emas — javob varianti o'quvchi o'qishi kerak
/// bo'lgan asosiy matn, kulrang esa "o'chirilgan" degan ma'no beradi.
enum AnswerState {
  /// Hali tanlanmagan.
  idle,

  /// Tanlangan, lekin hali tekshirilmagan.
  picked,

  /// Tekshirildi — bu to'g'ri javob.
  correct,

  /// Tekshirildi — o'quvchi shuni tanlagan va u xato.
  wrong,
}

class AnswerTile extends StatelessWidget {
  const AnswerTile({
    super.key,
    required this.letter,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String letter;
  final String text;
  final AnswerState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final palette = theme.extension<AppPalette>()!;

    final (border, fill, mark, accent) = switch (state) {
      AnswerState.idle => (palette.hairline, cs.surface, null, palette.muted),
      AnswerState.picked =>
        (cs.primary, palette.primaryTint, null, cs.primary),
      AnswerState.correct => (
          palette.success,
          palette.success.withValues(alpha: 0.10),
          Icons.check_circle,
          palette.success,
        ),
      AnswerState.wrong => (
          palette.danger,
          palette.danger.withValues(alpha: 0.10),
          Icons.cancel,
          palette.danger,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            // 56 px — barmoq uchun ishonchli va matn ikki qatorga sig'adi.
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.ms, vertical: Spacing.sm),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: border, width: state == AnswerState.idle ? 1 : 2),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    letter,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: accent, fontWeight: FontWeight.w700),
                  ),
                ),
                const Gap.ms(),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: cs.onSurface, height: 1.3),
                  ),
                ),
                if (mark != null) ...[
                  const Gap.sm(),
                  Icon(mark, color: accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Javobdan keyingi xabar — yengil fon, qora matn, boyqush.
class FeedbackBanner extends StatelessWidget {
  const FeedbackBanner({
    super.key,
    required this.correct,
    required this.title,
    this.body,
    this.evidenceLabel,
    this.evidence,
    this.xp,
  });

  final bool correct;
  final String title;
  final String? body;

  /// "Matndan dalil" — o'qish bo'limida javobni isbotlaydigan gap.
  final String? evidenceLabel;
  final String? evidence;

  final int? xp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    final accent = correct ? palette.success : palette.danger;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OwlMascot(correct ? OwlMood.excited : OwlMood.encouraging, size: 52),
          const Gap.ms(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: accent)),
                    ),
                    if (xp != null && xp! > 0) ...[
                      const Gap.sm(),
                      _XpChip(xp: xp!),
                    ],
                  ],
                ),
                if ((body ?? '').isNotEmpty) ...[
                  const Gap.xs(),
                  Text(body!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurface)),
                ],
                if ((evidence ?? '').isNotEmpty) ...[
                  const Gap.sm(),
                  Container(
                    padding: const EdgeInsets.only(left: Spacing.ms),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                            color: theme.colorScheme.primary, width: 3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((evidenceLabel ?? '').isNotEmpty)
                          Text(evidenceLabel!,
                              style: theme.textTheme.labelSmall),
                        Text(
                          evidence!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.onSurface,
                              height: 1.5),
                        ),
                      ],
                    ),
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

class _XpChip extends StatelessWidget {
  const _XpChip({required this.xp});

  final int xp;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('+$xp XP',
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
    );
  }
}
