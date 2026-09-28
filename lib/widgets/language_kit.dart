import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../mascot/mascot.dart';
import '../theme/level_palette.dart';
import '../theme/spacing.dart';

/// Til bo'limining UMUMIY qismlari.
///
/// NEGA BIR JOYDA. Ilgari har bir ekran o'z chipini, o'z kartasini va o'z
/// bo'sh holatini yasardi — natijada bo'lim ilovaning qolgan qismidan
/// ajralib turardi va ichida ham bir-biriga o'xshamasdi. Bu yerdagi
/// qismlar HAMMA til ekranlarida ishlatiladi.

// --------------------------------------------------------------------------- //
//  Kenglik                                                                     //
// --------------------------------------------------------------------------- //
/// Matn 720 px dan keng bo'lsa o'qish qiyinlashadi (satr juda uzun).
/// Katta ekranda kontent markazda, shu kenglikda qoladi.
const double kContentMaxWidth = 720;

class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth ?? kContentMaxWidth),
          child: child,
        ),
      );
}

// --------------------------------------------------------------------------- //
//  Daraja belgisi                                                              //
// --------------------------------------------------------------------------- //
class LevelChip extends StatelessWidget {
  const LevelChip(this.level, {super.key, this.compact = false});

  final String level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = LevelPalette.color(level, Theme.of(context).brightness);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Spacing.sm : Spacing.ms,
        vertical: compact ? 2 : Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        level,
        style: (compact
                ? Theme.of(context).textTheme.labelSmall
                : Theme.of(context).textTheme.labelMedium)
            ?.copyWith(color: c, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Ro'yxatdagi daraja belgisi — yumaloq kvadrat, ichida "A1".
///
/// Rangli NUQTA o'rniga yozuv: rang o'zi yetarli emas (rangni ajrata
/// olmaydigan o'quvchi bor, va olti daraja olti rang — yodlab bo'lmaydi).
/// Yozuv + rang birga ishlaydi.
class LevelBadge extends StatelessWidget {
  const LevelBadge(this.level, {super.key, this.size = 36});

  final String level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = LevelPalette.color(level, Theme.of(context).brightness);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        level,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: c, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

/// Ro'yxatdagi kichik nuqta — matn o'rnini egallamasdan darajani beradi.
class LevelDot extends StatelessWidget {
  const LevelDot(this.level, {super.key, this.size = 10});

  final String level;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: LevelPalette.color(level, Theme.of(context).brightness),
          shape: BoxShape.circle,
        ),
      );
}

// --------------------------------------------------------------------------- //
//  Statistika katakchasi                                                       //
// --------------------------------------------------------------------------- //
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: Spacing.md, horizontal: Spacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const Gap.xs(),
          Text(value,
              style: t.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700, color: color)),
          Text(label,
              style: t.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  Mavzu qatori                                                                //
// --------------------------------------------------------------------------- //
enum TopicStatus { notStarted, inProgress, done }

/// Mavzu qatori — HOLAT BELGISI bilan, radio doira bilan emas.
///
/// Radio doira "tanlang" degan ma'noni beradi va o'quvchi bittasini
/// tanlashi kerakdek tuyuladi. Bu yerda esa holat KO'RSATILADI: hali
/// boshlanmagan / davom etmoqda / tugagan.
class TopicTile extends StatelessWidget {
  const TopicTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.status,
    required this.progress,
    required this.onTap,
    this.level,
  });

  final String title;

  /// Asl grammatik nom (ingliz tilida) — kichik va kulrang. O'chirilmaydi:
  /// darslikda va imtihonda aynan shu nom uchraydi.
  final String? subtitle;

  final String meta;
  final TopicStatus status;

  /// 0..1 — `inProgress` holatida halqa shuni ko'rsatadi.
  final double progress;

  final String? level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = level == null
        ? cs.primary
        : LevelPalette.color(level, theme.brightness);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        // 48 px tegish maydoni — vertikal to'ldirish shuni ta'minlaydi.
        padding: const EdgeInsets.symmetric(
            vertical: Spacing.ms, horizontal: Spacing.sm),
        child: Row(
          children: [
            _StatusMark(status: status, progress: progress, color: accent),
            const Gap.ms(),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if ((subtitle ?? '').isNotEmpty)
                    Text(subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(meta, style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            const Gap.sm(),
            if (level != null) LevelChip(level!, compact: true),
            const Gap.xs(),
            Icon(Icons.chevron_right, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

class _StatusMark extends StatelessWidget {
  const _StatusMark(
      {required this.status, required this.progress, required this.color});

  final TopicStatus status;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 30,
      height: 30,
      child: switch (status) {
        TopicStatus.done => Container(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(Icons.check, size: 18, color: cs.onPrimary),
          ),
        TopicStatus.inProgress => Stack(
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress.clamp(0, 1)),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOut,
                builder: (_, v, __) => SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    value: v,
                    strokeWidth: 3,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.18),
                  ),
                ),
              ),
            ],
          ),
        TopicStatus.notStarted => Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.outlineVariant, width: 2),
            ),
          ),
      },
    );
  }
}

