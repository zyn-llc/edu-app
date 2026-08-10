import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../mascot/mascot.dart';
import '../../theme/app_colors.dart';
import '../../theme/spacing.dart';
import '../../widgets/currency.dart';
import '../../widgets/guest_notice.dart';

class ResultScreen extends StatelessWidget {
  final int score;
  final int total;

  final int xpEarned;
  final int coinsEarned;

  const ResultScreen({
    super.key,
    required this.score,
    required this.total,
    this.xpEarned = 0,
    this.coinsEarned = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final palette = Theme.of(context).extension<AppPalette>()!;
    final ratio = total == 0 ? 0.0 : score / total;

    final OwlMood mood;
    final String headline;
    if (ratio >= 0.8) {
      mood = OwlMood.wow;
      headline = l.greatJob;
    } else if (ratio >= 0.5) {
      mood = OwlMood.encouraging;
      headline = l.keepGoing;
    } else {
      mood = OwlMood.thinking;
      headline = l.reviewNeeded;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(l.resultTitle),
      ),
      // kichik telefonlarda (yoki katta shriftda) kontent sig'masdan
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OwlMascot(mood, size: 150),
                const Gap.md(),
                Text(headline,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const Gap.sm(),
                Text(l.scoreLine(score, total),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: palette.muted)),
                if (xpEarned > 0) ...[
                  const Gap.md(),
                  _RewardRow(xp: xpEarned, coins: coinsEarned),
                ],
                const Gap.lg(),
                const GuestNotice(),
                const Gap.lg(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                    child: Text(l.backHome),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  final int xp;
  final int coins;
  const _RewardRow({required this.xp, required this.coins});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      alignment: WrapAlignment.center,
      children: [
        RewardChip.xp(l.rewardXp(xp)),
        if (coins > 0) RewardChip.coin(l.rewardCoins(coins)),
      ],
    );
  }
}
