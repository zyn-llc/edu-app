import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../features/auth/login_sheet.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';

///
///
/// ilovani yopadi va qaytmaydi.
///
class GuestSignupPrompt extends ConsumerWidget {
  const GuestSignupPrompt({super.key, required this.answered});

  final int answered;

  static Future<bool> maybeShow(
    BuildContext context,
    WidgetRef ref, {
    required int answered,
  }) async {
    final auth = ref.read(authControllerProvider);
    if (auth.isAuthenticated || auth.initializing) return false;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => GuestSignupPrompt(answered: answered),
    );
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: palette.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.workspace_premium_outlined,
                    size: 34, color: scheme.primary),
              ),
            ),
            const Gap.md(),
            Text(l.guestProgressTitle,
                style: text.headlineSmall, textAlign: TextAlign.center),
            const Gap.sm(),
            Text(
              '${l.guestSolvedCount(answered)}\n${l.guestProgressHint}',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const Gap.lg(),
            FilledButton(
              onPressed: () {
                final root =
                    Navigator.of(context, rootNavigator: true).context;
                Navigator.pop(context);
                LoginSheet.show(root, reason: l.guestProgressHint);
              },
              child: Text(l.guestProgressCta),
            ),
            const Gap.sm(),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.guestLater),
            ),
          ],
        ),
      ),
    );
  }
}
