import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart' show AppPalette;
import '../../theme/motion.dart';
import '../../theme/spacing.dart';
import '../../theme/subject_palette.dart';
import '../../widgets/currency.dart';
import '../../widgets/hover_card.dart';
import '../../widgets/stats.dart';
import '../../widgets/subject_icon.dart';
import 'subjects.dart';

const int kXpPerCorrect = 10;

///
///
///
/// ## 2026-08-07 dizayn yangilanishi
///
/// |----------------------|---------------------------------------------------|
class SubjectCard extends StatelessWidget {
  const SubjectCard({
    super.key,
    required this.subject,
    required this.onTap,
    this.streakDays = 0,
  });

  final Subject subject;
  final VoidCallback onTap;

  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final palette = theme.extension<AppPalette>()!;
    final style = SubjectPalette.of(subject.code);
    final accent = style.color(theme.brightness);

    final empty = subject.questionCount <= 0;

    return HoverCard(
      onTap: empty ? null : onTap,
      // `enabled: false` kartani xiralashtiradi va soyasini oladi —
      // "Geometriya" boshqalardan bir qarashda ajralib turadi.
      enabled: !empty,
      accent: accent,
      padding: const EdgeInsets.all(Spacing.md),
      contentBuilder: (context, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- sarlavha qatori --------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: AnimatedSubjectIcon(
                  code: subject.code,
                  color: accent,
                  size: 26,
                  active: hovered && !empty,
                ),
              ),
              const Gap.ms(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.name,
                        style: text.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const Gap.xs(),
                    if (empty)
                      _Chip(
                        label: l.comingSoonChip,
                        color: accent,
                        background: accent.withValues(alpha: 0.16),
                      )
                    else
                      Text(
                        subject.isStarted
                            ? _lastLine(l)
                            : l.subjectByTopics,
                        style: text.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (subject.isStarted && !empty) ...[
                const Gap.sm(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: subject.accuracy.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 800),
                  curve: Motion.enter,
                  builder: (_, v, __) => ProgressRing(
                    value: v,
                    size: 46,
                    stroke: 4,
                    color: accent,
                    child: Text(
                      '${(v * 100).round()}%',
                      style: text.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const Gap.md(),

          // ---- o'rta blok --------------------------------------------------
          if (empty)
            Text(
              l.subjectComingSoonHint,
              style: text.bodySmall?.copyWith(color: scheme.onSurface),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            )
          else if (subject.isStarted)
            _ProgressBlock(subject: subject, accent: accent)
          else
            Row(
              children: [
                RewardChip.xp(l.subjectXpPerQuestion(kXpPerCorrect)),
              ],
            ),

          const Gap.md(),

          // ---- harakat -----------------------------------------------------
          if (!empty)
            Row(
              children: [
                if (_showStreak) ...[
                  _Chip(
                    label: '$streakDays',
                    icon: Icons.local_fire_department_rounded,
                    color: palette.danger,
                    background: palette.danger.withValues(alpha: 0.12),
                  ),
                  const Gap.sm(),
                ],
                Expanded(
                  child: Text(
                    // "apelsin = bosiladigan narsa" qoidasini o'rgana
                    _cta(l),
                    style: text.labelLarge?.copyWith(color: scheme.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedSlide(
                  offset: Offset(hovered ? 0.28 : 0, 0),
                  duration: Motion.fast,
                  curve: Motion.interactive,
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 18, color: scheme.primary),
                ),
              ],
            ),
        ],
      ),
    );
  }

  bool get _showStreak {
    if (streakDays <= 0 || !subject.isStarted) return false;
    final at = subject.lastPracticedAt;
    if (at == null) return true;
    final now = DateTime.now();
    return DateTime(at.year, at.month, at.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }

  String _lastLine(L10n l) =>
      '${l.lastPractice}: ${relativeDay(l, subject.lastPracticedAt ?? DateTime.now())}';

  ///
  ///
  ///
  ///     xos ko'cha-og'zaki ohang.
  ///
  String _cta(L10n l) => subject.isStarted ? l.continueLabel : l.startNow;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: icon == null ? Spacing.sm : 6, vertical: 2),
      decoration:
          BoxDecoration(color: background, borderRadius: Radii.pillRadius),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
        ],
        Text(label,
            style: text.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.subject, required this.accent});

  final Subject subject;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${subject.correct}/${subject.answered} ${l.subjectSolved}',
                style: text.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            RewardChip.xp(l.subjectXpPerQuestion(kXpPerCorrect)),
          ],
        ),
        const Gap.sm(),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: subject.accuracy.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 800),
          curve: Motion.enter,
          builder: (_, v, __) => ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: palette.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ),
      ],
    );
  }
}

/// Grid katakchasi balandligi.
///
///
///
double subjectCardHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3);
  return 216 * scale.toDouble();
}

String relativeDay(L10n l, DateTime at) {
  final now = DateTime.now();
  final a = DateTime(at.year, at.month, at.day);
  final b = DateTime(now.year, now.month, now.day);
  final days = b.difference(a).inDays;
  if (days <= 0) return l.todayLabel;
  if (days == 1) return l.yesterdayLabel;
  return '$days ${l.daysAgoSuffix}';
}
