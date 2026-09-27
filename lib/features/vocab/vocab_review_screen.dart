import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/api_error.dart';
import '../../core/pronounce.dart';
import '../../core/sound.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import 'flip_card.dart';
import 'vocab_data.dart';

/// Takrorlash seansi: kartochka -> ag'darish -> baho.
///
/// JADVALNI SERVER HISOBLAYDI. Bu yerda SM-2 ning nusxasi YO'Q — tugma
/// bosilganda `POST /v1/vocab/review` chaqiriladi va keyingi sana javobdan
/// olinadi. Ikki joyda ikki nusxa ajralib ketardi va o'quvchi so'zni
/// noto'g'ri kunda ko'rardi — buni esa hech kim sezmaydi.
///
/// Kartochkalar seans BOSHIDA bir marta olinadi. Har javobdan keyin qayta
/// so'rasak, javob berilgan so'z ro'yxatdan chiqib, ro'yxat oyoq ostidan
/// siljib turardi.
///
/// TALAFFUZ — qurilmaning sintezatoridan (`core/pronounce.dart`). Til uchun
/// ovoz bo'lmasa tugma UMUMAN ko'rsatilmaydi: nemischa so'zni inglizcha
/// ovozda o'qitish noto'g'ri talaffuzni o'rgatish bo'lardi.
class VocabReviewScreen extends ConsumerStatefulWidget {
  const VocabReviewScreen({super.key, required this.language});

  final String? language;

  @override
  ConsumerState<VocabReviewScreen> createState() => _VocabReviewScreenState();
}

