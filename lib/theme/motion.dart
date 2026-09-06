import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

///
///
///
///
///
///
/// `flutter_animate` vidjet qurilganda ishga tushadi. `IndexedStack` da tab
abstract final class Motion {
  static const fast = Duration(milliseconds: 160);

  static const normal = Duration(milliseconds: 240);

  static const slow = Duration(milliseconds: 320);

  static const stagger = Duration(milliseconds: 40);

  static const enter = Curves.easeOutCubic;

  static const interactive = Curves.easeOut;

  static const emphasized = Curves.easeInOutCubicEmphasized;
}

extension MotionEffects on Widget {
  Widget enterFade({Duration? delay}) => animate(delay: delay)
      .fadeIn(duration: Motion.slow, curve: Motion.enter)
      .moveY(begin: 8, end: 0, duration: Motion.slow, curve: Motion.enter);

  Widget enterStaggered(int index, {int maxIndex = 8}) => enterFade(
        delay: Motion.stagger * (index > maxIndex ? maxIndex : index),
      );
}
