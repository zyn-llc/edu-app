import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/spacing.dart';

/// Bo'sh holat — ikonka, sarlavha, izoh va HARAKAT.
///
/// Nega shunchaki "Hozircha bellashuvlar yo'q" yetarli emas: bo'sh ekran
/// foydalanuvchiga ilova buzuq yoki tugallanmagandek tuyuladi. Yaxshi bo'sh
/// holat uch savolga javob beradi:
///   1. Nima uchun bu yer bo'sh?
///   2. Bu normalmi?
///   3. Endi nima qilay?
///
/// Uchinchisi eng muhimi — shuning uchun `action` ixtiyoriy emas, deyarli
/// har doim berilishi kerak.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Karta ichida ko'rsatilganda — kichikroq ikonka, kamroq bo'shliq.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: compact ? Spacing.lg : Spacing.xl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 64 : 88,
                height: compact ? 64 : 88,
                decoration: BoxDecoration(
                  color: palette.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    size: compact ? 30 : 40, color: scheme.primary),
              ),
              Gap(compact ? Spacing.md : Spacing.lg),
              Text(title,
                  style: compact ? text.titleLarge : text.headlineSmall,
                  textAlign: TextAlign.center),
              const Gap.sm(),
              Text(message,
                  style: text.bodyMedium, textAlign: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                Gap(compact ? Spacing.md : Spacing.lg),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
              if (secondaryLabel != null && onSecondary != null) ...[
                const Gap.sm(),
                TextButton(
                    onPressed: onSecondary, child: Text(secondaryLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Yuklanish paytidagi "skelet" — kulrang to'rtburchak, yengib o'tuvchi
/// yaltirash bilan.
///
/// `CircularProgressIndicator` dan afzalligi: foydalanuvchi kontent QANDAY
/// joylashishini oldindan ko'radi, shuning uchun yuklanish tezroq tuyuladi
/// va kontent kelganda sahifa "sakramaydi".
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = Radii.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              // Yaltirash chapdan o'ngga suriladi. `-1..2` oralig'i —
              // yaltirash to'liq chiqib ketishi uchun.
              begin: Alignment(-1 + _c.value * 3, 0),
              end: Alignment(_c.value * 3, 0),
              colors: [
                palette.surfaceAlt,
                palette.hairline,
                palette.surfaceAlt,
              ],
            ),
          ),
        );
      },
    );
  }
}