class _VocabReviewScreenState extends ConsumerState<VocabReviewScreen> {
  List<VocabEntry>? _cards;
  int _index = 0;
  bool _revealed = false;
  bool _busy = false;
  String? _error;
  int _coins = 0;
  final _graded = <String, RecallGrade>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cards =
          await ref.read(vocabRepositoryProvider).due(widget.language);
      if (mounted) {
        setState(() => _cards = cards);
        _speakCurrent();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cards = const [];
          _error = humanError(e, L10n.of(context));
        });
      }
    }
  }

  VocabEntry? get _current {
    final c = _cards;
    if (c == null || _index >= c.length) return null;
    return c[_index];
  }

  /// Yangi kartochka chiqqanda so'zni bir marta aytish — talaffuz so'zning
  /// bir qismi, uni eshitish uchun alohida harakat talab qilmaslik kerak.
  void _speakCurrent() {
    final card = _current;
    if (card == null) return;
    ref.read(pronounceServiceProvider).say(card.lemma, card.language);
  }

  Future<void> _grade(RecallGrade g) async {
    final card = _current;
    if (card == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Haptika — javob qabul qilingani darhol seziladi, tarmoqni kutmasdan.
    HapticFeedback.selectionClick();
    try {
      final r = await ref.read(vocabRepositoryProvider).review(card.id, g);
      _graded[card.id] = g;
      final sfx = ref.read(soundServiceProvider);
      g == RecallGrade.forgot ? sfx.wrong() : sfx.correct();
      if (mounted) {
        setState(() {
          _coins += r.coinsAwarded;
          _index += 1;
          _revealed = false;
        });
        _speakCurrent();
      }
    } on DioException catch (e) {
      if (mounted) setState(() => _error = humanError(e, L10n.of(context)));
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e, L10n.of(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() {
    ref.invalidate(vocabStatsProvider);
    ref.invalidate(vocabDueProvider);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final uiLang = ref.watch(localeCodeProvider);
    final cards = _cards;

    if (cards == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.vocabReviewTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l.vocabReviewTitle)),
        body: Center(
          child: EmptyState(
            key: const Key('vocab-review-empty'),
            icon: Icons.check_circle_outline,
            title: l.vocabNothingDueTitle,
            message: _error ?? l.vocabNothingDueBody,
            actionLabel: l.vocabBrowseAction,
            onAction: () => Navigator.pop(context),
          ),
        ),
      );
    }

    final card = _current;
    if (card == null) {
      final forgot =
          _graded.values.where((g) => g == RecallGrade.forgot).length;
      // Seans oxiri — yagona joy, u yerda "tugadi" ovozi o'rinli.
      ref.read(soundServiceProvider).complete();
      return Scaffold(
        appBar: AppBar(title: Text(l.vocabReviewTitle)),
        body: Center(
          child: EmptyState(
            key: const Key('vocab-review-done'),
            icon: Icons.emoji_events_outlined,
            title: l.vocabSessionDoneTitle,
            message: l.vocabSessionDoneBody(cards.length, forgot) +
                (_coins > 0 ? '\n+$_coins' : ''),
            actionLabel: l.vocabSessionDoneAction,
            onAction: _finish,
          ).animate().fadeIn(duration: 300.ms).scale(
              begin: const Offset(0.92, 0.92), curve: Curves.easeOutBack),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${cards.length}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _index / cards.length),
            duration: 350.ms,
            curve: Curves.easeOut,
            builder: (_, v, __) =>
                LinearProgressIndicator(value: v, minHeight: 3),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: GestureDetector(
                    key: const Key('vocab-card'),
                    // Kartochkaning o'ziga bosish ham ag'daradi — pastdagi
                    // tugmaga tegish shart emas.
                    onTap: _revealed
                        ? null
                        : () => setState(() => _revealed = true),
                    child: FlipCard(
                      showBack: _revealed,
                      front: _CardFace(
                        key: ValueKey('front-${card.id}'),
                        card: card,
                        child: _Front(card: card),
                      ),
                      back: _CardFace(
                        key: ValueKey('back-${card.id}'),
                        card: card,
                        tinted: true,
                        child: _Back(card: card, uiLang: uiLang),
                      ),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                Text(_error!,
                    key: const Key('vocab-review-error'),
                    style: TextStyle(color: theme.colorScheme.error)),
                const Gap.sm(),
              ],
              if (!_revealed)
                FilledButton(
                  key: const Key('vocab-reveal'),
                  onPressed: () => setState(() => _revealed = true),
                  child: Text(l.vocabReveal),
                )
              else
                Row(
                  key: const Key('vocab-grades'),
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('vocab-grade-forgot'),
                        onPressed:
                            _busy ? null : () => _grade(RecallGrade.forgot),
                        child: Text(l.vocabGradeForgot),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('vocab-grade-hard'),
                        onPressed:
                            _busy ? null : () => _grade(RecallGrade.hard),
                        child: Text(l.vocabGradeHard),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: FilledButton(
                        key: const Key('vocab-grade-easy'),
                        onPressed:
                            _busy ? null : () => _grade(RecallGrade.easy),
                        child: Text(l.vocabGradeEasy),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.25),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartochka qobig'i — ikkala tomon uchun bir xil o'lcham va shakl.
/// Aks holda ag'darishda kartochka "sakrab" ketardi.
class _CardFace extends StatelessWidget {
  const _CardFace({
    super.key,
    required this.card,
    required this.child,
    this.tinted = false,
  });

  final VocabEntry card;
  final Widget child;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 280, maxWidth: 460),
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tinted
              ? [cs.primaryContainer, cs.surfaceContainerHighest]
              : [cs.surfaceContainerLowest, cs.surfaceContainerHigh],
        ),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(child: child),
    );
  }
}

class _Front extends ConsumerWidget {
  const _Front({required this.card});

  final VocabEntry card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LevelChip(card.cefrLevel),
        const Gap.md(),
        Text(
          card.display,
          key: const Key('vocab-card-front'),
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600),
        ),
        if ((card.ipa ?? '').isNotEmpty) ...[
          const Gap.xs(),
          // Audio manbada yo'q; IPA — talaffuzning yagona yozma ko'rinishi
          // va u 100 % ingliz yozuvlarida bor.
          Text(card.ipa!,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        const Gap.md(),
        _SpeakButton(card: card),
        const Gap.lg(),
        Text(l.vocabTapToFlip, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({required this.card, required this.uiLang});

  final VocabEntry card;
  final String uiLang;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(card.display,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const Gap.md(),
        Text(
          card.translation(uiLang) ?? l.vocabNoTranslation,
          key: const Key('vocab-card-back'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        if ((card.pos ?? '').isNotEmpty) ...[
          const Gap.sm(),
          Text(card.pos!, style: theme.textTheme.bodySmall),
        ],
        const Gap.md(),
        _SpeakButton(card: card),
      ],
    );
  }
}

/// Talaffuz tugmasi. Til uchun ovoz bo'lmasa — UMUMAN ko'rsatilmaydi.
class _SpeakButton extends ConsumerWidget {
  const _SpeakButton({required this.card});

  final VocabEntry card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported =
        ref.watch(pronounceSupportedProvider(card.language)).valueOrNull;
    // `null` — hali tekshirilmoqda. Tugmani ko'rsatib, keyin yo'qotish
    // sakrab turgan interfeys beradi, shuning uchun kutamiz.
    if (supported != true) return const SizedBox.shrink();
    return IconButton.filledTonal(
      key: const Key('vocab-speak'),
      icon: const Icon(Icons.volume_up_outlined),
      tooltip: L10n.of(context).vocabListen,
      onPressed: () =>
          ref.read(pronounceServiceProvider).say(card.lemma, card.language),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip(this.level);

  final String level;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(level,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: cs.onSecondaryContainer)),
    );
  }
}
