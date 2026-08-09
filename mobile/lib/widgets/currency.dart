import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// Ilova iqtisodiyotining vizual tili: **noncoin** va **XP**.
///
/// ## Nega tanga emas
///
/// Oltin tanga (🪙) — dunyodagi har uchinchi ilovada bor. U hech narsa
/// anglatmaydi va brendga tegishli emas: skrinshotda ko'rgan odam qaysi
/// ilova ekanini ayta olmaydi. **noncoin** esa nomi ham, shakli ham
/// Topag'onniki: qirrali kristall, ikki rangli, 24 px da ham 128 px da ham
/// tanib olinadi.
///
/// ## Backend O'ZGARMAYDI
///
/// Serverda maydon nomi baribir `coins` bo'lib qoladi (`/v1/me`,
/// `GradeResult.coins_awarded`, `challenges.stake`). Bu ATAYLAB: valyuta
/// nomi — mahsulot qarori, ma'lumot sxemasi emas. Migratsiya, API versiyasi
/// va mavjud hisoblarni buzmasdan nomni istalgan vaqtda yana o'zgartirish
/// mumkin. Faqat UI qatlami «noncoin» deydi.
///
/// ## Ikki alohida valyuta
///
/// * **XP** — o'sish. Kamaymaydi, sarflanmaydi, darajani beradi.
/// * **noncoin** — sarflanadigan resurs: bellashuv garovi, kelajakda
///   avatar bezaklari, qiyin savolni o'tkazib yuborish.
///
/// Ikkalasining rangi ham FARQ QILADI (XP — apelsin/energiya, noncoin —
/// binafsha-siyoh/qimmatbaho), aks holda foydalanuvchi ikkita raqamni bitta
/// narsa deb o'qiydi.
abstract final class Rewards {
  /// XP rangi — brend apelsini. "Energiya" ma'nosi.
  static const xp = Color(0xFFF8721C);

  /// noncoin rangi — sovuq binafsha. Apelsindan aniq ajraladi va
  /// "qimmatbaho tosh" assotsiatsiyasini beradi.
  static const coinDark = Color(0xFF6A53C7);

  /// Kristallning yorug' qirralari.
  static const coinLight = Color(0xFF9C86F0);
}

/// noncoin belgisi — qirrali kristall.
///
/// Shakl: olti burchak, ichida yuqoridan tushgan yorug'lik chizig'i. Ikki
/// rang — bittasi bilan u yassi dog' bo'lib qolardi.
///
/// [sparkle] `true` bo'lsa har ~5 soniyada ustidan yorug'lik yaltirab
/// o'tadi. Bu faqat KATTA ko'rinishlarda (stat kartochkasi) yoqiladi:
/// ro'yxatdagi 20 ta yaltiragan ikonka — diskoteka.
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
    // Bu "tosh kesilgan" shakl — doira "tanga" bo'lib qolardi.
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

    // Ichki qirra — yuqori uchdan yon burchaklarga tushadigan ikki chiziq.
    // Aynan shu ikki chiziq shaklni "hajmli" qiladi.
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

    // Yaltirash: yupqa oq chiziq shakl ustidan diagonal o'tadi. Siklning
    // faqat 18% ida ko'rinadi — qolgan vaqtda tosh tinch turadi.
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
/// Nega ramka: yalang'och `Icons.bolt` matn yonida shunchaki ikonka bo'lib
/// qoladi. Ramka uni BELGIGA aylantiradi — noncoin kristalli bilan bir
/// oilada ko'rinadi va ikkalasi birga "iqtisodiyot tili" bo'ladi.
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

/// «⚡ 12 XP» / «✦ 480 noncoin» ko'rinishidagi chip.
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

/// Mukofot yuqoriga uchib ketadi: «+12 XP ⚡» paydo bo'ladi, ko'tariladi,
/// so'nadi.
///
/// ## Nega bu kerak
///
/// Raqamning jimgina o'zgarishi — hisobot. Uchib ketgan «+12» — voqea.
/// O'yin dizaynida bu «juicy feedback» deb ataladi va u yagona narsa
/// bo'lib, foydalanuvchini keyingi savolga majburlamasdan undaydi.
///
/// ## Nega Overlay
///
/// Animatsiya `Overlay` da ijro etiladi, ya'ni u karta chegarasidan
/// TASHQARIGA chiqib keta oladi (`Stack` ichida `clipBehavior` uni kesib
/// tashlagan bo'lardi) va layoutga umuman ta'sir qilmaydi — sahifa
/// sakramaydi.
///
/// ## Ishlatish
///
/// ```dart
/// RewardFly.show(context, xp: 10, coins: 2);
/// ```
///
/// `context` — mukofot QAYERDAN uchishini belgilaydi (odatda javob
/// tugmasi yoki fikr-mulohaza bloki).
abstract final class RewardFly {
  static void show(
    BuildContext context, {
    int xp = 0,
    int coins = 0,
    String xpLabel = 'XP',
    String coinLabel = 'noncoin',
  }) {
    if (xp <= 0 && coins <= 0) return;
    // OS darajasida animatsiya o'chirilgan bo'lsa — hech narsa qilmaymiz.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final origin = box.localToGlobal(Offset(box.size.width / 2, 0));

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        // Chip kengligi oldindan noma'lum, shuning uchun markazga
        // `FractionalTranslation` bilan keltiramiz.
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
              // `mounted` tekshiruvi shart: ekran animatsiya tugashidan
              // oldin yopilsa entry allaqachon olib tashlangan bo'ladi.
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
          // narsa kabi. Chiziqli harakat "lift" bo'lib ko'rinardi.
          final dy = -64 * Curves.easeOutCubic.transform(t);
          // Boshida tez paydo bo'ladi, oxirgi 45% da so'nadi.
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
