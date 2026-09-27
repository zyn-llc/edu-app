import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/api_error.dart';
import '../../core/pronounce.dart';
import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import 'vocab_data.dart';

/// Lug'atni ko'rish: daraja va mavzu bo'yicha filtr, to'plamga qo'shish.
///
/// KIRISH SHART EMAS ko'rish uchun — mehmon so'zlarni ko'rib, modul nima
/// ekanini tushunishi kerak. To'plamga qo'shish esa akkaunt talab qiladi.
class VocabBrowseScreen extends ConsumerStatefulWidget {
  const VocabBrowseScreen({super.key, required this.language});

  final String language;

  @override
  ConsumerState<VocabBrowseScreen> createState() => _VocabBrowseScreenState();
}

const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

class _VocabBrowseScreenState extends ConsumerState<VocabBrowseScreen> {
  late VocabQuery _q = VocabQuery(language: widget.language);
  final _searchCtrl = TextEditingController();
  final _pending = <String>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _add(VocabEntry e) async {
    final l = L10n.of(context);
    setState(() => _pending.add(e.id));
    try {
      await ref.read(vocabRepositoryProvider).addToDeck([e.id]);
      ref.invalidate(vocabEntriesProvider(_q));
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
      appBar: AppBar(title: Text(l.vocabTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, 0),
            child: TextField(
              key: const Key('vocab-search'),
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.vocabSearchHint,
                isDense: true,
              ),
              onSubmitted: (v) => setState(() => _q = _q.copyWith(search: v)),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              children: [
                FilterChip(
                  key: const Key('vocab-level-all'),
                  label: Text(l.vocabAllLevels),
                  selected: _q.level == null,
                  onSelected: (_) =>
                      setState(() => _q = _q.copyWith(clearLevel: true)),
                ),
                for (final lv in _levels) ...[
                  const SizedBox(width: Spacing.xs),
                  FilterChip(
                    key: Key('vocab-level-$lv'),
                    label: Text(lv),
                    selected: _q.level == lv,
                    onSelected: (_) => setState(() => _q = _q.level == lv
                        ? _q.copyWith(clearLevel: true)
                        : _q.copyWith(level: lv)),
                  ),
                ],
              ],
            ),
          ),
          topics.maybeWhen(
            data: (ts) => SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                children: [
                  FilterChip(
                    label: Text(l.vocabAllTopics),
                    selected: _q.topic == null,
                    onSelected: (_) =>
                        setState(() => _q = _q.copyWith(clearTopic: true)),
                  ),
                  for (final t in ts.take(24)) ...[
                    const SizedBox(width: Spacing.xs),
                    FilterChip(
                      label: Text('${t.topic} (${t.count})'),
                      selected: _q.topic == t.topic,
                      onSelected: (_) => setState(() => _q =
                          _q.topic == t.topic
                              ? _q.copyWith(clearTopic: true)
                              : _q.copyWith(topic: t.topic)),
                    ),
                  ],
                ],
              ),
            ),
            orElse: () => const SizedBox(height: 44),
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: EmptyState(
                  icon: Icons.cloud_off,
                  title: l.vocabLoadFailedTitle,
                  message: humanError(e, l),
                  actionLabel: l.retry,
                  onAction: () => ref.invalidate(vocabEntriesProvider(_q)),
                ),
              ),
              data: (items) => items.isEmpty
                  ? Center(
                      child: EmptyState(
                        key: const Key('vocab-browse-empty'),
                        icon: Icons.search_off,
                        title: l.vocabNoResultsTitle,
                        message: l.vocabNoResultsBody,
                      ),
                    )
                  : ListView.separated(
                      key: const Key('vocab-list'),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = items[i];
                        return ListTile(
                          title: Text(e.display),
                          subtitle: Text(
                            [
                              e.translation(uiLang) ?? l.vocabNoTranslation,
                              if ((e.ipa ?? '').isNotEmpty) e.ipa!,
                            ].join('  ·  '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          leading: CircleAvatar(
                            radius: 16,
                            child: Text(e.cefrLevel,
                                style: theme.textTheme.labelSmall),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Talaffuz — ro'yxatda ham. Til uchun ovoz
                              // bo'lmasa tugma umuman chiqmaydi.
                              if (ref
                                      .watch(pronounceSupportedProvider(
                                          e.language))
                                      .valueOrNull ==
                                  true)
                                IconButton(
                                  key: Key('vocab-say-${e.id}'),
                                  icon: const Icon(Icons.volume_up_outlined),
                                  tooltip: l.vocabListen,
                                  onPressed: () => ref
                                      .read(pronounceServiceProvider)
                                      .say(e.lemma, e.language),
                                ),
                              e.inDeck
                              ? Icon(Icons.check_circle,
                                  color: theme.colorScheme.primary)
                              : IconButton(
                                  key: Key('vocab-add-${e.id}'),
                                  icon: _pending.contains(e.id)
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.add_circle_outline),
                                  tooltip: l.vocabAddToDeck,
                                  onPressed: signedIn && !_pending.contains(e.id)
                                      ? () => _add(e)
                                      : null,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
