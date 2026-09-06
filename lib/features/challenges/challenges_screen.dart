import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/motion.dart';
import '../../theme/elevation.dart';
import '../../theme/spacing.dart';
import '../../widgets/app_footer.dart';
import '../../widgets/currency.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/hover_card.dart';
import '../auth/login_sheet.dart';
import '../subjects/subjects.dart';
import 'challenge_invite.dart';
import 'challenge_play_screen.dart';
import 'challenges_data.dart';

class ChallengesScreen extends ConsumerStatefulWidget {
  const ChallengesScreen({super.key});

  @override
  ConsumerState<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends ConsumerState<ChallengesScreen> {
  bool _joinHandled = false;

  /// yozmaydi: havolani bosdi — bellashuvda.
  void _consumePendingJoin() {
    if (_joinHandled) return;
    final code = ref.read(pendingJoinCodeProvider);
    if (code == null) return;
    if (!ref.read(authControllerProvider).isAuthenticated) return;
    _joinHandled = true;
    ref.read(pendingJoinCodeProvider.notifier).state = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openJoinDialog(context, ref, initialCode: code);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final auth = ref.watch(authControllerProvider);

    if (!auth.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: Text(l.navChallenges)),
        body: EmptyState(
          icon: Icons.emoji_events_outlined,
          title: l.navChallenges,
          message: l.challengeLoginNeeded,
          actionLabel: l.authLoginTitle,
          onAction: () =>
              LoginSheet.show(context, reason: l.challengeLoginNeeded),
        ),
      );
    }

    _consumePendingJoin();

    final challenges = ref.watch(myChallengesProvider);
    final coins = ref.watch(coinInfoProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.navChallenges)),
      floatingActionButton: GlowFab(
        onPressed: () => _openCreateSheet(context),
        icon: const Icon(Icons.add),
        label: Text(l.challengeNew),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myChallengesProvider);
          ref.invalidate(coinInfoProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.sm, Spacing.md, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
          coins.when(
              data: (c) => _CoinBar(info: c),
              loading: () => const Skeleton(height: 72, radius: Radii.lg),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const Gap.ms(),
            OutlinedButton.icon(
              onPressed: () => _openJoinDialog(context, ref),
              icon: const Icon(Icons.qr_code_rounded),
              label: Text(l.challengeJoinByCode),
            ),
            const Gap.md(),
            challenges.when(
              loading: () => const Column(
                children: [
                  Skeleton(height: 84, radius: Radii.lg),
                  Gap.ms(),
                  Skeleton(height: 84, radius: Radii.lg),
                ],
              ),
              // `EmptyState` ichida `SingleChildScrollView` bor; `ListView`
              error: (e, _) => SizedBox(
                height: 300,
                child: EmptyState(
                  compact: true,
                  icon: Icons.wifi_off_rounded,
                  title: l.errNoConnection,
                  message: '$e',
                  actionLabel: l.retry,
                  onAction: () => ref.invalidate(myChallengesProvider),
                ),
              ),
              data: (items) => items.isEmpty
                  ? SizedBox(
                      height: 340,
                      child: EmptyState(
                        compact: true,
                        icon: Icons.emoji_events_outlined,
                        title: l.challengeNew,
                        message: l.challengeEmptyFull,
                        actionLabel: l.challengeNew,
                        onAction: () => _openCreateSheet(context),
                        secondaryLabel: l.challengeJoinByCode,
                        onSecondary: () => _openJoinDialog(context, ref),
                      ),
                    )
                  : Column(children: [
                      for (final (i, ch) in items.indexed) ...[
                        _ChallengeCard(ch: ch).enterStaggered(i),
                        const Gap.ms(),
                      ],
                    ]),
            ),
                  const SizedBox(height: 96),
                ]),
              ),
            ),
            const FooterSliver(),
          ],
        ),
      ),
    );
  }

  void _openCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const _CreateChallengeSheet(),
    );
  }

  void _openJoinDialog(BuildContext context, WidgetRef ref,
      {String? initialCode}) {
    final l = L10n.of(context);
    final ctrl = TextEditingController(text: initialCode ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.challengeJoinByCode),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: InputDecoration(hintText: l.challengeCodeHint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(
            onPressed: () async {
              final code = ctrl.text.trim().toUpperCase();
              if (code.length < 4) return;
              Navigator.pop(ctx);
              try {
                await ref.read(challengeRepositoryProvider).join(code);
                ref.invalidate(myChallengesProvider);
                ref.invalidate(coinInfoProvider);
              } catch (e) {
                if (context.mounted) _showApiError(context, e);
              }
            },
            child: Text(l.challengeJoin),
          ),
        ],
      ),
    );
  }
}

