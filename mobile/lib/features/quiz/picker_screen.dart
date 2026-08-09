import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/breakpoints.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/subject_palette.dart';
import '../subjects/subjects.dart';
import 'quiz_data.dart';
import 'quiz_screen.dart';

class PickerScreen extends ConsumerStatefulWidget {
  final Subject subject;
  const PickerScreen(this.subject, {super.key});

  @override
  ConsumerState<PickerScreen> createState() => _PickerScreenState();
}

class _PickerScreenState extends ConsumerState<PickerScreen> {
  int _step = 0; // 0 = grade, 1 = topics + count + timer

  bool _allLevels = false;
  int? _grade;

  bool _topicBased = false;
  String? _topicId;
  int _count = 10;
  /// Taymer STANDART YOQIQ (2026-08-08 ko'rigi).
  ///
  /// Ilgari `false` edi va amalda hech kim uni yoqmasdi — mashq imtihonga
  /// emas, cheksiz o'ylashga o'rgatardi. Vaqt tugasa savol NOTO'G'RI deb
  /// sanalmaydi (`quiz_screen.dart` dagi `_timedOut`), ya'ni standart
  /// yoqilgani foydalanuvchini jazolamaydi — xohlamasa bir bosishda
  /// o'chiradi.
  bool _timed = true;

  bool get _step0Done => _allLevels || _grade != null;

  /// Bo'lim qidiruvi. Geografiyada 179 ta bo'lim bor — scroll bilan izlash
  /// amalda ishlamaydi.
  final _topicQuery = TextEditingController();

  @override
  void dispose() {
    _topicQuery.dispose();
    super.dispose();
  }

