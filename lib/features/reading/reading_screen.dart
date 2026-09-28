import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/api_error.dart';
import '../../core/pronounce.dart';
import '../../core/sound.dart';
import '../../l10n/app_localizations.dart';
import '../../mascot/mascot.dart';
import '../../theme/spacing.dart';
import '../../widgets/answer_tile.dart';
import '../../widgets/language_kit.dart';
import '../language/display_names.dart';
import 'reading_data.dart';
import 'word_lookup.dart';

/// Matn o'qish: matn + tushunish savollari.
///
/// ESKI EKRANNING MUAMMOLARI. Matn chap chetga yopishib, kesilib turardi;
/// satr kengligi cheklanmagani uchun kompyuterda bitta qator ~180 belgi
/// bo'lib, ko'z satr oxiridan keyingisining boshiga qaytolmasdi; savollar
/// kartasiz, past kontrastli va javobga munosabatsiz edi.
///
/// MATN EKRANDA QOLADI. Tushunish savoliga javob berayotganda matnga
/// qaytib qarash aldash emas — bu aynan o'qish ko'nikmasi. Keng ekranda
/// matn chapda yopishib turadi, torida esa yig'iladigan kartada.
///
/// DALIL JUMLASI faqat javobdan KEYIN ko'rinadi va o'sha payt matn ichida
/// ham belgilanadi: u javobning o'zi, oldindan bersak matnni o'qish
/// keraksiz bo'lib qolardi.
class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({super.key, required this.passageId});

  final String passageId;

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

/// Ikki ustun shu kenglikdan boshlanadi. Undan tor bo'lsa, matn ham,
/// savol ham juda siqilib qolardi.
const double _kTwoColumn = 1000;
const double _kMaxWidth = 1100;

