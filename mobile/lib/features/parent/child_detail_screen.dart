import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../analysis/topic_mastery_view.dart';
import 'parent_data.dart';

/// Read-only deep view of one linked child: progress stats + topic mastery.
/// Aggregates only — no individual wrong-answer detail (privacy posture).
class ChildDetailScreen extends ConsumerWidget {
  final ChildSummary child;
  const ChildDetailScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final name = child.displayName?.isNotEmpty == true
        ? child.displayName!
        : l.lbAnonymous;
    final analysisAsync = ref.watch(childAnalysisProvider(child.studentId));
    final acc = (child.progress.accuracy * 100).round();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _S(label: l.statLevel, value: '${child.progress.level}'),
                _S(label: l.statXp, value: '${child.progress.xp}'),
                _S(label: l.statStreak, value: '${child.progress.streakDays}'),
                _S(label: l.statAccuracy, value: '$acc%'),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(l.analysisTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          analysisAsync.when(
            loading: () => const Center(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator())),
            error: (_, __) => Row(
              children: [
                Expanded(child: Text(l.authNetworkError)),
                TextButton(
                  onPressed: () => ref
                      .invalidate(childAnalysisProvider(child.studentId)),
                  child: Text(l.retry),
                ),
              ],
            ),
            data: (a) => TopicMasteryView(analysis: a),
          ),
        ],
      ),
    );
  }
}

class _S extends StatelessWidget {
  final String label;
  final String value;
  const _S({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: scheme.primary)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: p.muted)),
      ],
    );
  }
}
