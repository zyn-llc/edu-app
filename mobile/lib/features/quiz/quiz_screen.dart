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
/// Bitta savolga beriladigan vaqt (soniya).
///
/// 30 — variantli savol uchun: o'qish + tanlash. Yozma javobda (`numeric`,
/// `open_keyword`) esa foydalanuvchi klaviaturada teradi, matematikada
/// bundan tashqari qo'lda hisoblaydi ham — shuning uchun ikki barobar vaqt.
/// Bitta raqamdan foydalanilganda matematik savollarda taymer doim yetmasdi.
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
  /// instead of option cards; the server normalizes ("0,5", "1/3") and grades.
  bool _isTypedType(Question q) =>
      q.type == 'numeric' || q.type == 'open_keyword';

  bool get _canSubmit {
    final q = _questions[_index];
    return _isTypedType(q) ? _typed.text.trim().isNotEmpty : _selected != null;
  }
  /// Mehmonga ro'yxatdan o'tish taklifi shu sessiyada ko'rsatildimi.
  /// Bir marta — takroriy oyna faqat asabga tegadi va konversiyani tushiradi.
  bool _signupPromptShown = false;

  /// Nechanchi savoldan keyin taklif chiqadi. 5 — o'quvchi ilova qandayligini
  /// tushunib ulgurgan, lekin hali zerikmagan nuqta.
  static const _promptAfter = 5;

  GradeResult? _result;
  int _score = 0;
  int _maxScore = 0;
  final _stopwatch = Stopwatch();

  Timer? _ticker;
  int _remaining = _perQuestionSeconds;

  /// Shu savolda vaqt tugadi.
  ///
  /// NEGA ALOHIDA HOLAT (2026-08-08 ko'rigi). Ilgari vaqt tugaganda
  /// `_grade(_selected)` chaqirilardi: tanlanmagan javob serverga ketardi
  /// va o'quvchi «Noto'g'ri» degan qizil javobni ko'rardi. Bu ikki jihatdan
  /// yomon:
  ///
  ///  1. **Yolg'on.** O'quvchi noto'g'ri javob bermadi — u umuman javob
  ///     bermadi. Ikkalasi bir xil ko'rsatilishi adolatsiz.
  ///  2. **Statistikani buzadi.** Bo'sh javob `submissions` ga tushib,
  ///     aniqlik foizini pasaytirardi va «kuchsiz mavzular» tahlilini
  ///     noto'g'ri hisoblardi.
  ///
  /// Endi vaqt tugasa savol serverga UMUMAN yuborilmaydi: ekranda «Vaqt
  /// tugadi» chiqadi va keyingi savolga o'tiladi. Savol yechilmagan bo'lib
  /// qoladi, ya'ni keyinroq yana uchrashi mumkin — bu to'g'ri.
  bool _timedOut = false;

  /// `dispose()` da `ref` dan foydalanib bo'lmaydi (u shu payt allaqachon
  /// yopilgan bo'lishi mumkin), shuning uchun konteynerni oldindan olamiz.
  /// Bu mashqni yarmida tashlab chiqqan foydalanuvchi uchun kerak: u ham
  /// XP olgan bo'lishi mumkin.
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
      // Kadr ichida (vidjet daraxti demontaj qilinayotganda) provider'ni
      // o'zgartirish "modified a provider while the widget tree was building"
      // xatosini beradi. Shuning uchun keyingi kadrga suramiz — konteyner
      // ilova darajasida, u yopilmaydi.
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
        // Serverga YUBORILMAYDI — sabab `_timedOut` izohida.
        setState(() => _timedOut = true);
      }
    });
  }

  Future<void> _grade(String? key) async {
    if (_result != null || _submitting) return;
    // `await` dan OLDIN olinadi: keyin `context` yaroqsiz bo'lishi mumkin.
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
      // NEGA POST-FRAME: `_feedback` bloki AYNAN shu `setState` da paydo
      // bo'ladi, ya'ni hozir uning `RenderBox` i hali yo'q va boshlanish
      // nuqtasini hisoblab bo'lmaydi. Keyingi kadrda esa u joyida turadi.
      //
      // NEGA `_rewardAnchor`: `context` (butun ekran) ishlatilsa mukofot
      // ekranning yuqori chetidan uchardi — o'quvchi unga qaramaydi, chunki
      // ko'zi javob bergan joyda. Harakat AYNAN shu yerdan boshlanishi
      // kerak, aks holda "nima uchun berildi" bog'lanishi yo'qoladi.
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
        // Sabab bo'yicha aniq matn: tarmoq uzilishi, 429 va server xatosi —
        // uchtasi uchun uchta boshqacha harakat kerak. Ilgari uchalasi ham
        // "qayta urinib ko'ring" derdi, holbuki 429 da qayta urinish aynan
        // noto'g'ri harakat.
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(humanError(e, l))));
        _startTimer(); // give the time back on a failed send
      }
    }
  }

  /// Mashq davomida to'plangan XP/noncoin. Faqat ko'rsatish uchun — haqiqiy
  /// hisob serverda.
  int _xpEarned = 0;
  int _coinsEarned = 0;

  /// Mukofot animatsiyasi shu nuqtadan uchadi (fikr-mulohaza bloki).
  final GlobalKey _rewardAnchor = GlobalKey();

  /// Dashboard, tahlil, fan kartochkalari va tanga balansi shu mashqdan
  /// keyin eskirgan bo'ladi. Ilgari ular faqat "tortib yangilash" bilan
  /// yangilanardi va foydalanuvchi "XP o'smadi" deb o'ylardi — aslida
  /// ekrandagi raqam eski edi.
  void _refreshProgress() {
    ref.invalidate(meOverviewProvider);
    ref.invalidate(analysisProvider);
    ref.invalidate(subjectsProvider);
    ref.invalidate(coinInfoProvider);
  }

  void _next() {
    // Mehmon bir necha savol yechgach — ro'yxatdan o'tishga taklif.
    // MASHQ TUGAGANDA ko'rsatilmaydi: u yerda `ResultScreen` dagi
    // `GuestNotice` ayni shu vazifani bajaradi, ikkitasi ketma-ket chiqsa
    // bosim bo'lib tuyuladi.
    if (!_signupPromptShown &&
        _index + 1 >= _promptAfter &&
        _index + 1 < _questions.length) {
      _signupPromptShown = true; // qayta chaqirilmasin (natijasidan qat'i nazar)
      GuestSignupPrompt.maybeShow(context, ref, answered: _index + 1);
    }

    if (_index + 1 >= _questions.length) {
      // Mashq tugadi — kichik fanfar. Natija ekrani ochilishidan oldin
      // chaqiriladi, shunda ovoz va maskot bir vaqtda ko'rinadi.
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
      // Ilgari bu yerda `Text('$_error')` turardi va o'quvchi ekranda
      // `DioException [connection error]: http://api.topagon.uz/v1/questions`
      // ni ko'rardi — bu ilova buzuq degan yagona xulosaga olib boradi.
      // `humanError` xatoni sababiga qarab tarjima qiladi, `EmptyState` esa
      // chiqish yo'lini beradi.
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
      // Bo'sh ekran + bitta qator matn "ilova buzuq" degan taassurot
      // qoldiradi. Endi sabab ham, chiqish yo'li ham ko'rsatiladi.
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
      // Keng ekranda savol matni butun monitor bo'ylab cho'zilmasin: bir
      // qatorda 60–75 belgidan ko'p bo'lsa ko'z qatordan qatorga o'ta olmaydi.
      // Telefonda `ContentWidth` hech narsa qilmaydi (maxWidth ekrandan katta).
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
                // Tema shkalasidan: savol matni — `titleMedium`. Ilgari bu
                // yerda qattiq `fontSize: 17` turardi va sahifadagi boshqa
                // matnlardan farq qilmasdi.
                // Kalit `Animate` ning O'ZIDA bo'lishi kerak (shuning uchun
                // `KeyedSubtree`), aks holda savol almashganda Flutter eski
                // animatsiya holatini qayta ishlatadi va matn "ochilmaydi".
                KeyedSubtree(
                  key: ValueKey('stem_${q.id}'),
                  child: MathText(q.stem,
                          style: Theme.of(context).textTheme.titleMedium)
                      .enterFade(),
                ),
                const SizedBox(height: 18),
                // `ValueKey` savol ID sidan: kalit o'zgarganda `Animate`
                // yangi holat oladi va variantlar KEYINGI savolda ham
                // qaytadan ochiladi. Kalitsiz animatsiya faqat birinchi
                // savolda ishlardi.
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

  // Kursor turgan joyga belgi qo'yadi (bor tanlovni almashtiradi).
  //
  // NEGA KERAK. `/` klaviaturada allaqachon terilishi mumkin edi (formatter
  // ruxsat beradi), lekin telefonning standart klaviaturasida u SIMVOLLAR
  // sahifasining orqasida yashiringan — o'quvchi uni qidirib topmaydi va
  // "kasrni qanday yozish kerak?" degan xabar yuboradi. Tugma buni bir
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
    // FAQAT `numeric` savolda kiritish cheklanadi.
    //
    // XATO (2026-08-08 sinovida topilgan): "matematika ochiq savolida harf
    // yozib bo'lmadi". Filtr HAR QANDAY yozma savolga qo'llanardi, holbuki
    // `open_keyword` javobi — matn: «Toshkent», «uchburchak», «x=3, y=8».
    // Foydalanuvchi harf bosardi, ekranda hech narsa chiqmasdi va bu
    // klaviatura buzuq degan taassurot berardi.
    //
    // `numeric` da esa filtr o'z o'rnida: u yerda javob son bo'lishi shart
    // va tasodifiy harf serverda «noto'g'ri» ga aylanardi.
    final numericOnly = _questions[_index].type == 'numeric';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _typed,
          enabled: !answered && !_submitting && !_timedOut,
          // `numberWithOptions` EMAS: u telefonda faqat raqamli panelni ochadi
          // va u yerda `/` tugmasi YO'Q. Server esa kasr javobni ("1/3")
          // to'liq tushunadi — ya'ni javob qabul qilinardi-yu, uni yozib
          // bo'lmasdi. Endi to'liq klaviatura, lekin faqat matematik belgilar
          // kiritishga ruxsat beriladi.
          keyboardType: TextInputType.text,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            // HARF YO'Q. Ilgari ro'yxatda `e` va `r` turardi va sonli
            // javobga harf yozib bo'lardi. `e` ayniqsa zararli edi:
            // serverdagi `float()` "1e3" ni JIM QABUL QILADI va uni 1000
            // deb o'qiydi, ya'ni tasodifan bosilgan harf javobni butunlay
            // boshqa songa aylantirardi. Qolgan belgilar — pastdagi
            // tugmalar qatori chiqaradigan belgilar.
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
        // Matematik belgilar qatori faqat sonli savolda: matnli javobda
        // («Toshkent») √ va π tugmalari faqat chalkashtiradi.
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
    // `muted` EMAS. Kulrang harf + kulrang matn variantni "faol emas" qilib
    // ko'rsatardi — bu ilovadagi eng ko'p ko'riladigan ekran, u yerda
    // "bosiladigan" degan signal eng aniq bo'lishi kerak.
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
        // javobni tanlab, «Keyingi» bosardi va tanlovi hech qayerga
        // ketmagani uchun buni ilova xatosi deb o'ylardi.
        onTap: (_result != null || _timedOut)
            ? null
            // Variant tanlanganda qisqa klik. Javob yuborilgandan keyin
            // (_result != null) tugma o'chadi, ya'ni ovoz ham chiqmaydi.
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
                  // Rang va vazn ATAYLAB aniq berilgan: variant matni asosiy
                  // kontent, temaning standart matn uslubiga tashlab
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

  /// «+10 XP · +2 tanga» yoki nega mukofot berilmagani.
  ///
  /// Bu qator #1 muammoning javobi: XP tizimi to'g'ri ishlardi, lekin
  /// foydalanuvchi mehmon rejimida yoki AYNI savolni ikkinchi marta
  /// yechayotganini bilmasdi — server ikkala holatda ham XP bermaydi.
  Widget _rewardLine(L10n l, AppPalette p) {
    final r = _result!;
    final scheme = Theme.of(context).colorScheme;

    if (r.xpAwarded > 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        // Chiplar `widgets/currency.dart` dan — dashboarddagi va uchib
        // ketgan mukofotdagi belgilar bilan AYNAN bir xil. Ilgari bu yerda
        // yashil `Icons.bolt` va sariq tanga turardi, dashboardda esa
        // boshqacha — foydalanuvchi ularni bir narsa deb tanimasdi.
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

  /// «Vaqt tugadi» — javob KELMAGAN holat.
  ///
  /// Rangi ataylab NEYTRAL (kulrang/sariq), qizil emas: qizil butun ilovada
  /// «noto'g'ri javob» degan ma'noni bildiradi va shu holat aynan undan
  /// farq qilishi kerak. Maskot ham `encouraging` — bu muvaffaqiyatsizlik
  /// emas, shunchaki tugagan vaqt.
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
                // Noto'g'ri javobda server kalitni ham, izohni ham bermaydi
                // (aks holda "xato qil → javobni o'qi → qayta yubor" farmi
                // ochilardi). Sababsiz bo'sh joy "ilova javobni ko'rsatmay
                // qo'ydi" degan taassurot qoldiradi — shuning uchun nima
                // bo'lgani aytiladi.
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