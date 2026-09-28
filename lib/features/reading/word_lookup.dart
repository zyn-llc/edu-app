import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../core/pronounce.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/language_kit.dart';
import '../language/display_names.dart';
import '../vocab/vocab_data.dart';

/// Matn ichidagi so'zga bosish -> tarjima oynachasi.
///
/// TOPILMASA — HECH NARSA KO'RSATILMAYDI. Lug'atda so'z yo'q bo'lsa,
/// "taxminiy" tarjima chiqarish xato o'rgatish bo'lardi. Bu ayniqsa rus
/// tilida tez-tez uchraydi: matnda so'z TURLANGAN shaklda
/// ("работает"), lug'atda esa bosh shaklda ("работать") yotadi, ya'ni
/// to'g'ridan-to'g'ri qidiruv uni topmaydi.
///
/// Shuning uchun qidiruv ikki bosqichli: avval to'liq so'z, keyin
/// qisqartirilgan o'zak bo'yicha prefiks. Baribir topilmasa — jim.

/// Bosilgan so'zni lug'atdan qidirish natijasi.
final wordLookupProvider =
    FutureProvider.family<VocabEntry?, ({String word, String language})>(
        (ref, arg) async {
  final repo = ref.read(vocabRepositoryProvider);
  final clean = arg.word.toLowerCase();
  if (clean.length < 2) return null;

  Future<VocabEntry?> hunt(String q) async {
    final found = await repo.entries(
        VocabQuery(language: arg.language, search: q),
        limit: 8);
    if (found.isEmpty) return null;
    // Aynan mos kelgani bo'lsa — o'sha. Bo'lmasa eng qisqasi: u bosh
    // shaklga eng yaqin nomzod.
    for (final e in found) {
      if (e.lemma.toLowerCase() == clean) return e;
    }
    found.sort((a, b) => a.lemma.length.compareTo(b.lemma.length));
    return found.first;
  }

  final exact = await hunt(clean);
  if (exact != null && exact.lemma.toLowerCase() == clean) return exact;

  // Turlangan shakl uchun: oxiridan bir necha harf olib, o'zak bo'yicha.
  if (clean.length >= 5) {
    final stem = clean.substring(0, clean.length - 2);
    final byStem = await hunt(stem);
    if (byStem != null) return byStem;
  }
  return exact;
});

/// Har bir so'zi bosiladigan matn.
class TappableText extends ConsumerWidget {
  const TappableText({
    super.key,
    required this.text,
    required this.language,
    this.highlight,
  });

  final String text;
  final String language;

  /// Javobdan keyin belgilanadigan dalil jumlasi.
  final String? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 18 px va 1.7 qator oralig'i — uzun matn uchun o'qishga qulay.
    final base = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 18,
      height: 1.7,
      color: cs.onSurface,
    );

    final hl = (highlight ?? '').trim();
    final spans = <InlineSpan>[];

    // Dalil jumlasini ajratib, uchta bo'lakka bo'lamiz.
    final segments = <(String, bool)>[];
    if (hl.isEmpty) {
      segments.add((text, false));
    } else {
      final at = text.indexOf(hl);
      if (at < 0) {
        segments.add((text, false));
      } else {
        if (at > 0) segments.add((text.substring(0, at), false));
        segments.add((hl, true));
        final rest = at + hl.length;
        if (rest < text.length) segments.add((text.substring(rest), false));
      }
    }

    for (final (chunk, marked) in segments) {
      for (final token in _tokenise(chunk)) {
        if (token.isWord) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _Word(
              word: token.text,
              language: language,
              style: base,
              marked: marked,
            ),
          ));
        } else {
          spans.add(TextSpan(
            text: token.text,
            style: marked
                ? base?.copyWith(backgroundColor: cs.primaryContainer)
                : base,
          ));
        }
      }
    }

    // 68ch — satr uzunligi chegarasi. Undan uzun satrda ko'z keyingi
    // qatorning boshini topolmaydi.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 68 * 9.0),
      child: SelectionArea(
        child: Text.rich(TextSpan(children: spans), style: base),
      ),
    );
  }
}

class _Token {
  const _Token(this.text, this.isWord);
  final String text;
  final bool isWord;
}

final _wordRe = RegExp(r"[\p{L}\p{M}’'-]+", unicode: true);

List<_Token> _tokenise(String s) {
  final out = <_Token>[];
  var last = 0;
  for (final m in _wordRe.allMatches(s)) {
    if (m.start > last) out.add(_Token(s.substring(last, m.start), false));
    out.add(_Token(m.group(0)!, true));
    last = m.end;
  }
  if (last < s.length) out.add(_Token(s.substring(last), false));
  return out;
}

class _Word extends ConsumerWidget {
  const _Word({
    required this.word,
    required this.language,
    required this.style,
    required this.marked,
  });

  final String word;
  final String language;
  final TextStyle? style;
  final bool marked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _show(context, ref),
      child: Text(
        word,
        style: marked
            ? style?.copyWith(backgroundColor: cs.primaryContainer)
            : style,
      ),
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final clean = word.replaceAll(RegExp(r"[’'-]+$"), '');
    final entry = await ref.read(
        wordLookupProvider((word: clean, language: language)).future);
    // Lug'atda yo'q bo'lsa — jim. Taxminiy tarjima xato o'rgatadi.
    if (entry == null || !context.mounted) return;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _WordSheet(entry: entry),
    );
  }
}

class _WordSheet extends ConsumerStatefulWidget {
  const _WordSheet({required this.entry});

  final VocabEntry entry;

  @override
  ConsumerState<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends ConsumerState<_WordSheet> {
  bool _added = false;
  bool _busy = false;

  Future<void> _add() async {
    setState(() => _busy = true);
    HapticFeedback.selectionClick();
    try {
      await ref.read(vocabRepositoryProvider).addToDeck([widget.entry.id]);
      ref.invalidate(vocabStatsProvider);
      ref.invalidate(vocabDueProvider);
      if (mounted) setState(() => _added = true);
    } catch (_) {
      // Qo'shilmasa ham oynacha yiqilmasligi kerak.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final e = widget.entry;
    final uiLang = ref.watch(localeCodeProvider);
    final pos = DisplayNames.pos(e.pos, e.language, uiLang);
    final canSpeak =
        ref.watch(pronounceSupportedProvider(e.language)).valueOrNull == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, 0, Spacing.lg, Spacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LevelChip(e.cefrLevel, compact: true),
              const Gap.sm(),
              Expanded(
                child: Text(e.display,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (canSpeak)
                IconButton.filledTonal(
                  key: const Key('word-speak'),
                  icon: const Icon(Icons.volume_up_rounded),
                  tooltip: l.vocabListen,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () =>
                      ref.read(pronounceServiceProvider).say(e.lemma, e.language),
                ),
            ],
          ),
          const Gap.sm(),
          Text(e.translation(uiLang) ?? l.vocabNoTranslation,
              style: theme.textTheme.titleMedium),
          if (pos.isNotEmpty) ...[
            const Gap.xs(),
            Text(pos, style: theme.textTheme.bodySmall),
          ],
          const Gap.md(),
          if (_added || e.inDeck)
            Row(
              key: const Key('word-added'),
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const Gap.sm(),
                Text(l.vocabInDeckLabel,
                    style: theme.textTheme.bodyMedium),
              ],
            )
          else
            PrimaryButton(
              key: const Key('word-add'),
              label: l.vocabAddToDeck,
              icon: Icons.add_circle_outline,
              expand: true,
              onPressed: _busy ? null : _add,
            ),
        ],
      ),
    );
  }
}
