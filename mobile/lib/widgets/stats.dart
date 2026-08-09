import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/elevation.dart';
import '../theme/motion.dart';
import '../theme/spacing.dart';

/// Bo'lim sarlavhasi + ixtiyoriy "hammasi" harakati.
///
/// Nega alohida vidjet: sarlavhalar har ekranda qo'lda yozilganda o'lcham va
/// masofa har joyda biroz boshqacha bo'lib qoladi — ko'z buni darrov sezadi.
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

/// Dashboard uchun statistika kartochkasi.
///
/// Ilgari raqamlar quruq matn bo'lib turardi ("Daraja 12"). Bu ko'rinishda
/// raqam asosiy element, yorliq ikkilamchi, `delta` ("+32 XP bugun") esa
/// harakat hissini beradi — o'quvchi bugun nimadir qilganini ko'radi.
///
/// ## 2026-08-06 o'zgarishlari
///
/// * **Yumshoq soya** — karta oq fondan ajralib turadi (ilgari faqat
///   `hairline` chegara bor edi va lentadagi kartalar bitta kulrang
///   to'rtburchakka qo'shilib ketardi).
/// * **Rangli ikonka foni** — har ko'rsatkichning o'z rangi bor: XP/Daraja/
///   Tanga sariq-apelsin, Seriya qizil (olov), O'rin neytral. Rang ma'no
///   tashiydi, bezak emas: ko'z kartani o'qimasdan ham tanib oladi.
/// * **Raqam sanaladi** — 0 dan haqiqiy qiymatgacha 700 ms. Bu "erishilgan
///   natija" hissini beradi; statik raqam shunchaki ma'lumot.
/// * **Progress chizig'i 4 px** va u ham animatsiya bilan to'ladi.
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

  /// Material ikonkasi o'rniga ixtiyoriy vidjet — XP oltiburchagi yoki
  /// noncoin kristali (`widgets/currency.dart`).
  ///
  /// Nega kerak: valyuta belgisi brendning bir qismi. `Icons.monetization_on`
  /// bilan u har qanday boshqa ilovaga o'xshab qoladi va foydalanuvchi XP
  /// bilan noncoinni ikkita "raqam" deb o'qiydi. O'z belgisi bo'lsa — ikkita
  /// TURLI narsa ekani bir qarashda ko'rinadi.
  final Widget? iconWidget;

  /// Ko'rsatiladigan matn. [count] berilsa faqat zaxira sifatida ishlatiladi
  /// (masalan, raqam bo'lmagan "—" holati).
  final String value;
  final String label;

  /// "+32 XP" kabi bugungi o'zgarish. Null bo'lsa ko'rsatilmaydi.
  final String? delta;
  final Color? accent;

  /// 0..1. Berilsa kartochka pastida ingichka chiziq chiqadi.
  final double? progress;

  /// Berilsa raqam 0 dan shu qiymatgacha sanaladi. Formatlash [value] dagi
  /// ko'rinishga mos bo'lishi uchun bo'luvchi bo'shliq qo'yiladi.
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
              // Ikkala variant ham AYNAN 18×18 — aks holda lentadagi
              // kartochkalarda ikonka qutisi turli o'lchamda bo'lib,
              // ostidagi raqamlar bir chiziqda turmasdi.
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
            // Ingichka (4 px) va animatsiya bilan to'ladigan chiziq. Qalin
            // chiziq kartochkadagi raqamdan e'tiborni o'g'irlaydi.
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

/// Raqamni 0 dan sanab chiqadi. [count] null bo'lsa oddiy matn.
///
/// Nega `TweenAnimationBuilder`: u `AnimationController` talab qilmaydi va
/// qiymat o'zgarganda (mashqdan keyin XP oshganda) ESKI qiymatdan yangisiga
/// silliq o'tadi — ya'ni "0 dan qayta sanash" bo'lmaydi.
class _Value extends StatelessWidget {
  const _Value({required this.count, required this.fallback, this.style});

  final int? count;
  final String fallback;
  final TextStyle? style;

  /// 12 345 — mingliklar orasida ingichka bo'shliq. Vergul o'zbek tilida
  /// o'nlik ajratgich, shuning uchun mingliklar uchun ishlatilmaydi.
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
/// Chiziqli progressdan farqi: halqa kichik joyda ham o'qiladi va kartochka
/// burchagida "belgi" bo'lib turadi — Duolingo/Brilliant uslubi.
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
