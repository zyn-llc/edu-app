import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// Reward colours.
///
/// XP and coins are separate currencies and never share a colour:
/// warm orange for XP, cool violet for coins.
abstract final class Rewards {
  static const xp = Color(0xFFF8721C);

  /// Coin colour, kept clearly apart from the XP orange.
  static const coinDark = Color(0xFF6A53C7);

  /// Kristallning yorug' qirralari.
  static const coinLight = Color(0xFF9C86F0);
}

/// The coin mark: a faceted crystal.
///
///
class NonCoinIcon extends StatefulWidget {
  const NonCoinIcon({super.key, this.size = 20, this.sparkle = false});

  final double size;
  final bool sparkle;

  @override
  State<NonCoinIcon> createState() => _NonCoinIconState();
}

class _NonCoinIconState extends State<NonCoinIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.sparkle && !reduced) {
      if (!_c.isAnimating) _c.repeat();
    } else if (_c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.sparkle) {
      return CustomPaint(
        size: Size.square(widget.size),
        painter: _GemPainter(0),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: Size.square(widget.size),
        painter: _GemPainter(_c.value),
      ),
    );
  }
}

class _GemPainter extends CustomPainter {
  _GemPainter(this.t);

  /// 0..1 — yaltirash fazasi.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Olti burchak: yuqori va pastki uchi o'tkir, yon qirralari tekis.
    final outer = Path()
      ..moveTo(cx, 0)
      ..lineTo(w * 0.94, h * 0.28)
      ..lineTo(w * 0.94, h * 0.72)
      ..lineTo(cx, h)
      ..lineTo(w * 0.06, h * 0.72)
      ..lineTo(w * 0.06, h * 0.28)
      ..close();

    canvas.drawPath(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Rewards.coinLight, Rewards.coinDark],
        ).createShader(Offset.zero & size),
    );

    final facet = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, w * 0.055)
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.06, h * 0.28)
        ..lineTo(cx, h * 0.44)
        ..lineTo(w * 0.94, h * 0.28),
      facet,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx, 0)
        ..lineTo(cx, h * 0.44),
      facet,
    );

    if (t <= 0) return;

    const window = 0.18;
    if (t > window) return;
    final u = t / window; // 0..1
    canvas.save();
    canvas.clipPath(outer);
    final x = -w + u * (w * 3);
    canvas.drawLine(
      Offset(x, h * 1.2),
      Offset(x + w * 0.6, -h * 0.2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.65 * math.sin(math.pi * u))
        ..strokeWidth = w * 0.18,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GemPainter old) => old.t != t;
}

/// XP belgisi — olti burchak ichida chaqmoq.
///
class XpIcon extends StatelessWidget {
  const XpIcon({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Rewards.xp;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size.square(size), painter: _HexPainter(c)),
          Icon(Icons.bolt_rounded, size: size * 0.62, color: c),
        ],
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  _HexPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h * 0.26)
      ..lineTo(w, h * 0.74)
      ..lineTo(w / 2, h)
      ..lineTo(0, h * 0.74)
      ..lineTo(0, h * 0.26)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * 0.05),
    );
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.color != color;
}

class RewardChip extends StatelessWidget {
  const RewardChip.xp(this.text, {super.key})
      : _coin = false,
        color = Rewards.xp;

  const RewardChip.coin(this.text, {super.key})
      : _coin = true,
        color = Rewards.coinDark;

  final String text;
  final Color color;
  final bool _coin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: Radii.pillRadius,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _coin ? const NonCoinIcon(size: 14) : XpIcon(size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: color),
        ),
      ]),
    );
  }
}

/// so'nadi.
///
///
///
///
/// TASHQARIGA chiqib keta oladi (`Stack` ichida `clipBehavior` uni kesib
/// sakramaydi.
///
/// ## Ishlatish
///
/// ```dart
/// RewardFly.show(context, xp: 10, coins: 2);
/// ```
///
abstract final class RewardFly {
  static void show(
    BuildContext context, {
    int xp = 0,
    int coins = 0,
    String xpLabel = 'XP',
    String coinLabel = 'noncoin',
  }) {
    if (xp <= 0 && coins <= 0) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final origin = box.localToGlobal(Offset(box.size.width / 2, 0));

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: origin.dx,
        top: origin.dy,
        child: FractionalTranslation(
          translation: const Offset(-0.5, 0),
          child: _FlyBody(
            xp: xp,
            coins: coins,
            xpLabel: xpLabel,
            coinLabel: coinLabel,
            onDone: () {
              if (entry.mounted) entry.remove();
            },
          ),
        ),
      ),
    );
    overlay.insert(entry);
  }
}

class _FlyBody extends StatefulWidget {
  const _FlyBody({
    required this.xp,
    required this.coins,
    required this.xpLabel,
    required this.coinLabel,
    required this.onDone,
  });

  final int xp;
  final int coins;
  final String xpLabel;
  final String coinLabel;
  final VoidCallback onDone;

  @override
  State<_FlyBody> createState() => _FlyBodyState();
}

class _FlyBodyState extends State<_FlyBody> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = _c.value;
          // Ko'tarilish sekinlashib boradi (easeOut) — havoga otilgan
          final dy = -64 * Curves.easeOutCubic.transform(t);
          final opacity = t < 0.12
              ? t / 0.12
              : (t > 0.55 ? 1 - (t - 0.55) / 0.45 : 1.0);
          // Kichik "sakrash": 1.0 -> 1.12 -> 1.0
          final scale = 1 + 0.12 * math.sin(math.pi * math.min(t * 2.2, 1.0));
          return Transform.translate(
            offset: Offset(0, dy),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(scale: scale, child: child),
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.xp > 0) RewardChip.xp('+${widget.xp} ${widget.xpLabel}'),
            if (widget.xp > 0 && widget.coins > 0) const SizedBox(width: 6),
            if (widget.coins > 0)
              RewardChip.coin('+${widget.coins} ${widget.coinLabel}'),
          ]),
        ),
      ),
    );
  }
}