class _CoinBar extends ConsumerWidget {
  const _CoinBar({required this.info});

  final CoinInfo info;

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
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Rewards.coinDark.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: const NonCoinIcon(size: 24),
          ),
          const Gap.ms(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${info.balance}', style: text.headlineSmall),
                Text(l.coinBalance, style: text.bodySmall),
              ],
            ),
          ),
          if (info.adsLeftToday > 0)
            FilledButton.tonalIcon(
              onPressed: () async {
                try {
                  await ref.read(challengeRepositoryProvider).watchAd();
                  ref.invalidate(coinInfoProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(l.coinAdRewarded('${info.perAd}'))));
                  }
                } catch (e) {
                  if (context.mounted) _showApiError(context, e);
                }
              },
              icon: const Icon(Icons.play_circle_outline),
              label: Text('+${info.perAd}'),
            ),
        ],
      ),
    );
  }
}

class _ChallengeCard extends ConsumerWidget {
  const _ChallengeCard({required this.ch});

  final Challenge ch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    final String statusText;
    final Color statusColor;
    if (ch.status == 'open') {
      statusText = l.challengeWaitingOpponent;
      statusColor = palette.warning;
    } else if (ch.needsMyPlay) {
      statusText = l.challengeYourTurn;
      statusColor = scheme.primary;
    } else if (ch.waitingForThem) {
      statusText = l.challengeWaitingThem;
      statusColor = palette.muted;
    } else if (ch.status == 'done') {
      statusText = ch.isDraw
          ? l.challengeDraw
          : (ch.iWon == true ? l.challengeWon : l.challengeLost);
      statusColor = ch.iWon == true
          ? palette.success
          : (ch.isDraw ? palette.muted : palette.danger);
    } else {
      statusText = ch.status; // cancelled / expired
      statusColor = palette.faint;
    }

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: palette.hairline),
        boxShadow: Shadows.card(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.emoji_events_rounded, color: statusColor),
          ),
          const Gap.ms(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // nimaligini aytmaydi — XP mi, ball mi, noncoin mi?
                  '${l.challengeRewardLabel}: ${ch.stake * 2} ${l.statCoins}',
                  style: text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap.xs(),
                Text(
                  l.dashQuestionsCount(ch.questionCount),
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap.xs(),
                Text(
                  ch.status == 'done'
                      ? '$statusText  (${ch.myScore ?? 0} : ${ch.theirScore ?? 0})'
                      : statusText,
                  style: text.labelMedium?.copyWith(color: statusColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Gap.sm(),
          ..._trailing(context, ref, l),
        ],
      ),
    );
  }

  List<Widget> _trailing(BuildContext context, WidgetRef ref, L10n l) {
    if (ch.status == 'open') {
      return [
        OutlinedButton.icon(
          onPressed: () => ChallengeInviteSheet.show(context, ch.code),
          icon: const Icon(Icons.link_rounded, size: 18),
          label: Text(l.challengeGetLink),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const Gap.sm(),
        IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: l.cancel,
          onPressed: () async {
            try {
              await ref.read(challengeRepositoryProvider).cancel(ch.id);
              ref.invalidate(myChallengesProvider);
              ref.invalidate(coinInfoProvider);
            } catch (e) {
              if (context.mounted) _showApiError(context, e);
            }
          },
        ),
      ];
    }
    if (ch.needsMyPlay) {
      return [
        FilledButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(
                  builder: (_) => ChallengePlayScreen(challenge: ch)))
              .then((_) {
            ref.invalidate(myChallengesProvider);
            ref.invalidate(coinInfoProvider);
          }),
          child: Text(l.challengePlay),
        ),
      ];
    }
    return const [];
  }
}

