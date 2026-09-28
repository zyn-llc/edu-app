import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/api_error.dart';
import '../../auth/auth_controller.dart';
import '../../core/pronounce.dart';
import '../../l10n/app_localizations.dart';
import '../../mascot/mascot.dart';
import '../../theme/app_colors.dart' show AppPalette;
import '../../theme/level_palette.dart';
import '../../theme/spacing.dart';
import '../../widgets/language_kit.dart';
import '../language/display_names.dart';
import '../language/readable_pronunciation.dart';
import 'vocab_data.dart';

/// "Barcha so'zlar" — lug'atni ko'rish va to'plamga qo'shish.
///
/// XOM KALIT BU YERGA CHIQMAYDI. Mavzu va so'z turkumi `DisplayNames`
/// orqali o'zbekchaga o'giriladi.
///
/// SARLAVHA VA RO'YXAT BIR USTUNDA. Ilgari orqaga tugmasi ekranning eng
/// chap chetida yolg'iz turardi, ro'yxat esa markazda — ikkisi boshqa-
/// boshqa sahifadek ko'rinardi. Endi hammasi 720 px li bitta ustunda.
class VocabBrowseScreen extends ConsumerStatefulWidget {
  const VocabBrowseScreen({super.key, required this.language});

  final String language;

  @override
  ConsumerState<VocabBrowseScreen> createState() => _VocabBrowseScreenState();
}

