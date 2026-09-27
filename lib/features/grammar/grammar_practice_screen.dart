import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import 'grammar_data.dart';

/// Grammatika mashqi: savol -> variant tanlash -> natija.
///
/// TO'G'RI JAVOB OLDINDAN KELMAYDI. `/practice` faqat savol va variantlarni
/// beradi; to'g'ri variant `/answer` javobida, ya'ni tanlagandan KEYIN.
/// Shuning uchun bu ekranda "javobni bilib turib ko'rsatmaslik" degan holat
/// yo'q — javob shunchaki hali mavjud emas.
///
/// IZOH YO'Q (23 600/23 600). Xato javobdan keyin o'quvchiga faqat to'g'ri
/// variant va QAYSI QOIDA ekani ko'rsatiladi. Bu kam, lekin yolg'on emas:
/// izoh o'rniga o'ylab topilgan matn yozish xato o'rgatish bo'lardi.
class GrammarPracticeScreen extends ConsumerStatefulWidget {
  const GrammarPracticeScreen({super.key, required this.query});

  final GrammarQuery query;

  @override
  ConsumerState<GrammarPracticeScreen> createState() =>
      _GrammarPracticeScreenState();
}

class _GrammarPracticeScreenState
    extends ConsumerState<GrammarPracticeScreen> {
  List<GrammarQuestion>? _questions;
  int _index = 0;
  String? _picked;
  GrammarAnswer? _result;
  bool _busy = false;
  String? _error;
  int _correct = 0;
  int _coins = 0;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final qs = await ref
          .read(grammarRepositoryProvider)
          .practice(widget.query, limit: 10);
      if (mounted) {
        setState(() {
          _questions = qs;
          _shownAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _questions = const [];
          _error = humanError(e, L10n.of(context));
        });
      }
    }
  }

  GrammarQuestion? get _current {
    final q = _questions;
    if (q == null || _index >= q.length) return null;
    return q[_index];
  }

  Future<void> _submit(String? optionId) async {
    final q = _current;
    if (q == null || _busy || _result != null) return;
    setState(() {
      _busy = true;
      _picked = optionId;
      _error = null;
    });
    try {
      final ms = _shownAt == null
          ? null
          : DateTime.now().difference(_shownAt!).inMilliseconds;
      final r = await ref
          .read(grammarRepositoryProvider)
          .answer(q.id, optionId, responseMs: ms);
      if (mounted) {
        setState(() {
          _result = r;
          if (r.correct) _correct += 1;
          _coins += r.coinsAwarded;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _picked = null;
          _error = humanError(e, L10n.of(context));
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    setState(() {
      _index += 1;
      _picked = null;
      _result = null;
      _shownAt = DateTime.now();
    });
  }

  void _finish() {
    ref.invalidate(grammarMasteryProvider);
    ref.invalidate(grammarTopicsProvider);
    Navigator.pop(context);
  }

  Color? _optionColour(String id, ColorScheme cs) {
    final r = _result;
    if (r == null) return null;
    if (id == r.correctOptionId) return cs.primaryContainer;
    if (id == _picked) return cs.errorContainer;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final questions = _questions;

    if (questions == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.grammarPracticeTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l.grammarPracticeTitle)),
        body: Center(
          child: EmptyState(
            key: const Key('grammar-empty'),
            icon: Icons.search_off,
            title: l.grammarNoQuestionsTitle,
            message: _error ?? l.grammarNoQuestionsBody,
            actionLabel: l.vocabSessionDoneAction,
            onAction: () => Navigator.pop(context),
          ),
        ),
      );
    }

    final q = _current;
    if (q == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.grammarPracticeTitle)),
        body: Center(
          child: EmptyState(
            key: const Key('grammar-done'),
            icon: Icons.task_alt,
            title: l.grammarSessionDoneTitle,
            message: l.grammarSessionDoneBody(_correct, questions.length) +
                (_coins > 0 ? '\n+$_coins' : ''),
            actionLabel: l.vocabSessionDoneAction,
            onAction: _finish,
          ),
        ),
      );
    }

    final r = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${questions.length}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(value: _index / questions.length),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Chip(
                          label: Text(q.cefrLevel),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(q.topic,
                              style: theme.textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                      const Gap.md(),
                      Text(
                        q.questionText,
                        key: const Key('grammar-question'),
                        style: theme.textTheme.headlineSmall,
                      ),
                      const Gap.lg(),
                      for (final o in q.options) ...[
                        Card(
                          key: Key('grammar-option-${o.id}'),
                          margin: const EdgeInsets.only(bottom: Spacing.sm),
                          color: _optionColour(o.id, theme.colorScheme),
                          child: ListTile(
                            enabled: !_busy && r == null,
                            title: Text(o.text),
                            leading: CircleAvatar(
                              radius: 14,
                              child: Text(o.id.toUpperCase(),
                                  style: theme.textTheme.labelSmall),
                            ),
                            trailing: r == null
                                ? null
                                : o.id == r.correctOptionId
                                    ? const Icon(Icons.check)
                                    : (o.id == _picked
                                        ? const Icon(Icons.close)
                                        : null),
                            onTap: () => _submit(o.id),
                          ),
                        ),
                      ],
                      if (r != null) ...[
                        const Gap.sm(),
                        Card(
                          key: const Key('grammar-feedback'),
                          color: r.correct
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.all(Spacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.correct
                                      ? l.grammarCorrect
                                      : l.grammarIncorrect,
                                  style: theme.textTheme.titleMedium,
                                ),
                                // Izoh bank'da yo'q. Bo'sh joyni matn bilan
                                // to'ldirmaymiz — qaysi qoida ekani aytiladi,
                                // shu holicha.
                                if ((r.explanation ?? '').isNotEmpty) ...[
                                  const Gap.sm(),
                                  Text(r.explanation!),
                                ] else ...[
                                  const Gap.sm(),
                                  Text(l.grammarRuleLabel(r.topic),
                                      style: theme.textTheme.bodySmall),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const Gap.sm(),
                        Text(_error!,
                            key: const Key('grammar-error'),
                            style:
                                TextStyle(color: theme.colorScheme.error)),
                      ],
                    ],
                  ),
                ),
              ),
              const Gap.sm(),
              if (r != null)
                FilledButton(
                  key: const Key('grammar-next'),
                  onPressed: _next,
                  child: Text(_index + 1 >= questions.length
                      ? l.grammarFinish
                      : l.grammarNext),
                )
              else
                OutlinedButton(
                  key: const Key('grammar-skip'),
                  // NULL, bo'sh satr EMAS: backend `selected_option_id IS
                  // NULL` ni "o'tkazib yuborildi" deb saqlaydi, '' esa
                  // qilinmagan tanlovni qilingan qilib ko'rsatardi.
                  onPressed: _busy ? null : () => _submit(null),
                  child: Text(l.grammarSkip),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
