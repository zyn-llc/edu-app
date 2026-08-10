import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../auth/auth_controller.dart';
import '../../core/breakpoints.dart';
import '../../core/math_widget.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/motion.dart';
import '../../theme/app_colors.dart';
import '../../mascot/mascot.dart';
import '../../core/sound.dart';
import '../../widgets/currency.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/guest_signup_prompt.dart';
import '../challenges/challenges_data.dart';
import '../subjects/subjects.dart';
import 'quiz_data.dart';
import 'result_screen.dart';

const _green = Color(0xFF2FA36B);
const _red = Color(0xFFD64545);
const _perQuestionSeconds = 30;
const _typedQuestionSeconds = 60;

class QuizParams {
  final String subjectId;
  final String subjectCode;
  final int? grade; // null = all levels
  final String? topicId; // null = all topics
  final String? examContext;
  final int count;
  final bool timed;
  QuizParams({
    required this.subjectId,
    required this.subjectCode,
    this.grade,
    this.topicId,
    this.examContext,
    required this.count,
    this.timed = false,
  });
}

class QuizScreen extends ConsumerStatefulWidget {
  final QuizParams params;
  const QuizScreen(this.params, {super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  List<Question> _questions = [];
  bool _loading = true;
  Object? _error;
  bool _submitting = false;

  int _index = 0;
  String? _selected;
  final TextEditingController _typed = TextEditingController();

  /// Typed-answer questions (numeric / open_keyword) render a text field
  bool _isTypedType(Question q) =>
      q.type == 'numeric' || q.type == 'open_keyword';

  bool get _canSubmit {
    final q = _questions[_index];
    return _isTypedType(q) ? _typed.text.trim().isNotEmpty : _selected != null;
  }
  bool _signupPromptShown = false;

  static const _promptAfter = 5;

  GradeResult? _result;
  int _score = 0;
  int _maxScore = 0;
  final _stopwatch = Stopwatch();

  Timer? _ticker;
  int _remaining = _perQuestionSeconds;

  ///
  /// yomon:
  ///
  ///
  bool _timedOut = false;

  ProviderContainer? _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _load();
  }

  @override
  void dispose() {
    _typed.dispose();
    _ticker?.cancel();
    final c = _container;
    if (c != null && (_xpEarned > 0 || _coinsEarned != 0)) {
      // Invalidate after the frame: touching a provider during build throws.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        c.invalidate(meOverviewProvider);
        c.invalidate(analysisProvider);
        c.invalidate(subjectsProvider);
        c.invalidate(coinInfoProvider);
      });
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final qs = await ref.read(quizRepositoryProvider).fetchQuestions(
            widget.params.subjectId,
            grade: widget.params.grade,
            topicId: widget.params.topicId,
            examContext: widget.params.examContext,
            limit: widget.params.count,
          );
      setState(() {
        _questions = qs;
        _loading = false;
      });
      _stopwatch.start();
      _startTimer();
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _startTimer() {
    if (!widget.params.timed) return;
    _ticker?.cancel();
    setState(() {
      _remaining = _isTypedType(_questions[_index])
          ? _typedQuestionSeconds
          : _perQuestionSeconds;
      _timedOut = false;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_result != null) {
        t.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        setState(() => _timedOut = true);
      }
    });
  }

