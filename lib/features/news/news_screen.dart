import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/elevation.dart';
import '../../theme/spacing.dart';
import '../../theme/app_colors.dart';
import '../../widgets/empty_state.dart';
import 'news_data.dart';

/// News / announcements feed. Open to guests as well as signed-in users.
class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.newsTitle)),
      body: ref.watch(newsProvider).when(
            loading: () => const _NewsSkeleton(),
            error: (e, _) => EmptyState(
              icon: Icons.cloud_off,
              title: l.errServer,
              message: humanError(e, l),
              actionLabel: l.retry,
              onAction: () => ref.invalidate(newsProvider),
            ),
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.campaign_outlined,
                  title: l.newsEmptyTitle,
                  message: l.newsEmptyHint,
                  actionLabel: l.retry,
                  onAction: () => ref.invalidate(newsProvider),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.refresh(newsProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _NewsCard(item: items[i]),
                ),
              );
            },
          ),
    );
  }
}

class _NewsSkeleton extends StatelessWidget {
  const _NewsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => const Skeleton(height: 96, radius: 14),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final Announcement item;
  const _NewsCard({required this.item});

  /// Maintenance and updates should look different from promos at a glance.
  (IconData, Color) _style(ColorScheme scheme) => switch (item.kind) {
        'maintenance' => (Icons.build_outlined, scheme.error),
        'update' => (Icons.system_update_alt, scheme.primary),
        'promo' => (Icons.local_offer_outlined, scheme.tertiary),
        _ => (Icons.campaign_outlined, scheme.primary),
      };

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = _style(scheme);
    final d = item.publishedAt;
    final stamp =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: Shadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(item.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Text(stamp, style: TextStyle(fontSize: 11, color: p.muted)),
            ],
          ),
          const SizedBox(height: 10),
          Text(item.body,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: p.muted)),
        ],
      ),
    );
  }
}