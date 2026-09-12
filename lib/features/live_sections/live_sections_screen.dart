import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import 'join_sheet.dart';
import 'live_sections_data.dart';

/// Live sections open to the signed-in student.
///
/// Deliberately minimal: it exists so the join flow — the point of this
/// change — is reachable. The richer detail and attempt screens belong to the
/// live-sections rebuild (MOBILE_ARCHITECTURE.md §8).
class LiveSectionsScreen extends ConsumerWidget {
  const LiveSectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final async = ref.watch(liveSectionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.liveSectionsTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: EmptyState(
            icon: Icons.wifi_off,
            title: l.geoLoadFailed,
            message: l.errServer,
            actionLabel: l.retry,
            onAction: () => ref.invalidate(liveSectionsProvider),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(
                child: EmptyState(
                  icon: Icons.event_available_outlined,
                  title: l.liveSectionsEmptyTitle,
                  message: l.liveSectionsEmptyBody,
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(liveSectionsProvider),
                child: ListView.separated(
                  padding: Spacing.page(context),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Gap.sm(),
                  itemBuilder: (_, i) => _SectionCard(item: items[i]),
                ),
              ),
      ),
    );
  }
}

class _SectionCard extends ConsumerStatefulWidget {
  const _SectionCard({required this.item});
  final LiveSectionSummary item;

  @override
  ConsumerState<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends ConsumerState<_SectionCard> {
  bool _opening = false;

  Future<void> _join() async {
    setState(() => _opening = true);
    try {
      // Detail carries `school_fixed`, which decides which pickers the sheet
      // shows — fetched before opening, never guessed from the list row.
      final detail =
          await ref.read(liveSectionRepositoryProvider).detail(widget.item.id);
      if (!mounted) return;
      final ok = await JoinSheet.show(
        context,
        detail,
        initialRegionCode: ref.read(authControllerProvider).user?.regionCode,
      );
      if (ok == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).joinDone)),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final it = widget.item;
    final theme = Theme.of(context);
    final canJoin = !it.registered && it.registrationOpen && !_opening;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(it.title, style: theme.textTheme.titleMedium),
            if (it.description != null && it.description!.isNotEmpty) ...[
              const Gap.xs(),
              Text(it.description!, style: theme.textTheme.bodySmall),
            ],
            const Gap.xs(),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                _Chip(icon: Icons.schedule, label: _when(it.startAt)),
                if (it.schoolFixed)
                  _Chip(
                    icon: Icons.school_outlined,
                    label: it.school?.label ?? l.joinFixedSchool,
                  ),
                if (it.isProctored)
                  _Chip(
                      icon: Icons.visibility_outlined,
                      label: l.liveSectionProctored),
              ],
            ),
            const Gap.sm(),
            if (it.registered)
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: const Icon(Icons.check, size: 16),
                  label: Text(l.joinRegistered),
                ),
              )
            else
              FilledButton.tonal(
                onPressed: canJoin ? _join : null,
                child: Text(it.registrationOpen ? l.joinSubmit : l.joinClosed),
              ),
          ],
        ),
      ),
    );
  }

  String _when(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: 16),
        label: Text(label, overflow: TextOverflow.ellipsis),
        visualDensity: VisualDensity.compact,
      );
}
