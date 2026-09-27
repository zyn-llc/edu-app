import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/api_error.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import 'vocab_data.dart';

/// Takrorlash seansi: kartochka -> o'zingizni tekshiring -> baho.
///
/// JADVALNI SERVER HISOBLAYDI. Bu yerda SM-2 ning nusxasi YO'Q — tugma
/// bosilganda `POST /v1/vocab/review` chaqiriladi va keyingi sana javobdan
/// olinadi. Ikki joyda ikki nusxa bo'lsa, ular ajralib ketardi va o'quvchi
/// so'zni noto'g'ri kunda ko'rardi — buni esa hech kim sezmaydi.
///
/// Kartochkalar seans BOSHIDA bir marta olinadi. Har javobdan keyin qayta
/// so'rasak, endi javob berilgan so'z ro'yxatdan chiqib ketardi va ro'yxat
/// oyoq ostidan siljib turardi.
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
      if (mounted) setState(() => _cards = cards);
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

  Future<void> _grade(RecallGrade g) async {
    final card = _current;
    if (card == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(vocabRepositoryProvider).review(card.id, g);
      _graded[card.id] = g;
      if (mounted) {
        setState(() {
          _coins += r.coinsAwarded;
          _index += 1;
          _revealed = false;
        });
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
    // Seans tugadi: to'plam va statistika o'zgargan.
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
          ),
        ),
      );
    }

    final translation = card.translation(uiLang);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${cards.length}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(value: _index / cards.length),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(card.cefrLevel,
                            style: theme.textTheme.labelMedium),
                        const Gap.sm(),
                        // Nemis oti artikli bilan keladi ("der Tisch") —
                        // serverda yasalgan, bu yerda yig'ilmaydi.
                        Text(
                          card.display,
                          key: const Key('vocab-card-front'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displaySmall,
                        ),
                        if ((card.ipa ?? '').isNotEmpty) ...[
                          const Gap.xs(),
                          // Audio manbada yo'q; IPA — uni eshitmasdan
                          // talaffuzni bilishning yagona yo'li.
                          Text(card.ipa!,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                        const Gap.lg(),
                        if (_revealed) ...[
                          const Divider(),
                          const Gap.md(),
                          Text(
                            translation ?? l.vocabNoTranslation,
                            key: const Key('vocab-card-back'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          if ((card.pos ?? '').isNotEmpty) ...[
                            const Gap.xs(),
                            Text(card.pos!,
                                style: theme.textTheme.bodySmall),
                          ],
                        ],
                      ],
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
                // Uchta tugma, olti bosqichli baho emas: odamdan aniq baho
                // so'rash uni o'ylantiradi va seansni sekinlashtiradi.
                Row(
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}
