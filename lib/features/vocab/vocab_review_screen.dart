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
import '../../mascot/mascot.dart';
import '../../theme/level_palette.dart';
import '../../theme/spacing.dart';
import '../../widgets/language_kit.dart';
import '../language/display_names.dart';
import '../language/readable_pronunciation.dart';
import 'flip_card.dart';
import 'vocab_data.dart';

/// So'z kartochkasi.
///
/// JADVALNI SERVER HISOBLAYDI. Bu yerda SM-2 ning nusxasi yo'q — baho
/// yuboriladi, keyingi sana javobdan keladi. Ikki nusxa ajralib ketardi va
/// o'quvchi so'zni noto'g'ri kunda ko'rardi.
///
/// IPA EKRANGA CHIQMAYDI. Uning o'rniga o'zbek lotinida o'qiladigan
/// talaffuz (`readable_pronunciation.dart`) — va u ham faqat ishonchli
/// bo'lganda.
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

  /// Oxirgi baho — boyqush shunga qarab reaksiya qiladi. Reaksiya QISQA
  /// vaqt ko'rinadi: doimiy tursa, u bezakka aylanadi va e'tibordan
  /// chiqadi.
  RecallGrade? _lastGrade;

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
      _lastGrade = g;
    });
    HapticFeedback.selectionClick();
    // Reaksiyani o'chirish — keyingi kartochkada eski kayfiyat qolmasin.
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _lastGrade = null);
    });
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

  Widget _cardStack(VocabEntry card, String uiLang) => GestureDetector(
        key: const Key('vocab-card'),
        onTap: _revealed
            ? null
            : () {
                HapticFeedback.selectionClick();
                setState(() => _revealed = true);
              },
        child: FlipCard(
          showBack: _revealed,
          front: _CardFace(level: card.cefrLevel, child: _Front(card: card)),
          back: _CardFace(
              level: card.cefrLevel,
              child: _Back(card: card, uiLang: uiLang)),
        ),
      );

  void _finish() {
    ref.invalidate(vocabStatsProvider);
    ref.invalidate(vocabDueProvider);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
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
          child: OwlEmptyState(
            key: const Key('vocab-review-empty'),
            state: OwlState.sleeping,
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
      ref.read(soundServiceProvider).complete();
      return Scaffold(
        appBar: AppBar(title: Text(l.vocabReviewTitle)),
        body: Center(
          child: OwlEmptyState(
            key: const Key('vocab-review-done'),
            state: OwlState.cheering,
            size: 150,
            title: l.vocabSessionDoneTitle,
            message: l.vocabSessionDoneBody(cards.length, forgot) +
                (_coins > 0 ? '\n+$_coins' : ''),
            actionLabel: l.vocabSessionDoneAction,
            onAction: _finish,
          ).animate().fadeIn(duration: 280.ms).scale(
              begin: const Offset(0.93, 0.93), curve: Curves.easeOutBack),
        ),
      );
    }

    // "1 / 1" o'rniga chiziq: qolgan ish HAJMI muhim, raqam emas.
    final progress = _index / cards.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.vocabReviewTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: 380.ms,
            curve: Curves.easeOut,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 4,
              color: LevelPalette.color(
                  card.cefrLevel, Theme.of(context).brightness),
            ),
          ),
        ),
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
      body: SafeArea(
        child: ContentWidth(
          child: Padding(
            // Pastdagi tugmalar ekran chetiga TEGMAYDI.
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, Spacing.lg),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: _cardStack(card, uiLang)),
                      // Boyqush javobga javob beradi: "Bilaman" — bayram,
                      // "Yana ko'rsat" — dalda. Kartochkaning ustida,
                      // burchakda, tez so'nadigan qilib.
                      if (_lastGrade != null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: OwlMascot(
                              _lastGrade == RecallGrade.forgot
                                  ? OwlMood.encouraging
                                  : _lastGrade == RecallGrade.hard
                                      ? OwlMood.tip
                                      : OwlMood.excited,
                              size: 78,
                            )
                                .animate()
                                .fadeIn(duration: 160.ms)
                                .scale(
                                    begin: const Offset(0.7, 0.7),
                                    curve: Curves.easeOutBack)
                                .then(delay: 600.ms)
                                .fadeOut(duration: 260.ms),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const Gap.sm(),
                  Text(_error!,
                      key: const Key('vocab-review-error'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const Gap.md(),
                if (!_revealed)
                  PrimaryButton(
                    key: const Key('vocab-reveal'),
                    label: l.vocabRevealAction,
                    icon: Icons.visibility_outlined,
                    expand: true,
                    onPressed: () => setState(() => _revealed = true),
                  )
                else
                  _GradeRow(busy: _busy, onGrade: _grade)
                      .animate()
                      .fadeIn(duration: 200.ms)
                      .slideY(begin: 0.2, curve: Curves.easeOut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Baho qatori — [Yana ko'rsat] [Qiyin edi] [Bilaman].
///
/// Uchta tugma, chunki oltita bahodan tanlash o'quvchini to'xtatib
/// o'ylantiradi. Har biri aniq bitta SM-2 bahosiga tushadi.
class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.busy, required this.onGrade});

  final bool busy;
  final void Function(RecallGrade) onGrade;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final cs = Theme.of(context).colorScheme;
    return Row(
      key: const Key('vocab-grades'),
      children: [
        Expanded(
          child: _GradeButton(
            key: const Key('vocab-grade-forgot'),
            label: l.vocabGradeForgot,
            color: cs.error,
            onPressed: busy ? null : () => onGrade(RecallGrade.forgot),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: _GradeButton(
            key: const Key('vocab-grade-hard'),
            label: l.vocabGradeHard,
            color: cs.tertiary,
            onPressed: busy ? null : () => onGrade(RecallGrade.hard),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: _GradeButton(
            key: const Key('vocab-grade-easy'),
            label: l.vocabGradeEasy,
            color: cs.primary,
            filled: true,
            onPressed: busy ? null : () => onGrade(RecallGrade.easy),
          ),
        ),
      ],
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md));
    // 52 px — barmoq uchun ishonchli maydon, uchtasi 360 px ga sig'adi.
    const size = Size(0, 52);
    return filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
                minimumSize: size,
                shape: shape,
                backgroundColor: color),
            child: _Label(label),
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
                minimumSize: size,
                shape: shape,
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.5))),
            child: _Label(label),
          );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, height: 1.15),
      );
}

