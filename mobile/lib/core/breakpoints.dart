import 'package:flutter/material.dart';

enum WindowSize {
  compact,
  medium,
  expanded,
  large,
  extraLarge;

  static WindowSize fromWidth(double w) {
    if (w < 600) return WindowSize.compact;
    if (w < 840) return WindowSize.medium;
    if (w < 1200) return WindowSize.expanded;
    if (w < 1600) return WindowSize.large;
    return WindowSize.extraLarge;
  }

  bool get isCompact => this == WindowSize.compact;

  ///
  /// M3 tavsiyasi — rail aynan `medium` dan boshlanadi. Telefon landshaftda
  bool get useRail => this != WindowSize.compact;

  bool get useExtendedRail =>
      this == WindowSize.large || this == WindowSize.extraLarge;

  ///
  /// u kartochkalar gridi. 1100 px 27 dyuymli monitorda (2560 px) ikki yonida
  double get contentMaxWidth => this == WindowSize.extraLarge ? 1440 : 1100;

  int get gridColumns => switch (this) {
        WindowSize.compact => 2,
        WindowSize.medium => 3,
        WindowSize.expanded => 4,
        WindowSize.large => 5,
        WindowSize.extraLarge => 6,
      };
}

extension WindowSizeX on BuildContext {
  /// ochilganda ham (`viewInsets`) butun daraxtni qayta quradi.
  WindowSize get windowSize => WindowSize.fromWidth(MediaQuery.sizeOf(this).width);

  bool get isCompact => windowSize.isCompact;
  bool get useRail => windowSize.useRail;
}

class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;

  final double maxWidth;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