// --------------------------------------------------------------------------
///
///   * bo'shliqlar `Spacing` shkalasidan,
class _CreateChallengeSheet extends ConsumerStatefulWidget {
  const _CreateChallengeSheet();

  @override
  ConsumerState<_CreateChallengeSheet> createState() =>
      _CreateChallengeSheetState();
}

class _CreateChallengeSheetState extends ConsumerState<_CreateChallengeSheet> {
  String? _subjectId;
  int _count = 5;
  int _stake = 20;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final subjects = ref.watch(subjectsProvider);
    final coins = ref.watch(coinInfoProvider).valueOrNull;

    final balance = coins?.balance;
    final notEnough = balance != null && _stake > balance;
    final canSubmit = !_busy && _subjectId != null && !notEnough;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.challengeNew, style: text.headlineSmall),
            const Gap.lg(),

            subjects.when(
              data: (items) => DropdownButtonFormField<String>(
                initialValue: _subjectId,
                decoration: InputDecoration(labelText: l.challengeSubject),
                items: [
                  for (final s in items)
                    if (s.questionCount > 0)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _subjectId = v),
              ),
              loading: () => const Skeleton(height: 56, radius: Radii.md),
              error: (e, _) => Text('$e', style: text.bodySmall),
            ),
            const Gap.lg(),

            _SliderRow(
              label: l.challengeQuestionCount,
              value: '$_count',
              slider: Slider(
                value: _count.toDouble(),
                min: 3,
                max: 15,
                divisions: 12,
                label: '$_count',
                onChanged: (v) => setState(() => _count = v.round()),
              ),
            ),
            const Gap.md(),

            // ---- mukofot ------------------------------------------------
            _SliderRow(
              label: l.challengeRewardLabel,
              value: '${_stake * 2}',
              hint: l.challengeRewardHint,
              slider: Slider(
                value: _stake.toDouble(),
                min: 0,
                max: 200,
                divisions: 20,
                label: '${_stake * 2}',
                onChanged: (v) => setState(() => _stake = v.round()),
              ),
            ),
            if (balance != null)
              Text(
                '${l.coinBalance}: $balance',
                style: text.labelMedium?.copyWith(
                    color: notEnough ? palette.danger : palette.muted),
              ),
            const Gap.lg(),

            FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.challengeCreate),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    //
    // ishlatilayotgan kontekstni umuman kafolatlamaydi
    // (`use_build_context_synchronously` aynan shuni aytadi).
    //
    // uning kontekstidan foydalanish xavfsiz.
    final sheetNavigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    setState(() => _busy = true);
    try {
      final ch = await ref.read(challengeRepositoryProvider).create(
            subjectId: _subjectId!,
            questionCount: _count,
            stake: _stake,
          );
      ref.invalidate(myChallengesProvider);
      ref.invalidate(coinInfoProvider);
      if (!mounted) return;
      sheetNavigator.pop();
      await ChallengeInviteSheet.show(rootNavigator.context, ch.code);
    } catch (e) {
      if (mounted) _showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Yorliq + qiymat bir qatorda, slayder pastda.
///
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.slider,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: text.titleMedium)),
            Text(value,
                style: text.titleMedium?.copyWith(color: scheme.primary)),
          ],
        ),
        if (hint != null) ...[
          const Gap.xs(),
          Text(hint!, style: text.bodySmall),
        ],
        slider,
      ],
    );
  }
}

void _showApiError(BuildContext context, Object e) {
  String msg = '$e';
  try {
    final data = (e as dynamic).response?.data;
    if (data is Map && data['title'] != null) msg = data['title'] as String;
  } catch (_) {}
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
