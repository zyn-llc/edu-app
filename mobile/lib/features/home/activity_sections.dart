import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_models.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/elevation.dart';
import '../../theme/motion.dart';
import '../../theme/spacing.dart';
import '../../theme/subject_palette.dart';
import '../../widgets/currency.dart';
import '../../widgets/hover_card.dart';
import '../../widgets/subject_icon.dart';
import '../quiz/picker_screen.dart';
import '../subjects/subjects.dart';
import 'home_shell.dart';

///
///
///
///
/// raqamlarga ham ishonmaydi.
///

const int kDailyTarget = 20;

Subject? _resumeTarget(List<Subject> subjects) {
  final playable = [for (final s in subjects) if (s.questionCount > 0) s];
  if (playable.isEmpty) return null;
  Subject best = playable.first;
  DateTime? bestAt;
  for (final s in playable) {
    final at = s.lastPracticedAt;
    if (at != null && (bestAt == null || at.isAfter(bestAt))) {
      bestAt = at;
      best = s;
    }
  }
  return best;
}

class DailyGoalCard extends StatelessWidget {
  const DailyGoalCard({
    super.key,
    required this.subjects,
    required this.progress,
  });

  final List<Subject> subjects;
  final Progress? progress;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    final target = _resumeTarget(subjects);
    if (target == null) return const SizedBox.shrink();

    final done = progress?.answeredToday ?? 0;
    final complete = done >= kDailyTarget;
    final accent = complete ? palette.success : scheme.primary;
    final ratio = (done / kDailyTarget).clamp(0.0, 1.0);

    void start() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PickerScreen(target)),
        );

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: complete
            ? palette.success.withValues(alpha: 0.10)
            : palette.primaryTint,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: accent.withValues(alpha: 0.30)),
        boxShadow: Shadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(complete ? Icons.check_circle_rounded : Icons.flag_rounded,
                  color: accent),
              const Gap.ms(),
              Expanded(
                child: Text(
                  complete ? l.dashGoalDone : l.dashGoalTitle,
                  style: text.titleMedium?.copyWith(color: accent),
                ),
              ),
              if (progress != null)
                Text('$done / $kDailyTarget',
                    style: text.titleMedium?.copyWith(
                        color: accent, fontWeight: FontWeight.w700)),
            ],
          ),
          const Gap.ms(),

          if (progress == null)
            Text(l.dashGoalLead(kDailyTarget), style: text.bodySmall)
          else ...[
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 700),
              curve: Motion.enter,
              builder: (_, v, __) => ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  backgroundColor: scheme.surface,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ),
            const Gap.sm(),
            Text(
              complete
                  ? l.dashGoalTomorrow(kDailyTarget)
                  : l.dashGoalRemaining(kDailyTarget - done),
              style: text.bodySmall,
            ),
          ],

          if (progress != null && progress!.answeredToday > 0) ...[
            const Gap.ms(),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                if (progress!.xpToday > 0)
                  RewardChip.xp(l.rewardXp(progress!.xpToday)),
                _MetaChip(
                  icon: Icons.track_changes_rounded,
                  label: l.dashAccuracyValue(
                      ((progress!.accuracyToday ?? 0) * 100).round()),
                  color: palette.muted,
                ),
                if (progress!.streakDays > 0)
                  _MetaChip(
                    icon: Icons.local_fire_department_rounded,
                    label: l.dashStreakDays(progress!.streakDays),
                    color: palette.danger,
                  ),
              ],
            ),
          ],

          if (!complete) ...[
            const Gap.md(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: start,
                child: Text(done > 0 ? l.continueLabel : l.dashQuickStart),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: Radii.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const Gap.xs(),
          Text(label,
              style: text.labelSmall
                  ?.copyWith(color: c, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    final week = progress.week;
    if (week.isEmpty) return const SizedBox.shrink();

    // faylini shishiradi va tartibni buzish oson.
    final names = l.weekdayShorts.split(',');

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: palette.hairline),
        boxShadow: Shadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.dashWeekTitle, style: text.titleSmall),
          const Gap.ms(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < week.length; i++)
                _DayDot(
                  // `DateTime.weekday`: 1 = dushanba … 7 = yakshanba.
                  label: names.length == 7
                      ? names[week[i].date.weekday - 1]
                      : '',
                  day: week[i],
                  index: i,
                ),
            ],
          ),
          const Gap.ms(),
          Wrap(
            spacing: Spacing.ms,
            runSpacing: Spacing.xs,
            children: [
              Text(l.dashQuestionsCount(progress.answered7d),
                  style: text.bodySmall),
              if (progress.xp7d > 0)
                Text(l.rewardXp(progress.xp7d),
                    style: text.bodySmall
                        ?.copyWith(color: Rewards.xp, fontWeight: FontWeight.w700)),
              Text(l.dashDaysActive(progress.activeDays7d),
                  style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.label, required this.day, required this.index});

  final String label;
  final DayStat day;
  final int index;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    final filled = day.isActive;
    final color = filled ? scheme.primary : palette.surfaceAlt;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: text.labelSmall?.copyWith(
            color: day.isToday ? scheme.primary : palette.muted,
            fontWeight: day.isToday ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        const Gap.xs(),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: day.isToday
                ? Border.all(color: scheme.primary, width: 2)
                : null,
          ),
          child: filled
              ? Icon(Icons.check_rounded,
                  size: 16, color: scheme.onPrimary)
              : null,
        ),
      ],
    ).enterStaggered(index);
  }
}

