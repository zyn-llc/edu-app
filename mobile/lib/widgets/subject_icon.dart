import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/subject_palette.dart';

/// Fanning "tirik" ikonkasi — sekin, uzluksiz mikro-animatsiya.
///
///
/// harakatlar juda oddiy — aylanish, tebranish, pulsatsiya — ularni
///
///
///
///
///
///
class AnimatedSubjectIcon extends StatefulWidget {
  const AnimatedSubjectIcon({
    super.key,
    required this.code,
    required this.color,
    this.size = 26,
    this.active = false,
  });

  final String code;
  final Color color;
  final double size;

  final bool active;

  @override
  State<AnimatedSubjectIcon> createState() => _AnimatedSubjectIconState();
}

class _AnimatedSubjectIconState extends State<AnimatedSubjectIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _motionFor(widget.code).period,
  );

  bool _running = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      if (_running) {
        _c.stop();
        _c.value = 0;
        _running = false;
      }
      return;
    }
    if (!_running) {
      _c.repeat();
      _running = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = _motionFor(widget.code);
    final glyph = Icon(
      SubjectPalette.of(widget.code).icon,
      color: widget.color,
      size: widget.size,
    );

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        child: glyph,
        builder: (context, child) => motion.build(
          context,
          _c.value,
          widget.active,
          widget.color,
          widget.size,
          child!,
        ),
      ),
    );
  }
}

class _SubjectMotion {
  const _SubjectMotion(this.period, this.build);

  final Duration period;

  final Widget Function(
    BuildContext context,
    double t,
    bool active,
    Color color,
    double size,
    Widget child,
  ) build;
}

_SubjectMotion _motionFor(String code) => _motions[code] ?? _breathe;

final _spin = _SubjectMotion(
  const Duration(seconds: 24),
  (context, t, active, color, size, child) => Transform.rotate(
    angle: 2 * math.pi * t * (active ? 2.5 : 1),
    child: child,
  ),
);

final _swing = _SubjectMotion(
  const Duration(milliseconds: 5200),
  (context, t, active, color, size, child) => Transform.rotate(
    angle: math.sin(2 * math.pi * t) * (active ? 0.16 : 0.075),
    // Pastki chetdan tebranadi — barg bandidan osilgandek.
    alignment: Alignment.bottomCenter,
    child: child,
  ),
);

final _wave = _SubjectMotion(
  const Duration(milliseconds: 4400),
  (context, t, active, color, size, child) {
    final phase = math.sin(2 * math.pi * t);
    final k = active ? 1.8 : 1.0;
    return Transform(
      alignment: Alignment.centerLeft, // bayroq ustunga mahkam
      // (`deprecated_member_use`). `scaleByDouble` to'rtta argument oladi —
      transform: Matrix4.identity()
        ..scaleByDouble(1 - 0.06 * k * phase.abs(), 1.0, 1.0, 1.0)
        ..setEntry(1, 0, 0.05 * k * phase),
      child: child,
    );
  },
);

///
/// kutilmagan bir "chertish" esa yoqadi.
final _pop = _SubjectMotion(
  const Duration(milliseconds: 7000),
  (context, t, active, color, size, child) {
    const start = 0.85;
    if (t < start) return child;
    final u = (t - start) / (1 - start); // 0..1
    final s = 1 - 0.14 * math.sin(math.pi * u);
    return Transform.scale(scale: s, child: child);
  },
);

/// Orbitadagi elektron — fizika.
///
final _orbit = _SubjectMotion(
  const Duration(milliseconds: 6000),
  (context, t, active, color, size, child) => Stack(
    alignment: Alignment.center,
    children: [
      child,
      Positioned.fill(
        child: CustomPaint(painter: _OrbitPainter(t, color)),
      ),
    ],
  ),
);

/// Ko'tarilayotgan pufakchalar — kimyo.
final _bubbles = _SubjectMotion(
  const Duration(milliseconds: 5000),
  (context, t, active, color, size, child) => Stack(
    alignment: Alignment.center,
    children: [
      child,
      Positioned.fill(
        child: CustomPaint(painter: _BubblePainter(t, color)),
      ),
    ],
  ),
);

/// Varaq o'girilishi — kitob (ona tili, adabiyot).
///
final _flip = _SubjectMotion(
  const Duration(milliseconds: 6500),
  (context, t, active, color, size, child) {
    const start = 0.75;
    if (t < start) return child;
    final u = (t - start) / (1 - start);
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..scaleByDouble(1 - 0.30 * math.sin(math.pi * u), 1.0, 1.0, 1.0),
      child: child,
    );
  },
);

/// Bolg'acha urishi — huquq.
final _tap = _SubjectMotion(
  const Duration(milliseconds: 6800),
  (context, t, active, color, size, child) {
    const start = 0.80;
    if (t < start) return child;
    final u = (t - start) / (1 - start);
    // Ikki marta uradi: 0 -> -18° -> 0 -> -12° -> 0
    final angle = -0.32 * math.sin(2 * math.pi * u).abs();
    return Transform.rotate(
      angle: angle,
      alignment: Alignment.bottomRight,
      child: child,
    );
  },
);

final _breathe = _SubjectMotion(
  const Duration(milliseconds: 8000),
  (context, t, active, color, size, child) => Transform.scale(
    scale: 1 + 0.035 * math.sin(2 * math.pi * t),
    child: child,
  ),
);

final _step = _SubjectMotion(
  const Duration(milliseconds: 9000),
  (context, t, active, color, size, child) {
    final seg = (t * 3).floor(); // 0,1,2
    final u = (t * 3) - seg;
    final eased = u < 0.75 ? 0.0 : Curves.easeInOutCubic.transform((u - 0.75) / 0.25);
    final angle = (seg + eased) * (2 * math.pi / 3);
    return Transform.rotate(angle: angle, child: child);
  },
);

final _motions = <String, _SubjectMotion>{
  'geografiya': _spin,
  'biologiya': _swing,
  'ozbekiston_tarixi': _wave,
  'jahon_tarixi': _wave,
  'matematika': _pop,
  'geometriya': _step,
  'fizika': _orbit,
  'kimyo': _bubbles,
  'ona_tili': _flip,
  'adabiyot': _flip,
  'ingliz_tili': _flip,
  'huquq': _tap,
};

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rx = size.width * 0.46;
    final ry = size.height * 0.22;
    final a = 2 * math.pi * t;

    final path = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.5);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), path);

    // Elektron. Orbitaning "orqa" yarmida kichrayadi — chuqurlik hissi.
    final p = Offset(rx * math.cos(a), ry * math.sin(a));
    final back = math.sin(a) < 0;
    canvas.drawCircle(
      p,
      back ? 1.6 : 2.4,
      Paint()..color = color.withValues(alpha: back ? 0.45 : 1.0),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.t != t || old.color != color;
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.t, this.color);

  final double t;
  final Color color;

  static const _phases = [0.0, 0.37, 0.68];
  static const _dx = [-0.22, 0.06, 0.26];
  static const _r = [1.6, 2.4, 1.9];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _phases.length; i++) {
      final u = (t + _phases[i]) % 1.0;
      final alpha = math.sin(math.pi * u);
      canvas.drawCircle(
        Offset(size.width * (0.5 + _dx[i]), size.height * (0.92 - 0.7 * u)),
        _r[i],
        Paint()..color = color.withValues(alpha: 0.55 * alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.t != t || old.color != color;
}
