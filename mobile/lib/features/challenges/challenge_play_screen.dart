import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/api_error.dart';
import '../../core/math_widget.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/empty_state.dart';
import '../quiz/quiz_data.dart' show Question;
import 'challenges_data.dart';

/// Plays a challenge: same frozen question set as the opponent, NO per-question
/// feedback (this is a bet — corrections would leak the answer key mid-game).
/// Answers are collected locally and submitted in ONE batch at the end.
class ChallengePlayScreen extends ConsumerStatefulWidget {
  final Challenge challenge;
  const ChallengePlayScreen({super.key, required this.challenge});

  @override
  ConsumerState<ChallengePlayScreen> createState() =>
      _ChallengePlayScreenState();
}

class _ChallengePlayScreenState extends ConsumerState<ChallengePlayScreen> {
  List<Question>? _questions;
  int _index = 0;
  final Map<String, Map<String, dynamic>> _answers = {};
  final TextEditingController _typed = TextEditingController();
  String? _selected;
  bool _submitting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lang = ref.read(localeCodeProvider);
      final qs = await ref
          .read(challengeRepositoryProvider)
          .questions(widget.challenge.id, lang);
      setState(() => _questions = qs);
    } catch (e) {
      setState(() => _error = e);
    }
  }

  bool _isTyped(Question q) =>
      q.type == 'numeric' || q.type == 'open_keyword';

  void _insertSymbol(String value) {
    final text = _typed.text;
    final sel = _typed.selection;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    _typed.value = TextEditingValue(
      text: text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    setState(() {});
  }

  void _next() {
    final q = _questions![_index];
    if (_isTyped(q)) {
      final t = _typed.text.trim();
      _answers[q.id] =
          q.type == 'numeric' ? {'value': t} : {'text': t};
    } else {
      _answers[q.id] = {
        'option_ids': _selected == null ? [] : [_selected!]
      };
    }
    _selected = null;
    _typed.clear();
    if (_index + 1 < _questions!.length) {
      setState(() => _index++);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final res = await ref
          .read(challengeRepositoryProvider)
          .submit(widget.challenge.id, _answers);
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ResultDialog(res: res, stake: widget.challenge.stake),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.navChallenges)),
        body: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: l.errTitle,
          message: humanError(_error!, l),
          actionLabel: l.retry,
          onAction: () {
            setState(() => _error = null);
            _load();
          },
        ),
      );
    }
    if (_questions == null || _submitting) {
      return Scaffold(
        appBar: AppBar(title: Text(l.navChallenges)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final q = _questions![_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${_questions!.length}'),
        // No back mid-bet: leaving forfeits nothing yet (nothing sent), but make
        // the one-shot nature explicit.
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l.challengeLeaveTitle),
                content: Text(l.challengeLeaveBody),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l.cancel)),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).pop();
                    },
                    child: Text(l.challengeLeave),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
                value: (_index + 1) / _questions!.length),
            const SizedBox(height: 16),
            MathText(q.stem, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            // `RadioListTile.groupValue`/`onChanged` Flutter 3.32 da eskirgan.
            Expanded(
              child: RadioGroup<String>(
                groupValue: _selected,
                onChanged: (v) => setState(() => _selected = v),
                child: ListView(
                  children: [
                    for (final o in q.options)
                      Card(
                        child: RadioListTile<String>(
                          value: o.optionKey,
                          title: MathText(o.text),
                        ),
                      ),
                    if (_isTyped(q)) ...[
                      TextField(
                        controller: _typed,
                        keyboardType: TextInputType.text,
                        autocorrect: false,
                        enableSuggestions: false,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9,.\-+/()πer√^ ]')),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: L10n.of(context).typedAnswerLabel,
                          helperText: L10n.of(context).typedAnswerHelp,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final s in const ['a/b', '√', 'π', 'x²', '( )'])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: OutlinedButton(
                                onPressed: () => _insertSymbol(
                                    {'a/b': '/', 'x²': '^', '( )': '()'}[s] ??
                                        s),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(40, 36),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text(s,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            FilledButton(
              onPressed: (_isTyped(q)
                      ? _typed.text.trim().isNotEmpty
                      : _selected != null)
                  ? _next
                  : null,
              child: Text(_index + 1 < _questions!.length
                  ? l.next
                  : l.challengeFinish),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultDialog extends StatelessWidget {
  final ChallengeSubmitResult res;
  final int stake;
  const _ResultDialog({required this.res, required this.stake});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    String title;
    String body;
    if (res.status != 'done') {
      title = l.challengeSheetInTitle;
      body = l.challengeSheetInBody('${res.yourScore}', '${res.maxScore}');
    } else if (res.winnerId == null) {
      title = l.challengeDraw;
      body = l.challengeDrawBody('$stake');
    } else {
      // The submitter is always a participant; if there IS a winner and the
      // status just flipped to done, my_score vs their_score decides — but the
      // here show pot movement generically.
      title = l.challengeSettledTitle;
      body = l.challengeSettledBody('${res.yourScore}', '${res.maxScore}',
          '${stake * 2}');
    }
    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.ok),
        ),
      ],
    );
  }
}
