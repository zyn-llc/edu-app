import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/elevation.dart';
import '../theme/motion.dart';
import '../theme/spacing.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.ms),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: scheme.primary),
            const Gap.sm(),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.headlineSmall),
                if (subtitle != null) ...[
                  const Gap.xs(),
                  Text(subtitle!, style: text.bodySmall),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// A single stat tile: icon, value and label.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    this.icon,
    this.iconWidget,
    required this.value,
    required this.label,
    this.delta,
    this.accent,
    this.progress,
    this.count,
  }) : assert(icon != null || iconWidget != null,
            'StatCard: `icon` yoki `iconWidget` dan biri berilishi shart');

  final IconData? icon;

  /// noncoin kristali (`widgets/currency.dart`).
  ///
  final Widget? iconWidget;

  final String value;
  final String label;

  final String? delta;
  final Color? accent;

  final double? progress;

  final int? count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final color = accent ?? scheme.primary;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: palette.hairline),
        boxShadow: Shadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: SizedBox(
              width: 18,
              height: 18,
              child: Center(
                child: iconWidget ?? Icon(icon, size: 18, color: color),
              ),
            ),
          ),
          const Gap.ms(),
          _Value(count: count, fallback: value, style: text.headlineMedium),
          const Gap.xs(),
          Text(label,
              style: text.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (delta != null) ...[
            const Gap.sm(),
            Text(delta!,
                style: text.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ],
          if (progress != null) ...[
            const Gap.ms(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress!.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Motion.enter,
              builder: (_, v, __) => ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 4,
                  backgroundColor: palette.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.count, required this.fallback, this.style});

  final int? count;
  final String fallback;
  final TextStyle? style;

  static String grouped(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u2009');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = style?.copyWith(height: 1.0);
    if (count == null) {
      return Text(fallback,
          style: s, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: count!.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(
        grouped(v.round()),
        style: s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Halqa shaklidagi progress. Ichida foiz yoki ixtiyoriy vidjet.
///
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 44,
    this.stroke = 4,
    this.color,
    this.child,
  });

  /// 0..1
  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final c = color ?? scheme.primary;
    final v = value.clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(v, c, palette.surfaceAlt, stroke),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, trackPaint);

    if (value <= 0) return;

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // soat 12 dan boshlanadi
      2 * math.pi * value,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}
