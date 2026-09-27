import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../core/sound.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import 'reading_data.dart';

/// Bitta matn: o'qish, keyin savollar.
///
/// MATN SAVOLLAR BILAN BIRGA EKRANDA QOLADI. Tushunish savoliga javob
/// berayotganda matnga qaytib qarash — bu aldash emas, aynan o'qish
/// ko'nikmasi. Matnni yashirish xotira mashqiga aylantirardi.
///
/// DALIL JUMLASI faqat javobdan KEYIN ko'rsatiladi — u matndagi aynan
/// o'sha gap, ya'ni javobning o'zi.
class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({super.key, required this.passageId});

  final String passageId;

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  final _picked = <String, String?>{};
  final _results = <String, ReadingAnswer>{};
  final _busy = <String>{};
  String? _error;
  int _coins = 0;
  DateTime? _openedAt;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
  }

  Future<void> _answer(ReadingQuestion q, String? optionId) async {
    if (_busy.contains(q.id) || _results.containsKey(q.id)) return;
    setState(() {
      _busy.add(q.id);
      _picked[q.id] = optionId;
      _error = null;
    });
    try {
      final ms = _openedAt == null
          ? null
          : DateTime.now().difference(_openedAt!).inMilliseconds;
      final r = await ref
          .read(readingRepositoryProvider)
          .answer(q.id, optionId, responseMs: ms);
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
      if (mounted) {
        setState(() {
          _picked.remove(q.id);
          _error = humanError(e, L10n.of(context));
        });
      }
    } finally {
      if (mounted) setState(() => _busy.remove(q.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(passageProvider(widget.passageId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l.readingTitle),
        actions: [
          if (_coins > 0)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.md),
              child: Center(child: Text('+$_coins')),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: EmptyState(
            icon: Icons.cloud_off,
            title: l.vocabLoadFailedTitle,
            message: humanError(e, l),
            actionLabel: l.retry,
            onAction: () =>
                ref.invalidate(passageProvider(widget.passageId)),
          ),
        ),
        data: (p) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Row(children: [
              Chip(
                  label: Text(p.cefrLevel),
                  visualDensity: VisualDensity.compact),
              const SizedBox(width: Spacing.sm),
              Text(l.readingMeta(p.wordCount, p.readMinutes),
                  style: theme.textTheme.bodySmall),
            ]),
            if ((p.topic ?? '').isNotEmpty) ...[
              const Gap.xs(),
              Text(p.topic!, style: theme.textTheme.bodySmall),
            ],
            const Gap.md(),

            // ---- matn -------------------------------------------------
            SelectableText(
              p.body,
              key: const Key('reading-body'),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
            const Gap.lg(),
            const Divider(),
            const Gap.md(),

            if (p.questions.isEmpty)
              EmptyState(
                key: const Key('reading-no-questions'),
                icon: Icons.help_outline,
                title: l.readingNoQuestionsTitle,
                message: l.readingNoQuestionsBody,
                compact: true,
              )
            else
              Text(l.readingQuestionsTitle(p.questions.length),
                  style: theme.textTheme.titleMedium),
            const Gap.md(),

            // ---- savollar ----------------------------------------------
            for (var i = 0; i < p.questions.length; i++) ...[
              _QuestionCard(
                index: i + 1,
                question: p.questions[i],
                picked: _picked[p.questions[i].id],
                result: _results[p.questions[i].id],
                busy: _busy.contains(p.questions[i].id),
                onPick: (o) => _answer(p.questions[i], o),
              ),
              const Gap.md(),
            ],

            if (_error != null)
              Text(_error!,
                  key: const Key('reading-error'),
                  style: TextStyle(color: theme.colorScheme.error)),

            if (p.questions.isNotEmpty &&
                _results.length >= p.questions.length) ...[
              const Gap.md(),
              FilledButton(
                key: const Key('reading-finish'),
                onPressed: () {
                  ref.invalidate(passagesProvider);
                  Navigator.pop(context);
                },
                child: Text(l.grammarFinish),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.picked,
    required this.result,
    required this.busy,
    required this.onPick,
  });

  final int index;
  final ReadingQuestion question;
  final String? picked;
  final ReadingAnswer? result;
  final bool busy;
  final void Function(String?) onPick;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final r = result;

    Color? colour(String id) {
      if (r == null) return null;
      if (id == r.correctOptionId) return cs.primaryContainer;
      if (id == picked) return cs.errorContainer;
      return null;
    }

    return Card(
      key: Key('reading-q-${question.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$index. ${question.questionText}',
                style: theme.textTheme.titleSmall),
            const Gap.sm(),
            for (final o in question.options)
              Container(
                margin: const EdgeInsets.only(bottom: Spacing.xs),
                decoration: BoxDecoration(
                  color: colour(o.id),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  dense: true,
                  enabled: !busy && r == null,
                  title: Text(o.text),
                  leading: Text(o.id.toUpperCase(),
                      style: theme.textTheme.labelLarge),
                  trailing: r == null
                      ? null
                      : o.id == r.correctOptionId
                          ? const Icon(Icons.check, size: 18)
                          : (o.id == picked
                              ? const Icon(Icons.close, size: 18)
                              : null),
                  onTap: () => onPick(o.id),
                ),
              ),
            if (r != null && (r.evidenceSpan ?? '').isNotEmpty) ...[
              const Gap.sm(),
              // MATNDAGI AYNAN O'SHA GAP. Bu modulda "nega shunday" degan
              // savolga javob beradigan yagona joy — grammatikada izoh
              // umuman yo'q.
              Container(
                key: Key('reading-evidence-${question.id}'),
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  border: Border(
                      left: BorderSide(color: cs.primary, width: 3)),
                  color: cs.surfaceContainerHighest,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.readingEvidenceLabel,
                        style: theme.textTheme.labelSmall),
                    const Gap.xs(),
                    Text(r.evidenceSpan!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ],
            if (r == null) ...[
              const Gap.xs(),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: Key('reading-skip-${question.id}'),
                  // NULL — backend `selected_option_id IS NULL` ni
                  // "o'tkazib yuborildi" deb saqlaydi.
                  onPressed: busy ? null : () => onPick(null),
                  child: Text(l.grammarSkip),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
