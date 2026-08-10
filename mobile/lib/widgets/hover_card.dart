import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/elevation.dart';
import '../theme/motion.dart';
import '../theme/spacing.dart';

/// Bosiladigan karta — sichqoncha ostida ko'tariladi, barmoq ostida bosiladi.
///
///
///
/// ## 2026-08-06: harakat kuchaytirildi
///
///
/// |--------------|----------|----------------------|-----------------------|
/// | tinch        | 0        | `Shadows.card` (4%)  | hairline              |
/// | hover        | −4 px    | `Shadows.lift` (12%) | aksent, 1.5 px        |
/// | bosilgan     | +1 px    | `Shadows.card`       | aksent                |
///
///
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    this.child,
    this.contentBuilder,
    this.onTap,
    this.padding = const EdgeInsets.all(Spacing.md),
    this.borderRadius = Radii.cardRadius,
    this.accent,
    this.selected = false,
    this.enabled = true,
    this.background,
    this.glow = true,
  }) : assert(child != null || contentBuilder != null,
            'HoverCard: `child` yoki `contentBuilder` dan biri berilishi shart');

  final Widget? child;

  final Widget Function(BuildContext context, bool hovered)? contentBuilder;

  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  final Color? accent;

  final bool selected;

  final bool enabled;

  final Color? background;

  /// Hover'da neytral soyaga QO'SHIMCHA ravishda aksent rangli porlash
  /// qo'shiladi.
  ///
  final bool glow;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;
  bool _pressed = false;

  bool get _tappable => widget.onTap != null && widget.enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final accent = widget.accent ?? scheme.primary;

    final hovering = _hover && widget.enabled;
    final active = hovering || widget.selected;

    // Siljish: hover'da yuqoriga, bosilganda pastga.
    final dy = !widget.enabled
        ? 0.0
        : _pressed
            ? 1.0
            : (hovering ? -4.0 : 0.0);

    // Hover soyasi = neytral ko'tarilish + aksent porlash. Porlash alohida
    final shadows = !widget.enabled
        ? const <BoxShadow>[]
        : (hovering && !_pressed)
            ? [
                ...Shadows.lift(context),
                if (widget.glow) ...Shadows.glow(accent, opacity: 0.20),
              ]
            : Shadows.card(context);

    final card = AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.interactive,
      transform: Matrix4.translationValues(0, dy, 0),
      transformAlignment: Alignment.center,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.background ?? scheme.surface,
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: active
              ? accent.withValues(alpha: widget.selected ? 1 : 0.5)
              : palette.hairline,
          width: active ? 1.5 : 1,
        ),
        boxShadow: shadows,
      ),
      child: widget.contentBuilder?.call(context, hovering) ?? widget.child,
    );

    // bilmaydi ("Geometriya qani?").
    final body = AnimatedOpacity(
      duration: Motion.fast,
      opacity: widget.enabled ? 1 : 0.62,
      child: card,
    );

    return MouseRegion(
      cursor: _tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: widget.enabled ? (_) => setState(() => _hover = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        onTapDown: _tappable ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _tappable ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _tappable ? () => setState(() => _pressed = false) : null,
        onTap: _tappable ? widget.onTap : null,
        child: body,
      ),
    );
  }
}

///
/// ## 2026-08-07: porlash "nafas oladi"
///
///
class GlowFab extends StatefulWidget {
  const GlowFab({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final Widget label;

  @override
  State<GlowFab> createState() => _GlowFabState();
}

class _GlowFabState extends State<GlowFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      if (_c.isAnimating) _c.stop();
      _c.value = 0.5;
      return;
    }
    if (!_c.isAnimating) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fab = FloatingActionButton.extended(
      onPressed: widget.onPressed,
      icon: widget.icon,
      label: widget.label,
    );
    return AnimatedBuilder(
      animation: _c,
      child: fab,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: Radii.buttonRadius,
          boxShadow: Shadows.glow(
            scheme.primary,
            opacity: 0.28 + 0.16 * _c.value,
          ),
        ),
        child: child,
      ),
    );
  }
}