// --------------------------------------------------------------------------- //
//  3. Davom ettiring                                                          //
// --------------------------------------------------------------------------- //

/// Oxirgi ishlangan fanga qaytish kartasi.
///
///
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.subjects});

  final List<Subject> subjects;

  static Subject? pick(List<Subject> subjects) {
    Subject? best;
    DateTime? bestAt;
    for (final s in subjects) {
      final at = s.lastPracticedAt;
      if (s.questionCount <= 0 || at == null || s.answered <= 0) continue;
      if (bestAt == null || at.isAfter(bestAt)) {
        bestAt = at;
        best = s;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final brightness = Theme.of(context).brightness;

    final s = pick(subjects);
    if (s == null) return const SizedBox.shrink();

    final style = SubjectPalette.of(s.code);
    final color = style.color(brightness);
    final pct = (s.accuracy * 100).round();

    return HoverCard(
      accent: color,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PickerScreen(s)),
      ),
      contentBuilder: (context, hovered) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(Spacing.ms),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: AnimatedSubjectIcon(
                code: s.code, color: color, size: 26, active: hovered),
          ),
          const Gap.md(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.name,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const Gap.xs(),
                Text(
                  '${l.dashQuestionsCount(s.answered)} · '
                  '${l.dashAccuracyValue(pct)}',
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap.sm(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: s.accuracy.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 700),
                    curve: Motion.enter,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: palette.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap.ms(),
          AnimatedSlide(
            offset: hovered ? const Offset(0.25, 0) : Offset.zero,
            duration: Motion.fast,
            curve: Motion.interactive,
            child: Icon(Icons.arrow_forward_rounded, color: color),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  4. Bellashuv taklifi                                                       //
// --------------------------------------------------------------------------- //

class ChallengeCta extends ConsumerWidget {
  const ChallengeCta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: palette.hairline),
        boxShadow: Shadows.card(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(Spacing.ms),
            decoration: BoxDecoration(
              color: Rewards.coinDark.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: const Icon(Icons.emoji_events_rounded,
                color: Rewards.coinDark, size: 26),
          ),
          const Gap.md(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.navChallenges, style: text.titleMedium),
                const Gap.xs(),
                Text(l.dashChallengeBody, style: text.bodySmall),
                const Gap.ms(),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(homeTabProvider.notifier).state = 2,
                  child: Text(l.dashChallengeCta),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
