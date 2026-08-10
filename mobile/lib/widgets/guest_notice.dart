import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../features/auth/login_sheet.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';

class GuestNotice extends ConsumerWidget {
  const GuestNotice({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth.isAuthenticated || auth.initializing) {
      return const SizedBox.shrink();
    }

    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: palette.primaryTint,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: scheme.primary),
          const Gap.ms(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.guestProgressTitle,
                    style: text.titleMedium?.copyWith(color: scheme.primary)),
                const Gap.xs(),
                Text(l.guestProgressHint, style: text.bodySmall),
                if (!compact) ...[
                  const Gap.ms(),
                  FilledButton(
                    onPressed: () => LoginSheet.show(context,
                        reason: l.guestProgressHint),
                    child: Text(l.guestProgressCta),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