class _VocabBrowseScreenState extends ConsumerState<VocabBrowseScreen> {
  late VocabQuery _q = VocabQuery(language: widget.language);
  final _searchCtrl = TextEditingController();
  final _pending = <String>{};
  final _justAdded = <String>{};
  String? _expanded;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _add(VocabEntry e) async {
    final l = L10n.of(context);
    setState(() => _pending.add(e.id));
    HapticFeedback.selectionClick();
    try {
      await ref.read(vocabRepositoryProvider).addToDeck([e.id]);
      if (mounted) setState(() => _justAdded.add(e.id));
      ref.invalidate(vocabStatsProvider);
      ref.invalidate(vocabDueProvider);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(humanError(err, l))));
      }
    } finally {
      if (mounted) setState(() => _pending.remove(e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final uiLang = ref.watch(localeCodeProvider);
    final signedIn = ref.watch(authControllerProvider).isAuthenticated;
    final page = ref.watch(vocabPageProvider(_q));
    final topics = ref.watch(vocabTopicsProvider(widget.language));

    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: CustomScrollView(
            slivers: [
              // Sarlavha USTUN ichida — chetda yolg'iz qolmaydi.
              SliverAppBar(
                pinned: true,
                titleSpacing: 0,
                backgroundColor: theme.colorScheme.surface,
                surfaceTintColor: Colors.transparent,
                leading: const BackButton(),
                title: Text(l.vocabBrowseAction),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(148),
                  child: _StickyHeader(
                    controller: _searchCtrl,
                    query: _q,
                    total: page.valueOrNull?.total,
                    topics: topics.valueOrNull ?? const [],
                    uiLang: uiLang,
                    onQuery: (q) => setState(() => _q = q),
                  ),
                ),
              ),
              page.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: OwlEmptyState(
                      state: OwlState.confused,
                      title: l.vocabLoadFailedTitle,
                      message: humanError(e, l),
                      actionLabel: l.retry,
                      onAction: () =>
                          ref.invalidate(vocabPageProvider(_q)),
                    ),
                  ),
                ),
                data: (p) => p.items.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: OwlEmptyState(
                            key: const Key('vocab-browse-empty'),
                            state: OwlState.confused,
                            title: l.vocabNoResultsTitle,
                            message: l.vocabNoResultsBody,
                          ),
                        ),
                      )
                    : SliverList.separated(
                        itemCount: p.items.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, indent: 68, endIndent: Spacing.md),
                        itemBuilder: (_, i) {
                          final e = p.items[i];
                          return _WordRow(
                            key: Key('vocab-row-${e.id}'),
                            entry: e,
                            uiLang: uiLang,
                            inDeck: e.inDeck || _justAdded.contains(e.id),
                            pending: _pending.contains(e.id),
                            canAdd: signedIn,
                            expanded: _expanded == e.id,
                            onToggle: () => setState(
                                () => _expanded = _expanded == e.id ? null : e.id),
                            onAdd: () => _add(e),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  Yopishib turadigan sarlavha: qidiruv + filtrlar                             //
// --------------------------------------------------------------------------- //
class _StickyHeader extends StatelessWidget {
  const _StickyHeader({
    required this.controller,
    required this.query,
    required this.total,
    required this.topics,
    required this.uiLang,
    required this.onQuery,
  });

  final TextEditingController controller;
  final VocabQuery query;
  final int? total;
  final List<VocabTopic> topics;
  final String uiLang;
  final void Function(VocabQuery) onQuery;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, 0, Spacing.md, Spacing.sm),
            child: TextField(
              key: const Key('vocab-search'),
              controller: controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: l.vocabSearchHint,
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          controller.clear();
                          onQuery(query.copyWith(search: ''));
                        },
                      ),
              ),
              onSubmitted: (v) => onQuery(query.copyWith(search: v)),
            ),
          ),

          // ---- CEFR: BITTA gorizontal qator ---------------------------
          _ChipRow(
            children: [
              _Chip(
                key: const Key('vocab-level-all'),
                label: l.vocabAllLevels,
                selected: query.level == null,
                onTap: () => onQuery(query.copyWith(clearLevel: true)),
              ),
              for (final lv in LevelPalette.order)
                _Chip(
                  key: Key('vocab-level-$lv'),
                  label: lv,
                  // Tanlangan daraja — O'Z rangi, oq matn bilan.
                  selectedColor:
                      LevelPalette.color(lv, theme.brightness),
                  selected: query.level == lv,
                  onTap: () => onQuery(query.level == lv
                      ? query.copyWith(clearLevel: true)
                      : query.copyWith(level: lv)),
                ),
            ],
          ),
          const SizedBox(height: Spacing.xs),

          // ---- mavzu: BITTA gorizontal qator --------------------------
          _ChipRow(
            children: [
              _Chip(
                label: l.vocabAllTopics,
                selected: query.topic == null,
                onTap: () => onQuery(query.copyWith(clearTopic: true)),
              ),
              for (final t in topics)
                _Chip(
                  key: Key('vocab-topic-${t.topic}'),
                  label: DisplayNames.topic(t.topic, uiLang),
                  badge: '${t.count}',
                  // Mavzu tanlanganda TO'Q NEYTRAL rang — to'q sariq
                  // bo'lsa, tanlanmagan holatdan farq qilmasdi, chunki
                  // butun ilova to'q sariq.
                  selectedColor: cs.onSurface,
                  selected: query.topic == t.topic,
                  onTap: () => onQuery(query.topic == t.topic
                      ? query.copyWith(clearTopic: true)
                      : query.copyWith(topic: t.topic)),
                ),
            ],
          ),
          if (total != null) ...[
            const SizedBox(height: Spacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: Text(
                  l.vocabTotalWords(total!),
                  key: const Key('vocab-total'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Gorizontal chip qatori, ikki chetida so'nish.
///
/// So'nish BOR, chunki qator kesilib tugasa, o'quvchi yana chip borligini
/// bilmaydi va surib ko'rmaydi.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return SizedBox(
      height: 40,
      child: ShaderMask(
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [surface, Colors.transparent, Colors.transparent, surface],
          stops: const [0.0, 0.035, 0.965, 1.0],
        ).createShader(r),
        blendMode: BlendMode.dstOut,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          children: children,
        ),
      ),
    );
  }
}