/// Har bir to'g'ri javob uchun XP — mashq oqimidagi bilan bir xil.
const int _kXpPerCorrect = 10;

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  int _index = 0;
  String? _picked;
  final _results = <String, ReadingAnswer>{};
  bool _busy = false;
  String? _error;
  int _coins = 0;
  bool _passageOpen = true;
  bool _finished = false;
  DateTime? _openedAt;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
  }

  ReadingAnswer? get _current {
    final qs = _questions;
    if (qs == null || _index >= qs.length) return null;
    return _results[qs[_index].id];
  }

  List<ReadingQuestion>? _questions;

  int get _correctCount =>
      _results.values.where((r) => r.correct).length;

  Future<void> _check(ReadingQuestion q) async {
    if (_busy || _picked == null || _results.containsKey(q.id)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ms = _openedAt == null
          ? null
          : DateTime.now().difference(_openedAt!).inMilliseconds;
      final r = await ref
          .read(readingRepositoryProvider)
          .answer(q.id, _picked, responseMs: ms);
      final sfx = ref.read(soundServiceProvider);
      r.correct ? sfx.correct() : sfx.wrong();
      r.correct
          ? HapticFeedback.lightImpact()
          : HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {
          _results[q.id] = r;
          _coins += r.coinsAwarded;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e, L10n.of(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next(int total) {
    if (_index + 1 >= total) {
      ref.read(soundServiceProvider).complete();
      setState(() => _finished = true);
      ref.invalidate(passagesProvider);
      return;
    }
    setState(() {
      _index += 1;
      _picked = null;
      _openedAt = DateTime.now();
    });
  }

  void _restart() {
    setState(() {
      _index = 0;
      _picked = null;
      _results.clear();
      _finished = false;
      _coins = 0;
      _openedAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final async = ref.watch(passageProvider(widget.passageId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l.readingTitle),
        actions: [
          if (_coins > 0)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.md),
              child: Center(
                  child: Text('+$_coins',
                      style: Theme.of(context).textTheme.titleSmall)),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: OwlEmptyState(
            state: OwlState.confused,
            title: l.vocabLoadFailedTitle,
            message: humanError(e, l),
            actionLabel: l.retry,
            onAction: () =>
                ref.invalidate(passageProvider(widget.passageId)),
          ),
        ),
        data: (p) {
          _questions = p.questions;
          if (p.questions.isEmpty) {
            return Center(
              child: OwlEmptyState(
                key: const Key('reading-no-questions'),
                state: OwlState.reading,
                title: l.readingNoQuestionsTitle,
                message: l.readingNoQuestionsBody,
              ),
            );
          }
          if (_finished) {
            return _Results(
              correct: _correctCount,
              total: p.questions.length,
              onRetry: _restart,
              onMore: () => Navigator.pop(context),
            );
          }
          return LayoutBuilder(
            builder: (context, c) => c.maxWidth >= _kTwoColumn
                ? _wide(p)
                : _narrow(p),
          );
        },
      ),
    );
  }

  // ---- keng ekran: ikki ustun ---------------------------------------------
  Widget _wide(PassageDetail p) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxWidth),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  // Matn yopishib turadi: savolga javob berayotganda ham
                  // ko'rinib tursin.
                  child: SingleChildScrollView(
                    child: _PassageCard(
                      passage: p,
                      highlight: _current?.evidenceSpan,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.lg),
                Expanded(flex: 4, child: _questionPane(p)),
              ],
            ),
          ),
        ),
      );

  // ---- tor ekran: matn tepada, yig'iladi ----------------------------------
  Widget _narrow(PassageDetail p) => ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          _PassageCard(
            passage: p,
            highlight: _current?.evidenceSpan,
            collapsed: !_passageOpen,
            onToggle: () => setState(() => _passageOpen = !_passageOpen),
          ),
          const Gap.md(),
          _questionPane(p),
        ],
      );

  Widget _questionPane(PassageDetail p) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final q = p.questions[_index];
    final r = _results[q.id];
    final total = p.questions.length;

    AnswerState stateOf(String id) {
      if (r == null) return id == _picked ? AnswerState.picked : AnswerState.idle;
      if (id == r.correctOptionId) return AnswerState.correct;
      if (id == _picked) return AnswerState.wrong;
      return AnswerState.idle;
    }

    return Column(
      key: ValueKey('q-$_index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // "6 ta savol" sarlavhasi emas — qayerdaligi muhim.
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (_index + 1) / total),
                  duration: 220.ms,
                  curve: Curves.easeOut,
                  builder: (_, v, __) => LinearProgressIndicator(
                      value: v, minHeight: 6),
                ),
              ),
            ),
            const Gap.sm(),
            Text('${_index + 1}/$total',
                style: theme.textTheme.labelLarge),
          ],
        ),
        const Gap.md(),
        Text(
          q.questionText,
          key: const Key('reading-question'),
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w600, height: 1.35),
        ),
        const Gap.md(),
        for (final o in q.options)
          AnswerTile(
            key: Key('reading-option-${o.id}'),
            letter: o.id.toUpperCase(),
            text: o.text,
            state: stateOf(o.id),
            onTap: r != null || _busy
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() => _picked = o.id);
                  },
          ),
        if (r != null) ...[
          const Gap.sm(),
          FeedbackBanner(
            key: const Key('reading-feedback'),
            correct: r.correct,
            title: r.correct
                ? l.readingCorrect
                : l.readingWrong(r.correctOptionId.toUpperCase()),
            evidenceLabel: l.readingEvidenceLabel,
            evidence: r.evidenceSpan,
            xp: r.correct ? _kXpPerCorrect : null,
          ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.15),
        ],
        if (_error != null) ...[
          const Gap.sm(),
          Text(_error!,
              key: const Key('reading-error'),
              style: TextStyle(color: theme.colorScheme.error)),
        ],
        const Gap.md(),
        PrimaryButton(
          key: const Key('reading-primary'),
          label: r == null
              ? l.readingCheck
              : (_index + 1 >= total ? l.readingSeeResult : l.grammarNext),
          expand: true,
          // Variant tanlanmaguncha o'chirilgan: bo'sh javobni yuborish
          // savolni behuda sarflaydi.
          onPressed: r == null
              ? (_picked == null || _busy ? null : () => _check(q))
              : () => _next(total),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------- //
//  Matn kartasi                                                                //
// --------------------------------------------------------------------------- //
class _PassageCard extends ConsumerWidget {
  const _PassageCard({
    required this.passage,
    this.highlight,
    this.collapsed = false,
    this.onToggle,
  });

  final PassageDetail passage;
  final String? highlight;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final uiLang = ref.watch(localeCodeProvider);
    final canSpeak =
        ref.watch(pronounceSupportedProvider(passage.language)).valueOrNull ==
            true;
    final topic = DisplayNames.readingTopic(passage.topic, uiLang);

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LevelChip(passage.cefrLevel),
              Text(l.readingMeta(passage.wordCount, passage.readMinutes),
                  style: theme.textTheme.bodySmall),
              if (topic.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.ms, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(topic,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: cs.onSecondaryContainer)),
                ),
            ],
          ),
          const Gap.sm(),
          Row(
            children: [
              if (canSpeak) ...[
                IconButton.filledTonal(
                  key: const Key('reading-listen'),
                  icon: const Icon(Icons.volume_up_rounded),
                  tooltip: l.readingListen,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => ref
                      .read(pronounceServiceProvider)
                      .say(passage.body, passage.language),
                ),
                const SizedBox(width: Spacing.sm),
                IconButton.outlined(
                  key: const Key('reading-listen-slow'),
                  icon: const Icon(Icons.slow_motion_video_rounded),
                  tooltip: l.readingListenSlow,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => ref
                      .read(pronounceServiceProvider)
                      .say(passage.body, passage.language, slow: true),
                ),
              ],
              const Spacer(),
              if (onToggle != null)
                TextButton.icon(
                  key: const Key('reading-toggle'),
                  onPressed: onToggle,
                  icon: Icon(collapsed
                      ? Icons.expand_more
                      : Icons.expand_less),
                  label:
                      Text(collapsed ? l.readingShowText : l.readingHideText),
                ),
            ],
          ),
          if (!collapsed) ...[
            const Gap.sm(),
            TappableText(
              text: passage.body,
              language: passage.language,
              highlight: highlight,
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  Natija                                                                      //
// --------------------------------------------------------------------------- //
class _Results extends StatelessWidget {
  const _Results({
    required this.correct,
    required this.total,
    required this.onRetry,
    required this.onMore,
  });

  final int correct;
  final int total;
  final VoidCallback onRetry;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final share = total == 0 ? 0.0 : correct / total;
    final good = share >= 0.8;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: ContentWidth(
          maxWidth: 460,
          child: Column(
            key: const Key('reading-results'),
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: share),
                      duration: 700.ms,
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => SizedBox(
                        width: 150,
                        height: 150,
                        child: CircularProgressIndicator(
                          value: v,
                          strokeWidth: 12,
                          strokeCap: StrokeCap.round,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    Text('${(share * 100).round()}%',
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const Gap.md(),
              BreathingOwl(
                state: good ? OwlState.cheering : OwlState.idle,
                size: 110,
              ),
              const Gap.md(),
              Text(l.readingScore(correct, total),
                  style: theme.textTheme.titleLarge),
              const Gap.xs(),
              Text('+${correct * _kXpPerCorrect} XP',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary)),
              const Gap.lg(),
              PrimaryButton(
                key: const Key('reading-retry'),
                label: l.readingRetry,
                icon: Icons.refresh,
                expand: true,
                onPressed: onRetry,
              ),
              const Gap.sm(),
              OutlinedButton(
                key: const Key('reading-more'),
                onPressed: onMore,
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52)),
                child: Text(l.readingMore),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
