import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/spacing.dart';
import '../../widgets/avatar.dart';
import '../../widgets/empty_state.dart';
import '../analysis/topic_mastery_view.dart';
import '../home/activity_sections.dart';
import 'parent_data.dart';

///
///
///
///
///   1. **Bolam umuman shug'ullanyaptimi?**  → haftalik ritm (7 nuqta),
///
///
class ChildDetailScreen extends ConsumerWidget {
  final ChildSummary child;
  const ChildDetailScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final palette = Theme.of(context).extension<AppPalette>()!;
    final name = child.displayName?.isNotEmpty == true
        ? child.displayName!
        : l.lbAnonymous;
    final analysisAsync = ref.watch(childAnalysisProvider(child.studentId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Row(
          children: [
            // ishlaydi.
            UserAvatar(name: name, colorIndex: child.avatarColor, size: 32),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(childAnalysisProvider(child.studentId)),
        child: ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            // ---- 1. Shug'ullanyaptimi -------------------------------------
            _SectionTitle(l.parentRhythmTitle),
            const Gap.sm(),
            WeekStrip(progress: child.progress),
            const Gap.sm(),
            _SignalRow(child: child),

            const Gap.xl(),

            // ---- 2. Qayerda qiynalyapti -----------------------------------
            _SectionTitle(l.parentStrugglesTitle),
            const Gap.sm(),
            analysisAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => SizedBox(
                height: 220,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: l.errTitle,
                  message: l.errNoConnection,
                  actionLabel: l.retry,
                  onAction: () =>
                      ref.invalidate(childAnalysisProvider(child.studentId)),
                ),
              ),
              data: (a) {
                if (a.weakest.isEmpty && a.strongest.isEmpty) {
                  return SizedBox(
                    height: 240,
                    child: EmptyState(
                      icon: Icons.insights_rounded,
                      title: l.parentAnalysisEmptyTitle,
                      message: l.parentAnalysisEmptyBody,
                    ),
                  );
                }
                return TopicMasteryView(analysis: a);
              },
            ),

            const Gap.xl(),
            Text(l.parentPrivacyNote,
                style: TextStyle(fontSize: 12, height: 1.45, color: palette.faint)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.child});
  final ChildSummary child;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final palette = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;

    final items = <(String, String)>[
      ('${child.answered7d}', l.parentAnsweredWeek),
      ('${child.activeDays7d}/7', l.parentActiveDays),
      ('${(child.accuracy7d * 100).round()}%', l.parentAccuracyWeek),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (value, label) in items)
            Column(
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(fontSize: 11.5, color: palette.muted)),
              ],
            ),
        ],
      ),
    );
  }
}
