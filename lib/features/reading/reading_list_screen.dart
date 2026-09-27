import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import 'reading_data.dart';
import 'reading_screen.dart';

/// Matnlar ro'yxati: daraja bo'yicha filtr, holat, o'qish vaqti.
///
/// HOZIRCHA FAQAT RUS TILIDA matn bor. Ro'yxat bo'sh bo'lsa, buni ochiq
/// aytamiz — "xato" deb ko'rsatish yolg'on bo'lardi.
class ReadingListScreen extends ConsumerStatefulWidget {
  const ReadingListScreen({super.key, required this.language});

  final String language;

  @override
  ConsumerState<ReadingListScreen> createState() => _ReadingListScreenState();
}

const _levels = ['A1', 'A2', 'B1', 'B2', 'C1'];

class _ReadingListScreenState extends ConsumerState<ReadingListScreen> {
  String? _level;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final q = ReadingQuery(language: widget.language, level: _level);
    final async = ref.watch(passagesProvider(q));

    return Scaffold(
      appBar: AppBar(title: Text(l.readingTitle)),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              children: [
                FilterChip(
                  key: const Key('reading-level-all'),
                  label: Text(l.vocabAllLevels),
                  selected: _level == null,
                  onSelected: (_) => setState(() => _level = null),
                ),
                for (final lv in _levels) ...[
                  const SizedBox(width: Spacing.xs),
                  FilterChip(
                    key: Key('reading-level-$lv'),
                    label: Text(lv),
                    selected: _level == lv,
                    onSelected: (_) =>
                        setState(() => _level = _level == lv ? null : lv),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: EmptyState(
                  icon: Icons.cloud_off,
                  title: l.vocabLoadFailedTitle,
                  message: humanError(e, l),
                  actionLabel: l.retry,
                  onAction: () => ref.invalidate(passagesProvider(q)),
                ),
              ),
              data: (items) => items.isEmpty
                  ? Center(
                      child: EmptyState(
                        key: const Key('reading-empty'),
                        icon: Icons.menu_book_outlined,
                        title: l.readingNonePlannedTitle,
                        message: l.readingNonePlannedBody,
                      ),
                    )
                  : ListView.separated(
                      key: const Key('reading-list'),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = items[i];
                        return ListTile(
                          key: Key('reading-item-${p.id}'),
                          leading: CircleAvatar(
                            radius: 16,
                            child: Text(p.cefrLevel,
                                style: theme.textTheme.labelSmall),
                          ),
                          title: Text(p.topic ?? p.id,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.readingMeta(p.wordCount, p.readMinutes)),
                              if (p.answered > 0) ...[
                                const Gap.xs(),
                                LinearProgressIndicator(
                                    value: p.shareAnswered),
                              ],
                            ],
                          ),
                          trailing: switch (p.state) {
                            PassageState.done => Icon(Icons.check_circle,
                                color: theme.colorScheme.primary),
                            PassageState.started =>
                              const Icon(Icons.timelapse),
                            PassageState.newPassage =>
                              const Icon(Icons.chevron_right),
                          },
                          isThreeLine: p.answered > 0,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    ReadingScreen(passageId: p.id)),
                          ).then((_) => ref.invalidate(passagesProvider(q))),
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