  /// Qidiruv bo'sh bo'lsa hammasi. Solishtirish kichik harfda va apostrof
  /// shakllari birxillashtiriladi: foydalanuvchi «gʻarbiy» ni «g'arbiy» deb
  /// yozsa ham topilsin (klaviaturaga qarab uch xil apostrof chiqadi).
  List<TopicEntry> _filteredTopics(Catalog cat) {
    final q = _norm(_topicQuery.text);
    if (q.isEmpty) return cat.topics;
    return [for (final t in cat.topics) if (_norm(t.title).contains(q)) t];
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('ʻ', "'")
      .replaceAll('ʼ', "'")
      .trim();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final accent = SubjectPalette.of(widget.subject.code).color(Theme.of(context).brightness);
    // MUHIM: katalog TANLANGAN SINFGA bog'liq.
    //
    // 1-qadamda sinf hali tanlanmagan — to'liq katalog kerak (sinf ro'yxati
    // shundan chiqadi). 2-qadamda esa faqat shu sinfning bo'limlari
    // ko'rsatilishi kerak, aks holda foydalanuvchi 11-sinfni tanlab, 5-sinf
    // bo'limini tanlab qo'yadi va bo'sh mashqqa tushadi.
    final catalogAsync = ref.watch(catalogProvider((
      subjectId: widget.subject.id,
      grade: _step == 0 ? null : (_allLevels ? null : _grade),
    )));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              _step == 0 ? Navigator.pop(context) : setState(() => _step = 0),
        ),
        title: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration:
                BoxDecoration(color: accent, borderRadius: BorderRadius.circular(9)),
            child: Icon(SubjectPalette.of(widget.subject.code).icon,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(widget.subject.name, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      // Keng ekranda tanlov ro'yxati butun monitor bo'ylab yoyilmasin.
      body: ContentWidth(
        maxWidth: 760,
        child: catalogAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (cat) => Column(
            children: [
              _stepDots(),
              Expanded(
                child: _step == 0 ? _stepGrade(l, cat) : _stepTopics(l, cat),
              ),
              _bottomBar(l, cat),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepDots() {
    final primary = Theme.of(context).colorScheme.primary;
    final p = Theme.of(context).extension<AppPalette>()!;
    Widget dot(bool on) => Container(
          width: on ? 22 : 9,
          height: 9,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
              color: on ? primary : p.hairline,
              borderRadius: BorderRadius.circular(5)),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        dot(true),
        dot(_step == 1),
      ]),
    );
  }

  // ---------------- Step 1: grade ----------------
  Widget _stepGrade(L10n l, Catalog cat) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      children: [
        Text(l.pickGradeTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        _bigChoice(
          icon: Icons.public,
          title: l.allLevels,
          subtitle: l.allLevelsSub,
          selected: _allLevels,
          onTap: () => setState(() {
            _allLevels = true;
            _grade = null;
            _topicId = null;
          }),
        ),
        const SizedBox(height: 12),
        Text(l.grade,
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).extension<AppPalette>()!.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in cat.grades)
              _chip('${g.grade}-${l.gradeSuffix}', !_allLevels && _grade == g.grade,
                  () => setState(() {
                        _grade = g.grade;
                        _allLevels = false;
                        // Sinf o'zgardi — eski bo'lim endi bu sinfga
                        // tegishli bo'lmasligi mumkin.
                        _topicId = null;
                      })),
          ],
        ),
      ],
    );
  }

  // ---------------- Step 2: topics + count + timer ----------------
  Widget _stepTopics(L10n l, Catalog cat) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      children: [
        Text(l.includeTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        _bigChoice(
          icon: Icons.library_books_outlined,
          title: l.allTopics,
          subtitle: l.allTopicsSub,
          selected: !_topicBased,
          onTap: () => setState(() {
            _topicBased = false;
            _topicId = null;
          }),
        ),
        // Bu sinfda bo'lim ajratilmagan bo'lsa, variantni umuman
        // ko'rsatmaymiz. Bo'sh ro'yxatli tanlov — foydalanuvchi uchun
        // boshi berk ko'cha.
        if (cat.topics.isNotEmpty) ...[
          const SizedBox(height: 12),
          _bigChoice(
            icon: Icons.checklist_rtl,
            title: l.topicBased,
            subtitle: l.topicBasedSub,
            selected: _topicBased,
            onTap: () => setState(() => _topicBased = true),
          ),
          if (_topicBased) ...[
            const SizedBox(height: 10),
            // Qidiruv 12 tadan ko'p bo'lim bo'lgandagina chiqadi. Geografiyada
            // 179 ta bo'lim bor — u yerda scroll bilan izlash amalda
            // ishlamaydi; 5 ta bo'limda esa qidiruv qutisi ortiqcha shovqin.
            if (cat.topics.length > 12) ...[
              TextField(
                controller: _topicQuery,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.topicSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _topicQuery.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(_topicQuery.clear),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
            ],
            for (final t in _filteredTopics(cat))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _topicRow(t.title, _topicId == t.id,
                    () => setState(() => _topicId = t.id)),
              ),
            if (_filteredTopics(cat).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(l.topicSearchEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ],
        const SizedBox(height: 18),
        Text(l.questionCount,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _counter(),
        const SizedBox(height: 18),
        Text(l.timerQuestion,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _toggle(Icons.timer_outlined, l.yes, _timed,
                  () => setState(() => _timed = true))),
          const SizedBox(width: 10),
          Expanded(
              child: _toggle(Icons.block, l.no, !_timed,
                  () => setState(() => _timed = false))),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------------- shared widgets ----------------
  Widget _bottomBar(L10n l, Catalog cat) {
    // Bo'lim tanlash majburiy emas. Lekin "bo'lim bo'yicha" tanlangan-u,
    // bo'lim tanlanmagan bo'lsa — tugma o'chadi. Bu sinfda umuman bo'lim
    // bo'lmasa (`cat.topics` bo'sh) shart tushib qoladi.
    final ok = _step == 0
        ? _step0Done
        : (!_topicBased || cat.topics.isEmpty || _topicId != null);

    // O'chiq tugma NEGA o'chiq ekanini aytishi shart. Ilgari foydalanuvchi
    // shart bajarilmaganini ham, buzuqlikni ham ajrata olmasdi — ikkalasi
    // ham "kulrang tugma" bo'lib ko'rinardi.
    final String? blocker = ok
        ? null
        : (_step == 0 ? l.pickerNeedGrade : l.pickerNeedTopic);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (blocker != null) ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.info_outline_rounded,
                  size: 15,
                  color: Theme.of(context).extension<AppPalette>()!.muted),
              const SizedBox(width: 6),
              Text(blocker, style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 8),
          ],
          // `SizedBox` kerak: ilgari tugma `Padding` ning bevosita bolasi
          // bo'lgani uchun butun kenglikni egallardi. `Column` ichida esa u
          // o'z matni bo'yicha qisqarib qolardi.
          SizedBox(
            width: double.infinity,
            child: FilledButton(
          onPressed: !ok
              ? null
              : () {
                  if (_step == 0) {
                    setState(() => _step = 1);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuizScreen(QuizParams(
                          subjectId: widget.subject.id,
                          subjectCode: widget.subject.code,
                          grade: _allLevels ? null : _grade,
                          topicId: _topicBased ? _topicId : null,
                          count: _count,
                          timed: _timed,
                        )),
                      ),
                    );
                  }
                },
              child: Text(_step == 0 ? l.next : l.startNow),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _bigChoice({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final p = Theme.of(context).extension<AppPalette>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.10)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? primary : p.hairline, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? primary : p.muted, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? primary : p.faint, size: 22),
        ]),
      ),
    );
  }

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    final primary = Theme.of(context).colorScheme.primary;
    final p = Theme.of(context).extension<AppPalette>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? primary : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? primary : p.hairline),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : p.muted)),
      ),
    );
  }

  Widget _topicRow(String text, bool selected, VoidCallback onTap) {
    final primary = Theme.of(context).colorScheme.primary;
    final p = Theme.of(context).extension<AppPalette>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.10)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? primary : p.hairline),
        ),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400))),
          // Savol soni ATAYLAB ko'rsatilmaydi. Sabab: "9" turgan bo'lim
          // o'quvchiga "arzimas" bo'lib tuyuladi va u eng katta raqamli
          // bo'limni tanlaydi — ya'ni raqam mazmun o'rniga tanlov mezoniga
          // aylanadi. Bo'sh bo'limlar ro'yxatga umuman tushmaydi, shuning
          // uchun raqam foydalanuvchiga hech qanday qaror bermaydi.
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(Icons.check, size: 18, color: primary),
          ],
        ]),
      ),
    );
  }

  Widget _counter() {
    final p = Theme.of(context).extension<AppPalette>()!;
    Widget btn(IconData i, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.hairline)),
            child: Icon(i, size: 20),
          ),
        );
    return Row(children: [
      btn(Icons.remove,
          () => setState(() => _count = (_count - 5).clamp(5, 50))),
      Expanded(
        child: Center(
          child: Text('$_count',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
      ),
      btn(Icons.add, () => setState(() => _count = (_count + 5).clamp(5, 50))),
    ]);
  }

  Widget _toggle(IconData icon, String label, bool selected, VoidCallback onTap) {
    final primary = Theme.of(context).colorScheme.primary;
    final p = Theme.of(context).extension<AppPalette>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.10)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? primary : p.hairline, width: selected ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: selected ? primary : p.muted),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}
