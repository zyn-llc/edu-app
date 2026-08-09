import 'package:flutter/widgets.dart';

/// The EduOwl mascot moods, mapped to the expression sheet you provided.
/// Drop the PNGs (or a Rive file) into assets/mascot/ with these names.
enum OwlMood { happy, thinking, excited, encouraging, wow, tip, achievement, oops }

extension on OwlMood {
  String get asset => 'assets/mascot/owl_$name.png';
}

/// Shows the right owl for the moment:
///   result correct -> excited/wow, streak -> encouraging, empty -> thinking,
///   error -> oops, hint -> tip, badge earned -> achievement.
///
/// Falls back gracefully to [OwlMood.happy] art if a specific pose is missing,
/// so the app never crashes on a not-yet-added asset.
class OwlMascot extends StatelessWidget {
  final OwlMood mood;
  final double size;

  const OwlMascot(this.mood, {super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      mood.asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Image.asset(
        OwlMood.happy.asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
      ),
    );
  }
}
