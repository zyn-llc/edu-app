import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/motion.dart';
import '../../theme/spacing.dart';
import '../../theme/subject_palette.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/hover_card.dart';
import '../auth/login_sheet.dart';
import '../subjects/subjects.dart';
import 'notes_data.dart';

/// O'quvchining daftari.
///
/// ## Nima o'zgardi (2026-08-07)
///
/// Ilgari bu CRUD ro'yxati edi: bir xil oq to'rtburchaklar, sarlavha va uch
/// qator matn. Yozuvlar 20 tadan oshganda ular bir-biridan farq qilmasdi va
/// kerakligini topib bo'lmasdi.
///
/// Endi u DAFTAR:
///
/// | Element             | Nima uchun                                       |
/// |---------------------|--------------------------------------------------|
/// | Fan rangli chizig'i | Yozuvni o'qimasdan qaysi fandanligi bilinadi     |
/// | Qidiruv             | 20+ yozuvda yagona ishlaydigan navigatsiya        |
/// | Statistika qatori   | «24 yozuv · 8 fan» — mehnat ko'rinadi             |
/// | Boy bo'sh holat     | Nega kerakligini TUSHUNTIRADI, shunchaki bo'sh emas |
/// | Tezkor yozuv        | Sarlavha majburiy emas — birinchi qator o'zi sarlavha |
/// | Saqlash tasdig'i    | Tugma «✓ Saqlandi» ga aylanadi, keyin yopiladi    |
///
/// Yozuvlar hisobga bog'langan, shuning uchun ekran kirishni talab qiladi.
/// Mehmonga bo'sh ro'yxat emas, sabab ko'rsatiladi — bo'sh ro'yxat buzuq
/// ilova taassurotini beradi.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  /// Daftarni ochish.
  ///
  /// Keng ekranda (≥900 px) — MARKAZLASHGAN MODAL, tor ekranda — odatdagi
  /// to'liq sahifa.
  ///
  /// Nega ikki xil: web'da butun sahifani almashtirish kontekstni yo'qotadi —
  /// foydalanuvchi dashboarddan uzoqlashgandek his qiladi va "orqaga"
  /// tugmasini qidiradi. Modal esa dashboard ustida ochiladi, ortida u
  /// ko'rinib turadi va Esc yoki tashqariga bosish bilan yopiladi. Telefonda
  /// esa modal aksincha yomon: ekran kichik, modal deyarli butun ekranni
  /// egallaydi va shunchaki sahifaning yomon ko'rinishiga aylanadi.
  static Future<void> open(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (!wide) {
      return Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotesScreen()),
      );
    }
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(
            horizontal: Spacing.xl, vertical: Spacing.xxl),
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardRadius),
        // DIQQAT: `ConstrainedBox` da `const` ATAYLAB yo'q, ichkaridagi
        // `NotesScreen()` da esa OSHKORA `const` bor.
        //
        // Sabab: `const ConstrainedBox(...)` bo'lsa, ichkaridagi hamma narsa
        // ham const kontekstga tushadi va sinf O'ZINING static metodi ichida
        // o'zini const qilib qurmoqchi bo'ladi — analizator buni
        // `const_with_non_const` deb rad etadi.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: const NotesScreen(),
        ),
      ),
    );
  }

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Qidiruv maydoni shundan ko'p yozuv bo'lgandagina chiqadi.
  ///
  /// 6 tagacha yozuv bitta ekranga sig'adi — qidiruv u yerda faqat joy
  /// egallaydi va "bu yerda ko'p narsa bor" degan yolg'on taassurot beradi.
  static const _searchThreshold = 6;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Apostrof shakllarini birxillashtiradi va registrni tushiradi.
  ///
  /// Nega: o'zbek matnida `oʻ`, `o'`, `o'`, `o‘` — to'rt xil belgi, lekin
  /// foydalanuvchi uchun bitta harf. Normallashtirilmasa «bogʻlanish» so'zi
  /// «bog'lanish» so'rovi bilan TOPILMAYDI va qidiruv buzuq deb qabul
  /// qilinadi. Bu `picker_screen` dagi bo'lim qidiruvi bilan bir xil qoida.
  static String _norm(String s) {
    var out = s.toLowerCase();
    for (final ch in const ['ʻ', 'ʼ', '‘', '’']) {
      out = out.replaceAll(ch, "'");
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final auth = ref.watch(authControllerProvider);
    final loggedIn = auth.user != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(l.notesTitle),
      ),
      floatingActionButton: loggedIn
          ? GlowFab(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add),
              label: Text(l.notesNew),
            )
          : null,
      body: !loggedIn
          ? EmptyState(
              icon: Icons.lock_outline,
              title: l.notesLoginRequired,
              message: l.notesLoginRequiredHint,
              actionLabel: l.authLoginTitle,
              onAction: () =>
                  LoginSheet.show(context, reason: l.notesLoginRequiredHint),
            )
          : ref.watch(notesProvider).when(
                loading: () => const _NotesSkeleton(),
                error: (e, _) => EmptyState(
                  icon: Icons.cloud_off,
                  title: l.errServer,
                  message: humanError(e, l),
                  actionLabel: l.retry,
                  onAction: () => ref.invalidate(notesProvider),
                ),
                data: (notes) => _body(l, notes),
              ),
    );
  }

  Widget _body(L10n l, List<Note> notes) {
    if (notes.isEmpty) return _EmptyNotebook(onCreate: () => _openEditor(context));

    // Fan ID → Fan. `subjectsProvider` allaqachon dashboardda yuklangan,
    // shuning uchun bu yerda odatda tarmoqqa chiqilmaydi (Riverpod keshi).
    // Yuklanmagan bo'lsa xarita bo'sh bo'ladi va kartalar neytral rangda
    // chiqadi — bu yumshoq degradatsiya, xato emas.
    final subjects = <String, Subject>{
      for (final s in ref.watch(subjectsProvider).valueOrNull ?? const <Subject>[])
        s.id: s,
    };

    final q = _norm(_query.trim());
    final visible = q.isEmpty
        ? notes
        : [
            for (final n in notes)
              if (_norm('${n.title ?? ''} ${n.body}').contains(q)) n
          ];

    return Column(
      children: [
        _StatsRow(notes: notes, subjects: subjects),
        if (notes.length > _searchThreshold)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, 0, Spacing.md, Spacing.sm),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: l.notesSearchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(
                    borderRadius: Radii.buttonRadius),
              ),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? EmptyState(
                  compact: true,
                  icon: Icons.search_off_rounded,
                  title: l.notesSearchEmpty,
                  message: l.notesSearchHint,
                )
              : RefreshIndicator(
                  onRefresh: () async => ref.refresh(notesProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.md, Spacing.xs, Spacing.md, 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Gap.ms(),
                    itemBuilder: (_, i) {
                      final n = visible[i];
                      return Dismissible(
                        key: ValueKey(n.id),
                        direction: DismissDirection.endToStart,
                        background: const _DeleteBackground(),
                        confirmDismiss: (_) => _confirmDelete(context, l),
                        onDismissed: (_) async {
                          await ref.read(notesRepositoryProvider).delete(n.id);
                          ref.invalidate(notesProvider);
                        },
                        child: _NoteCard(
                          note: n,
                          subject: n.subjectId == null
                              ? null
                              : subjects[n.subjectId],
                          onTap: () => _openEditor(context, note: n),
                        ).enterStaggered(i),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<bool> _confirmDelete(BuildContext context, L10n l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.notesDeleteTitle),
        content: Text(l.notesDeleteBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(l.delete)),
        ],
      ),
    );
    return ok ?? false;
  }

  void _openEditor(BuildContext context, {Note? note}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NoteEditorSheet(note: note),
    );
  }
}