// --------------------------------------------------------------------------- //
//  Daraja chizig'i                                                             //
// --------------------------------------------------------------------------- //
class LevelProgressBar extends StatelessWidget {
  const LevelProgressBar({
    super.key,
    required this.level,
    required this.done,
    required this.total,
  });

  final String level;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = LevelPalette.color(level, theme.brightness);
    final value = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          SizedBox(width: 30, child: LevelChip(level, compact: true)),
          const Gap.sm(),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              builder: (_, v, __) => ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  color: c,
                  backgroundColor: c.withValues(alpha: 0.16),
                ),
              ),
            ),
          ),
          const Gap.sm(),
          Text('$done/$total', style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  Boyqush bilan bo'sh holat                                                   //
// --------------------------------------------------------------------------- //
class OwlEmptyState extends StatelessWidget {
  const OwlEmptyState({
    super.key,
    required this.state,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.size = 120,
  });

  final OwlState state;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BreathingOwl(state: state, size: size),
          const Gap.md(),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          if ((message ?? '').isNotEmpty) ...[
            const Gap.sm(),
            Text(message!,
                style: t.bodyMedium, textAlign: TextAlign.center),
          ],
          if (actionLabel != null && onAction != null) ...[
            const Gap.md(),
            PrimaryButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

/// Bitta rasmdan jonli his: sekin "nafas olish".
///
/// Boyqushning har bir kayfiyati uchun alohida animatsiya yo'q, lekin
/// mutlaqo qimirlamaydigan rasm o'lik ko'rinadi. Harakat juda kichik —
/// diqqatni tortmaydi, shunchaki tirik qiladi.
class BreathingOwl extends StatefulWidget {
  const BreathingOwl({super.key, required this.state, this.size = 120});

  final OwlState state;
  final double size;

  @override
  State<BreathingOwl> createState() => _BreathingOwlState();
}

class _BreathingOwlState extends State<BreathingOwl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    // Harakatni kamaytirish yoqilgan bo'lsa — umuman jonlantirmaymiz.
    if (!WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
        .disableAnimations) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.scale(
          scale: 1 + 0.025 * Curves.easeInOut.transform(_c.value),
          child: child,
        ),
        child: OwlMascot(widget.state.mood, size: widget.size),
      );
}

// --------------------------------------------------------------------------- //
//  Asosiy tugma                                                                //
// --------------------------------------------------------------------------- //
/// Bosilganda ozgina kichrayadi — tegish sezilishi uchun.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final child = FilledButton(
      onPressed: enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onPressed!();
            }
          : null,
      style: FilledButton.styleFrom(
        // 48 px — barmoq uchun eng kichik ishonchli maydon.
        minimumSize: Size(widget.expand ? double.infinity : 0, 52),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
        textStyle: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      child: widget.icon == null
          ? Text(widget.label)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 20),
                const Gap.sm(),
                Flexible(
                    child: Text(widget.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );

    return Listener(
      onPointerDown: enabled ? (_) => setState(() => _down = true) : null,
      onPointerUp: enabled ? (_) => setState(() => _down = false) : null,
      onPointerCancel: enabled ? (_) => setState(() => _down = false) : null,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}
