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
import '../../theme/level_palette.dart';
import '../../theme/spacing.dart';
import '../../widgets/language_kit.dart';
import '../language/display_names.dart';
import 'vocab_data.dart';

/// "Barcha so'zlar" — lug'atni ko'rish va to'plamga qo'shish.
///
/// XOM KALIT BU YERGA CHIQMAYDI. Mavzu va so'z turkumi
/// `DisplayNames` orqali o'zbekchaga o'giriladi: ilgari ekranda
/// `science_abstract (1054)` va `noun` turardi.
///
/// Ko'rish uchun kirish shart emas; to'plamga qo'shish uchun shart.
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
      // Belgi darhol o'zgaradi — ro'yxat qayta yuklanguncha kutmaydi,
      // aks holda tugma bosilgandek tuyulmaydi.
      if (mounted) setState(() => _justAdded.add(e.id));
      ref.invalidate(vocabStatsProvider);
      ref.invalidate(vocabDueProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.vocabAdded(e.display))));
      }
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
    final entries = ref.watch(vocabEntriesProvider(_q));
    final topics = ref.watch(vocabTopicsProvider(widget.language));

    return Scaffold(
      appBar: AppBar(title: Text(l.vocabBrowseAction)),
      body: SafeArea(
        child: ContentWidth(
          child: Column(
            children: [
              // ---- qidiruv ---------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
                child: TextField(
                  key: const Key('vocab-search'),
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l.vocabSearchHint,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _q = _q.copyWith(search: ''));
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) =>
                      setState(() => _q = _q.copyWith(search: v)),
                ),
              ),

              // ---- daraja ----------------------------------------------
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: Spacing.md),
                  children: [
                    _Pill(
                      key: const Key('vocab-level-all'),
                      label: l.vocabAllLevels,
                      selected: _q.level == null,
                      onTap: () =>
                          setState(() => _q = _q.copyWith(clearLevel: true)),
                    ),
                    for (final lv in LevelPalette.order)
                      _Pill(
                        key: Key('vocab-level-$lv'),
                        label: lv,
                        color: LevelPalette.color(lv, theme.brightness),
                        selected: _q.level == lv,
                        onTap: () => setState(() => _q = _q.level == lv
                            ? _q.copyWith(clearLevel: true)
                            : _q.copyWith(level: lv)),
                      ),
                  ],
                ),
              ),

              // ---- mavzu (O'ZBEKCHA nom + son) --------------------------
              topics.maybeWhen(
                data: (ts) => SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: Spacing.md),
                    children: [
                      _Pill(
                        label: l.vocabAllTopics,
                        selected: _q.topic == null,
                        onTap: () => setState(
                            () => _q = _q.copyWith(clearTopic: true)),
                      ),
                      for (final t in ts)
                        _Pill(
                          key: Key('vocab-topic-${t.topic}'),
                          // Son ATAYLAB ko'rsatilmaydi: o'quvchiga
                          // mavzuda nechta so'z borligi emas, mavzuning
                          // o'zi kerak.
                          label: DisplayNames.topic(t.topic, uiLang),
                          selected: _q.topic == t.topic,
                          onTap: () => setState(() => _q = _q.topic == t.topic
                              ? _q.copyWith(clearTopic: true)
                              : _q.copyWith(topic: t.topic)),
                        ),
                    ],
                  ),
                ),
                orElse: () => const SizedBox(height: 44),
              ),
              const Gap.sm(),
              const Divider(height: 1),

              // ---- ro'yxat ---------------------------------------------
              Expanded(
                child: entries.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: OwlEmptyState(
                      state: OwlState.confused,
                      title: l.vocabLoadFailedTitle,
                      message: humanError(e, l),
                      actionLabel: l.retry,
                      onAction: () =>
                          ref.invalidate(vocabEntriesProvider(_q)),
                    ),
                  ),
                  data: (items) => items.isEmpty
                      ? Center(
                          child: OwlEmptyState(
                            key: const Key('vocab-browse-empty'),
                            state: OwlState.confused,
                            title: l.vocabNoResultsTitle,
                            message: l.vocabNoResultsBody,
                          ),
                        )
                      : ListView.separated(
                          key: const Key('vocab-list'),
                          padding: const EdgeInsets.only(bottom: Spacing.lg),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: Spacing.md),
                          itemBuilder: (_, i) => _WordRow(
                            entry: items[i],
                            uiLang: uiLang,
                            inDeck: items[i].inDeck ||
                                _justAdded.contains(items[i].id),
                            pending: _pending.contains(items[i].id),
                            canAdd: signedIn,
                            onAdd: () => _add(items[i]),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordRow extends ConsumerWidget {
  const _WordRow({
    required this.entry,
    required this.uiLang,
    required this.inDeck,
    required this.pending,
    required this.canAdd,
    required this.onAdd,
  });

  final VocabEntry entry;
  final String uiLang;
  final bool inDeck;
  final bool pending;
  final bool canAdd;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // `noun` emas, `ot`.
    final pos = DisplayNames.pos(entry.pos, entry.language, uiLang);
    final canSpeak =
        ref.watch(pronounceSupportedProvider(entry.language)).valueOrNull ==
            true;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      child: Row(
        children: [
          LevelDot(entry.cefrLevel),
          const Gap.ms(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.display,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  entry.translation(uiLang) ?? l.vocabNoTranslation,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (pos.isNotEmpty)
                  Text(pos, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          if (canSpeak)
            IconButton(
              key: Key('vocab-say-${entry.id}'),
              icon: const Icon(Icons.volume_up_outlined),
              tooltip: l.vocabListen,
              onPressed: () {
                HapticFeedback.selectionClick();
                ref
                    .read(pronounceServiceProvider)
                    .say(entry.lemma, entry.language);
              },
            ),
          // Qo'shilgani darhol ko'rinadi va belgi "sakrab" chiqadi.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: inDeck
                ? Icon(Icons.check_circle,
                    key: const ValueKey('in'), color: cs.primary, size: 28)
                    .animate()
                    .scale(
                        begin: const Offset(0.6, 0.6),
                        curve: Curves.easeOutBack,
                        duration: 260.ms)
                : IconButton(
                    key: Key('vocab-add-${entry.id}'),
                    icon: pending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_circle_outline),
                    tooltip: l.vocabAddToDeck,
                    onPressed: canAdd && !pending ? onAdd : null,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Filtr tugmasi — daraja rangida yoki neytral, son kichik nishon bilan.
class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = color ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.only(right: Spacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          decoration: BoxDecoration(
            color: selected ? c : c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: selected ? c : c.withValues(alpha: 0.30)),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? cs.onPrimary : c,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