/// Kartochka qobig'i — IKKALA tomon uchun bir xil.
///
/// Old va orqa tomon bir xil ko'rinishda bo'lishi SHART: ag'darilganda
/// fon o'zgarsa, kartochka almashgandek tuyuladi va ag'darish uzilib
/// qoladi. Farq faqat mazmunida.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.level, required this.child});

  final String level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = LevelPalette.color(level, theme.brightness);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerLowest,
            Color.alphaBlend(accent.withValues(alpha: 0.06), cs.surface),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Align(alignment: Alignment.topLeft, child: LevelChip(level)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
              child: child,
            ),
          ),
        ],
      ),
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
        Text(
          card.display,
          key: const Key('vocab-card-front'),
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Gap.md(),
        _SpeakButton(card: card),
        const Gap.lg(),
        Text(l.vocabTapToFlip,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
    final cs = theme.colorScheme;
    final pos = DisplayNames.pos(card.pos, card.language, uiLang);
    // IPA EMAS — o'zbek lotinida o'qiladigan taxminiy talaffuz.
    final say = readablePronunciation(
        lemma: card.lemma, ipa: card.ipa, language: card.language);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(card.display,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
        const Gap.md(),
        Text(
          card.translation(uiLang) ?? l.vocabNoTranslation,
          key: const Key('vocab-card-back'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (pos.isNotEmpty) ...[
          const Gap.sm(),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.ms, vertical: 2),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(pos,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: cs.onSecondaryContainer)),
          ),
        ],
        if (say != null) ...[
          const Gap.md(),
          Text(l.vocabPronounceLabel, style: theme.textTheme.labelSmall),
          Text(say,
              key: const Key('vocab-card-say'),
              style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic)),
        ],
        const Gap.md(),
        _SpeakButton(card: card),
      ],
    );
  }
}

/// Til uchun ovoz bo'lmasa — tugma UMUMAN chiqmaydi.
class _SpeakButton extends ConsumerWidget {
  const _SpeakButton({required this.card});

  final VocabEntry card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported =
        ref.watch(pronounceSupportedProvider(card.language)).valueOrNull;
    if (supported != true) return const SizedBox.shrink();
    return IconButton.filledTonal(
      key: const Key('vocab-speak'),
      iconSize: 28,
      // 48 px tegish maydoni.
      constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
      icon: const Icon(Icons.volume_up_rounded),
      tooltip: L10n.of(context).vocabListen,
      onPressed: () {
        HapticFeedback.selectionClick();
        ref.read(pronounceServiceProvider).say(card.lemma, card.language);
      },
    );
  }
}