/// Filtr tugmasi — qat'iy 40 px balandlik, matn MARKAZDA.
///
/// Balandlik `padding` bilan emas, `SizedBox` bilan qat'iy: to'ldirish
/// bilan hisoblanganda shrift o'lchami o'zgarsa chip ham o'zgarardi va
/// qator sakrab turardi.
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? selectedColor;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final palette = theme.extension<AppPalette>()!;
    final fillWhenSelected = selectedColor ?? cs.primary;

    final style = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: selected ? Colors.white : cs.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.only(right: Spacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            decoration: BoxDecoration(
              color: selected ? fillWhenSelected : cs.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: selected ? fillWhenSelected : palette.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Text(label, style: style)),
                if (badge != null) ...[
                  const SizedBox(width: Spacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.24)
                          : palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              selected ? Colors.white : palette.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  So'z qatori                                                                 //
// --------------------------------------------------------------------------- //
class _WordRow extends ConsumerWidget {
  const _WordRow({
    super.key,
    required this.entry,
    required this.uiLang,
    required this.inDeck,
    required this.pending,
    required this.canAdd,
    required this.expanded,
    required this.onToggle,
    required this.onAdd,
  });

  final VocabEntry entry;
  final String uiLang;
  final bool inDeck;
  final bool pending;
  final bool canAdd;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final palette = theme.extension<AppPalette>()!;
    final pos = DisplayNames.pos(entry.pos, entry.language, uiLang);
    final canSpeak =
        ref.watch(pronounceSupportedProvider(entry.language)).valueOrNull ==
            true;
    final say = readablePronunciation(
        lemma: entry.lemma, ipa: entry.ipa, language: entry.language);

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        child: Column(
          children: [
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  LevelBadge(entry.cefrLevel),
                  const Gap.ms(),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.display,
                                style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (pos.isNotEmpty) ...[
                              const SizedBox(width: Spacing.sm),
                              _PosPill(pos),
                            ],
                          ],
                        ),
                        Text(
                          entry.translation(uiLang) ?? l.vocabNoTranslation,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 15,
                              // AA uchun `muted`, `faint` emas.
                              color: palette.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (canSpeak)
                    _RoundButton(
                      key: Key('vocab-say-${entry.id}'),
                      icon: Icons.volume_up_outlined,
                      tooltip: l.vocabListen,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        ref
                            .read(pronounceServiceProvider)
                            .say(entry.lemma, entry.language);
                      },
                    ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (c, a) =>
                        ScaleTransition(scale: a, child: c),
                    child: inDeck
                        ? SizedBox(
                            key: const ValueKey('in'),
                            width: 44,
                            height: 44,
                            child: Icon(Icons.check_circle,
                                color: cs.primary, size: 26),
                          )
                            .animate()
                            .scale(
                                begin: const Offset(0.6, 0.6),
                                curve: Curves.easeOutBack,
                                duration: 260.ms)
                        : _RoundButton(
                            key: Key('vocab-add-${entry.id}'),
                            icon: Icons.add_circle_outline,
                            tooltip: l.vocabAddToDeck,
                            busy: pending,
                            onPressed:
                                canAdd && !pending ? onAdd : null,
                          ),
                  ),
                ],
              ),
            ),
            // Bosilganda ochiladi: talaffuz va misol (bo'lsa).
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeOut,
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                key: Key('vocab-expand-${entry.id}'),
                padding: const EdgeInsets.only(
                    left: 52, bottom: Spacing.ms, right: Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (say != null) ...[
                      Text(l.vocabPronounceLabel,
                          style: theme.textTheme.labelSmall),
                      Text(say,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: palette.muted)),
                    ] else
                      Text(l.vocabNoPronounce,
                          style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosPill extends StatelessWidget {
  const _PosPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 1),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: theme.textTheme.labelSmall?.copyWith(color: palette.muted)),
    );
  }
}

/// 44 px tegish maydoni — belgisi kichik bo'lsa ham.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 22,
          tooltip: tooltip,
          onPressed: onPressed,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon),
        ),
      );
}