  Future<void> _grade(String? key) async {
    if (_result != null || _submitting) return;
    final l = L10n.of(context);
    setState(() => _submitting = true);
    _ticker?.cancel();
    final q = _questions[_index];
    final Map<String, dynamic> payload = _isTypedType(q)
        ? (q.type == 'numeric'
            ? {'value': _typed.text.trim()}
            : {'text': _typed.text.trim()})
        : {'option_ids': key == null ? [] : [key]};
    try {
      final r = await ref
          .read(quizRepositoryProvider)
          .submitPayload(q.id, payload, _stopwatch.elapsedMilliseconds);
      setState(() {
        _result = r;
        _score += r.score;
        _maxScore += r.maxScore;
        _xpEarned += r.xpAwarded;
        _coinsEarned += r.coinsAwarded;
        _submitting = false;
      });
      if (r.isCorrect) {
        ref.read(soundServiceProvider).correct();
      } else {
        ref.read(soundServiceProvider).wrong();
      }
      // Mukofot fikr-mulohaza blokidan yuqoriga uchib ketadi.
      //
      //
      if (r.xpAwarded > 0 || r.coinsAwarded > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final anchor = _rewardAnchor.currentContext;
          if (anchor != null && mounted) {
            RewardFly.show(anchor, xp: r.xpAwarded, coins: r.coinsAwarded);
          }
        });
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(humanError(e, l))));
        _startTimer(); // give the time back on a failed send
      }
    }
  }

  int _xpEarned = 0;
  int _coinsEarned = 0;

  final GlobalKey _rewardAnchor = GlobalKey();

  void _refreshProgress() {
    ref.invalidate(meOverviewProvider);
    ref.invalidate(analysisProvider);
    ref.invalidate(subjectsProvider);
    ref.invalidate(coinInfoProvider);
  }

  void _next() {
    if (!_signupPromptShown &&
        _index + 1 >= _promptAfter &&
        _index + 1 < _questions.length) {
      _signupPromptShown = true;
      GuestSignupPrompt.maybeShow(context, ref, answered: _index + 1);
    }

    if (_index + 1 >= _questions.length) {
      ref.read(soundServiceProvider).complete();
      _refreshProgress();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => ResultScreen(
                  score: _score,
                  total: _maxScore,
                  xpEarned: _xpEarned,
                  coinsEarned: _coinsEarned,
                )),
      );
      return;
    }
    setState(() {
      _index++;
      _selected = null;
    _typed.clear();
      _result = null;
      _timedOut = false;
    });
    _stopwatch
      ..reset()
      ..start();
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(l.loadingQuestions),
          ]),
        ),
      );
    }
    if (_error != null) {
      // `DioException [connection error]: http://api.topagon.uz/v1/questions`
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: l.errTitle,
          message: humanError(_error!, l),
          actionLabel: l.retry,
          onAction: () {
            setState(() {
              _error = null;
              _loading = true;
            });
            _load();
          },
        ),
      );
    }
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.search_off_rounded,
          title: l.noQuestions,
          message: l.noQuestionsHint,
          actionLabel: l.back,
          onAction: () => Navigator.pop(context),
        ),
      );
    }

    final q = _questions[_index];
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final progress = (_index + 1) / _questions.length;
    final answered = _result != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(l.questionOf(_index + 1, _questions.length)),
        actions: [
          if (widget.params.timed && !answered)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _remaining <= 5
                        ? _red.withValues(alpha: 0.15)
                        : palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timer_outlined,
                        size: 15,
                        color: _remaining <= 5 ? _red : palette.muted),
                    const SizedBox(width: 4),
                    Text('0:${_remaining.toString().padLeft(2, '0')}',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _remaining <= 5 ? _red : palette.muted)),
                  ]),
                ),
              ),
            ),
        ],
      ),
      body: ContentWidth(
        maxWidth: 760,
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: palette.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              children: [
                KeyedSubtree(
                  key: ValueKey('stem_${q.id}'),
                  child: MathText(q.stem,
                          style: Theme.of(context).textTheme.titleMedium)
                      .enterFade(),
                ),
                const SizedBox(height: 18),
                for (final (i, opt) in q.options.indexed)
                  KeyedSubtree(
                    key: ValueKey('${q.id}_${opt.optionKey}'),
                    child: _option(q, opt, scheme, palette).enterStaggered(i),
                  ),
                if (_isTypedType(q)) _typedField(l, scheme, palette),
                if (_timedOut) _timeUpBanner(l, palette),
                if (answered) _feedback(l, palette),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
              child: FilledButton(
                onPressed: (answered || _timedOut)
                    ? _next
                    : (_canSubmit && !_submitting
                        ? () => _grade(_selected)
                        : null),
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text((answered || _timedOut)
                        ? (_index + 1 >= _questions.length ? l.finish : l.next)
                        : l.submitAnswer),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  //
  // bosishga tushiradi.
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

  Widget _symbolButton(String label, String insert, AppPalette p) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: OutlinedButton(
          onPressed: () => _insertSymbol(insert),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(40, 36),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            side: BorderSide(color: p.hairline),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _typedField(L10n l, ColorScheme scheme, AppPalette p) {
    final answered = _result != null;
    final numericOnly = _questions[_index].type == 'numeric';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _typed,
          enabled: !answered && !_submitting && !_timedOut,
          keyboardType: TextInputType.text,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            // boshqa songa aylantirardi. Qolgan belgilar — pastdagi
            if (numericOnly)
              FilteringTextInputFormatter.allow(
                  RegExp(r'[0-9,.\-+/()π√^ ]')),
          ],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_canSubmit && !_submitting && !answered) _grade(_selected);
          },
          decoration: InputDecoration(
            labelText: l.typedAnswerLabel,
            hintText: l.typedAnswerHint,
            helperText: l.typedAnswerHelp,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            suffixIcon: answered
                ? Icon(
                    _result!.isCorrect ? Icons.check_circle : Icons.cancel,
                    color: _result!.isCorrect ? _green : _red,
                  )
                : null,
          ),
        ),
        if (!answered && numericOnly) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _symbolButton('a/b', '/', p),
              _symbolButton('√', '√', p),
              _symbolButton('π', 'π', p),
              _symbolButton('x²', '^', p),
              _symbolButton('( )', '()', p),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _option(Question q, QChoice opt, ColorScheme scheme, AppPalette p) {
    final isSelected = _selected == opt.optionKey;
    Color border = p.hairline;
    Color bg = scheme.surface;
    Color letterBg = p.surfaceAlt;
    Color letterFg = scheme.onSurface;
    Widget? trailing;

    if (_result == null) {
      if (isSelected) {
        border = scheme.primary;
        bg = scheme.primary.withValues(alpha: 0.10);
        letterBg = scheme.primary;
        letterFg = scheme.onPrimary;
      }
    } else {
      final isCorrectOption = _result!.correctOptionIds.contains(opt.optionKey);
      if (isCorrectOption) {
        border = _green;
        bg = _green.withValues(alpha: 0.12);
        letterBg = _green;
        letterFg = Colors.white;
        trailing = const Icon(Icons.check_circle, color: _green, size: 20);
      } else if (isSelected) {
        border = _red;
        bg = _red.withValues(alpha: 0.12);
        letterBg = _red;
        letterFg = Colors.white;
        trailing = const Icon(Icons.cancel, color: _red, size: 20);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        // Vaqt tugagach ham variantlar bosilmaydi: aks holda o'quvchi
        onTap: (_result != null || _timedOut)
            ? null
            : () {
                ref.read(soundServiceProvider).tap();
                setState(() => _selected = opt.optionKey);
              },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: border, width: border == p.hairline ? 1 : 2),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: letterBg, borderRadius: BorderRadius.circular(8)),
                child: Text(opt.optionKey.replaceAll('opt_', '').toUpperCase(),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: letterFg)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MathText(
                  opt.text,
                  // qo'yilmaydi.
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ),
      ),
    );
  }

  Widget _rewardLine(L10n l, AppPalette p) {
    final r = _result!;
    final scheme = Theme.of(context).colorScheme;

    if (r.xpAwarded > 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        // Chiplar `widgets/currency.dart` dan — dashboarddagi va uchib
        // yashil `Icons.bolt` va sariq tanga turardi, dashboardda esa
        child: Wrap(spacing: 6, runSpacing: 4, children: [
          RewardChip.xp(l.rewardXp(r.xpAwarded)),
          if (r.coinsAwarded > 0) RewardChip.coin(l.rewardCoins(r.coinsAwarded)),
        ]),
      );
    }

    final String? note = switch (r.rewardReason) {
      'guest' => l.rewardGuest,
      'repeat' => l.rewardRepeat,
      _ => null,
    };
    if (note == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(note,
          style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: r.rewardReason == 'guest' ? scheme.primary : p.muted)),
    );
  }

  Widget _timeUpBanner(L10n l, AppPalette p) {
    final color = p.warning;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OwlMascot(OwlMood.encouraging, size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.quizTimeUp,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(height: 4),
                Text(l.quizTimeUpHint,
                    style: TextStyle(fontSize: 13, height: 1.4, color: p.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedback(L10n l, AppPalette p) {
    final ok = _result!.isCorrect;
    final color = ok ? _green : _red;
    return Container(
      key: _rewardAnchor,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OwlMascot(ok ? OwlMood.excited : OwlMood.encouraging, size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ok ? l.correct : l.incorrect,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color)),
                _rewardLine(l, p),
                if (!ok) ...[
                  const SizedBox(height: 4),
                  Text(l.quizWrongHint,
                      style:
                          TextStyle(fontSize: 13, height: 1.4, color: p.muted)),
                ],
                if ((_result!.explanation ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_result!.explanation!,
                      style:
                          TextStyle(fontSize: 13, height: 1.4, color: p.muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}