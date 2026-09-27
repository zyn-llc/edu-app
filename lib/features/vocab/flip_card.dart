import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Kartochkaning aylanishi — old tomondan orqasiga.
///
/// NEGA HAQIQIY 3D AYLANISH, oddiy fade emas. Kartochka metaforasi jismoniy:
/// o'quvchi so'zni ko'radi, o'ylaydi, keyin KARTOCHKANI AG'DARADI. Fade
/// bilan almashtirish "javob paydo bo'ldi" degan his beradi, ag'darish esa
/// "men tekshirdim" degan his — ikkinchisi mashqning mohiyatiga mos.
///
/// `Transform` `rotationY` bilan, burchak `pi/2` dan o'tganda tomon
/// almashadi. Orqa tomon yana bir marta AYLANTIRILADI, aks holda matn
/// ko'zguda aks etgandek teskari chiqadi — bu eng ko'p uchraydigan xato.
class FlipCard extends StatefulWidget {
  const FlipCard({
    super.key,
    required this.showBack,
    required this.front,
    required this.back,
    this.duration = const Duration(milliseconds: 420),
  });

  final bool showBack;
  final Widget front;
  final Widget back;
  final Duration duration;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.showBack ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant FlipCard old) {
    super.didUpdateWidget(old);
    if (widget.showBack != old.showBack) {
      widget.showBack ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // easeInOut — ag'darish o'rtasida sekinlashadi, ya'ni harakat
        // og'irlikka ega bo'lib tuyuladi.
        final t = Curves.easeInOut.transform(_c.value);
        final angle = t * math.pi;
        final showingBack = t >= 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            // Perspektiva: usiz aylanish shunchaki gorizontal siqilish
            // bo'lib ko'rinadi.
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: showingBack
              ? Transform(
                  alignment: Alignment.center,
                  // Orqa tomonni tiklash — bo'lmasa matn teskari.
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: widget.back,
                )
              : widget.front,
        );
      },
    );
  }
}
