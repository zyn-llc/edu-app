import 'package:flutter/material.dart';

import '../../auth/auth_models.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

/// Renders weakest/strongest topics from an [Analysis] as labelled accuracy bars.
/// Shared by the student dashboard and the parent child view so both read the
/// same Tier-1 analysis.
class TopicMasteryView extends StatelessWidget {
  final Analysis analysis;
  const TopicMasteryView({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = Theme.of(context).extension<AppPalette>()!;
    final weak = analysis.weakest;
    final strong = analysis.strongest;

    if (weak.isEmpty && strong.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(l.analysisEmpty,
            style: TextStyle(fontSize: 13, color: p.muted)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (weak.isNotEmpty) ...[
          Text(l.analysisWeak,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: p.muted)),
          const SizedBox(height: 8),
          for (final t in weak) _Bar(stat: t),
          const SizedBox(height: 14),
        ],
        if (strong.isNotEmpty) ...[
          Text(l.analysisStrong,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: p.muted)),
          const SizedBox(height: 8),
          for (final t in strong) _Bar(stat: t),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final TopicStat stat;
  const _Bar({required this.stat});

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AppPalette>()!;
    final pct = (stat.accuracy * 100).round();
    // red→amber→green by accuracy, kept inside the app's warm palette.
    final color = stat.accuracy >= 0.75
        ? const Color(0xFF2E9E5B)
        : stat.accuracy >= 0.5
            ? const Color(0xFFE8A53D)
            : const Color(0xFFD9534F);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(stat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w500)),
              ),
              Text('$pct%',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stat.accuracy.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: p.hairline,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