/// «12 yozuv · 5 fan · 3 mashqdan».
///
/// Nega kerak: raqamlar mehnatni ko'rsatadi. Bo'sh ro'yxatdan to'la ro'yxatga
/// o'tish sezilmaydi, «1 yozuv» dan «24 yozuv» ga o'tish esa seziladi — bu
/// daftarni davom ettirishga undaydigan yagona narsa.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.notes, required this.subjects});

  final List<Note> notes;
  final Map<String, Subject> subjects;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    final subjectIds = <String>{
      for (final n in notes)
        if (n.subjectId != null) n.subjectId!
    };
    final fromQuiz = notes.where((n) => n.questionId != null).length;

    final parts = <String>[
      l.notesStatNotes(notes.length),
      if (subjectIds.isNotEmpty) l.notesStatSubjects(subjectIds.length),
      if (fromQuiz > 0) l.notesStatFromQuiz(fromQuiz),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
      child: Row(
        children: [
          Icon(Icons.auto_stories_outlined, size: 16, color: palette.faint),
          const Gap.sm(),
          Expanded(
            child: Text(
              // ` · ` — vergul emas: ro'yxat emas, yonma-yon turgan
              // mustaqil faktlar. Vergul ular bitta jumla deb o'qishga
              // majburlaydi.
              parts.join('  ·  '),
              style: text.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Surib o'chirish fonidagi qizil maydon.
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: Spacing.lg),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.12),
        borderRadius: Radii.cardRadius,
      ),
      child: Icon(Icons.delete_outline, color: scheme.error),
    );
  }
}

/// Bo'sh daftar.
///
/// Nega uzun: bu ekranni birinchi ko'rgan o'quvchi daftar NIMA UCHUN
/// kerakligini bilmaydi. «Yozuv yo'q» degan matn unga hech narsa bermaydi
/// va u qaytib kelmaydi. Uchta qator esa aniq foydani aytadi.
class _EmptyNotebook extends StatelessWidget {
  const _EmptyNotebook({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final palette = theme.extension<AppPalette>()!;

    Widget bullet(IconData icon, String label) => Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Row(children: [
            Icon(icon, size: 18, color: scheme.primary),
            const Gap.ms(),
            Expanded(child: Text(label, style: text.bodySmall)),
          ]),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.primaryTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.auto_stories_rounded,
                      size: 40, color: scheme.primary),
                ),
              ),
              const Gap.lg(),
              Text(l.notesEmptyTitle,
                  style: text.headlineSmall, textAlign: TextAlign.center),
              const Gap.sm(),
              Text(l.notesEmptyHint,
                  style: text.bodyMedium, textAlign: TextAlign.center),
              const Gap.lg(),
              Divider(color: palette.hairline, height: 1),
              const Gap.lg(),
              bullet(Icons.edit_note_rounded, l.notesFeature1),
              bullet(Icons.label_outline_rounded, l.notesFeature2),
              bullet(Icons.search_rounded, l.notesFeature3),
              const Gap.md(),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: Text(l.notesEmptyCta),
              ),
            ],
          ),
        ),
      ),
    ).enterFade();
  }
}

/// Bitta yozuv kartochkasi.
///
/// Chapdagi 4 px rangli chiziq — fan identifikatori. Nega chiziq, butun
/// kartani bo'yash emas: 20 ta rangli karta ro'yxatni bezakka aylantiradi va
/// matn o'qilmay qoladi. Ingichka chiziq esa periferik ko'rish bilan
/// o'qiladi — foydalanuvchi «yashillar biologiya» ekanini bir kunda
/// o'rganadi.
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.subject, required this.onTap});

  final Note note;
  final Subject? subject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final palette = theme.extension<AppPalette>()!;

    final accent = subject == null
        ? palette.faint
        : SubjectPalette.of(subject!.code).color(theme.brightness);

    final d = note.updatedAt;
    final stamp = '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}';

    final title = (note.title?.trim().isNotEmpty ?? false)
        ? note.title!.trim()
        : _firstLine(note.body) ?? l.notesUntitled;

    return HoverCard(
      onTap: onTap,
      accent: accent,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Fan chizig'i kartaning BUTUN balandligi bo'ylab. `IntrinsicHeight`
            // shuning uchun kerak: `Row` bolalari o'z-o'zidan cho'zilmaydi.
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(Radii.lg)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.ms, Spacing.ms, Spacing.ms, Spacing.ms),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium,
                          ),
                        ),
                        const Gap.sm(),
                        Text(stamp,
                            style: text.labelSmall
                                ?.copyWith(color: palette.faint)),
                      ],
                    ),
                    const Gap.xs(),
                    Text(
                      note.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                    if (subject != null || note.questionId != null) ...[
                      const Gap.sm(),
                      Row(children: [
                        if (subject != null)
                          _MetaChip(
                            label: subject!.name,
                            color: accent,
                            dot: true,
                          ),
                        if (subject != null && note.questionId != null)
                          const Gap.sm(),
                        if (note.questionId != null)
                          _MetaChip(
                            label: l.notesFromQuiz,
                            color: scheme.primary,
                            icon: Icons.quiz_outlined,
                          ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sarlavhasiz yozuvda birinchi qator sarlavha bo'lib xizmat qiladi.
  /// Bo'sh qatorlar tashlab yuboriladi va 60 belgidan uzun qator kesiladi —
  /// aks holda butun abzats sarlavha bo'lib chiqardi.
  static String? _firstLine(String body) {
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      return line.length <= 60 ? line : '${line.substring(0, 60)}…';
    }
    return null;
  }
}

/// Kartochka ostidagi kichik yorliq: fan nomi yoki «Mashqdan».
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.color,
    this.icon,
    this.dot = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Ikonka o'rniga kichik rangli nuqta — fan uchun. Fanning o'z ikonkasi
  /// bor, lekin u chipda 12 px da tanib bo'lmas darajada kichik chiqadi.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: Radii.pillRadius,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot)
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        if (icon != null) Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: text.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Yozuv yaratish/tahrirlash varag'i.
///
/// Natijaviy ekrandan ham chaqiriladi — u yerda [questionId]/[subjectId]
/// yozuvni o'quvchi hozir yechgan savolga bog'laydi.
class NoteEditorSheet extends ConsumerStatefulWidget {
  final Note? note;
  final String? questionId;
  final String? subjectId;
  const NoteEditorSheet(
      {super.key, this.note, this.questionId, this.subjectId});

  @override
  ConsumerState<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends ConsumerState<NoteEditorSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.note?.body ?? '');
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Sarlavha MAJBURIY EMAS.
  ///
  /// Nega: daftarga yozish tez bo'lishi kerak. Ikkita majburiy maydon —
  /// ikki barobar ko'p ish, va sinovchilar aynan shu sababli yozuv
  /// qoldirmasdi. Sarlavha bo'sh bo'lsa matnning birinchi qatori ishlatiladi
  /// (kartada ham xuddi shu qoida — `_NoteCard._firstLine`), ya'ni natija
  /// bir xil ko'rinadi.
  String get _effectiveTitle {
    final t = _title.text.trim();
    if (t.isNotEmpty) return t;
    for (final raw in _body.text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      return line.length <= 60 ? line : line.substring(0, 60);
    }
    return '';
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(notesRepositoryProvider);
      if (widget.note == null) {
        await repo.create(
          body: body,
          title: _effectiveTitle,
          questionId: widget.questionId,
          subjectId: widget.subjectId,
        );
      } else {
        await repo.update(widget.note!.id,
            body: body, title: _effectiveTitle);
      }
      ref.invalidate(notesProvider);
      if (widget.questionId != null) {
        ref.invalidate(questionNotesProvider(widget.questionId!));
      }
      if (!mounted) return;
      // Tugma «✓ Saqlandi» ga aylanadi va SHUNDAN KEYIN varaq yopiladi.
      //
      // Nega 550 ms kutamiz: varaq darhol yopilsa foydalanuvchi saqlanganini
      // KO'RMAYDI — u faqat ekran yo'qolganini ko'radi va «saqlandimi?»
      // degan savol qoladi. Yarim soniya — tasdiqni o'qishga yetadi, lekin
      // kutish sifatida sezilmaydi.
      setState(() {
        _saving = false;
        _saved = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = humanError(e, L10n.of(context));
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final palette = theme.extension<AppPalette>()!;
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          Spacing.md, Spacing.ms, Spacing.md, insets + Spacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Varaq "tutqichi" — bu modal ekan va uni pastga surib yopish
          // mumkinligini bildiradi.
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.hairline,
                borderRadius: Radii.pillRadius,
              ),
            ),
          ),
          const Gap.ms(),
          Row(children: [
            Icon(widget.note == null ? Icons.edit_note_rounded : Icons.edit_outlined,
                size: 20, color: scheme.primary),
            const Gap.sm(),
            Text(widget.note == null ? l.notesNew : l.notesEdit,
                style: text.titleMedium),
          ]),
          const Gap.ms(),
          // MATN MAYDONI BIRINCHI, sarlavha ikkinchi.
          //
          // Nega tartib teskari: odam daftarga fikrni yozadi, keyin (agar
          // xohlasa) nom qo'yadi. Sarlavha birinchi turganda kursor u yerda
          // bo'ladi va foydalanuvchi «nima deb nomlasam ekan» degan
          // to'siqqa uriladi — aynan shu bosqichda yozuv tashlab ketiladi.
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 10,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l.notesQuickHint,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(
                  borderRadius: Radii.buttonRadius),
            ),
          ),
          const Gap.sm(),
          TextField(
            controller: _title,
            textInputAction: TextInputAction.done,
            maxLength: 200,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: l.notesFieldTitle,
              // Sarlavha bo'sh bo'lsa nima bo'lishini OLDINDAN ko'rsatamiz.
              // Aks holda foydalanuvchi uni majburiy deb o'ylaydi.
              hintText: _title.text.trim().isEmpty ? _effectiveTitle : null,
              counterText: '',
              border: const OutlineInputBorder(
                  borderRadius: Radii.buttonRadius),
            ),
          ),
          if (_error != null) ...[
            const Gap.sm(),
            Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
          const Gap.md(),
          Row(children: [
            TextButton(
              onPressed: _saving || _saved ? null : () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            const Spacer(),
            // Tugma uch holatda: «Saqlash» → aylanuvchi indikator →
            // «✓ Saqlandi». `AnimatedSize` kenglikni silliq o'zgartiradi,
            // aks holda tugma bir kadrda sakrardi.
            AnimatedSize(
              duration: Motion.fast,
              curve: Motion.interactive,
              child: FilledButton.icon(
                onPressed: (_saving || _saved || _body.text.trim().isEmpty)
                    ? null
                    : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_saved ? Icons.check_rounded : Icons.save_outlined,
                        size: 18),
                label: Text(_saved ? l.notesSaved : l.save),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Yuklanish skeleti — daftar qatorlari o'rnida.
class _NotesSkeleton extends StatelessWidget {
  const _NotesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm, Spacing.md, 96),
      itemCount: 5,
      separatorBuilder: (_, __) => const Gap.ms(),
      itemBuilder: (_, __) => const Skeleton(height: 84, radius: Radii.lg),
    );
  }
}
