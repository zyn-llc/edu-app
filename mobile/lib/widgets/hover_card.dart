import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/elevation.dart';
import '../theme/motion.dart';
import '../theme/spacing.dart';

/// Bosiladigan karta — sichqoncha ostida ko'tariladi, barmoq ostida bosiladi.
///
/// ## Nega kerak
///
/// Hover'siz interfeys web va desktopda o'lik ko'rinadi: foydalanuvchi qaysi
/// element bosiladiganini faqat bosib ko'rib biladi.
///
/// ## 2026-08-06: harakat kuchaytirildi
///
/// Ilgari hover'da soya `blurRadius: 18`, shaffofligi 10% edi — deyarli
/// ko'rinmasdi va sinovchilar kartalar bosiladiganini payqamasdi. Endi:
///
/// | Holat        | Siljish  | Soya                 | Chegara               |
/// |--------------|----------|----------------------|-----------------------|
/// | tinch        | 0        | `Shadows.card` (4%)  | hairline              |
/// | hover        | −4 px    | `Shadows.lift` (12%) | aksent, 1.5 px        |
/// | bosilgan     | +1 px    | `Shadows.card`       | aksent                |
/// | o'chirilgan  | 0        | yo'q                 | hairline, 45% shaffof |
///
/// Ko'tarilish `scale` bilan emas, `translateY` bilan: masshtablash ichkaridagi
/// matnni bir zumda xiralashtiradi (qayta rasterizatsiya), siljish esa yo'q.
///
/// Telefonda hover yo'q, shuning uchun bosish holati alohida kuzatiladi.
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

  /// Ichki kontent hover holatini BILISHI kerak bo'lganda — masalan, fan
  /// kartasidagi ikonka hover'da tezroq aylanadi, strelka o'ngga suriladi.
  ///
  /// Nega alohida `builder`, `InheritedWidget` emas: hover har piksel
  /// harakatida emas, faqat kirish/chiqishda o'zgaradi (ikki `setState`),
  /// ya'ni obuna mexanizmi ortiqcha murakkablik bo'lardi.
  final Widget Function(BuildContext context, bool hovered)? contentBuilder;

  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// Hover paytida chegara shu rangga o'tadi. Berilmasa `primary`.
  final Color? accent;

  /// Tanlangan holat — hover'dan qat'i nazar chegara rangli turadi.
  final bool selected;

  /// `false` bo'lsa karta vizual ravishda "o'chgan": xiralashadi, soya
  /// yo'qoladi, kursor o'zgarmaydi va `onTap` chaqirilmaydi.
  ///
  /// Nega alohida bayroq (`onTap == null` yetarli emas): ba'zi kartalar
  /// bosilmaydi, lekin o'chirilgan ham emas (masalan, statistika kartasi) —
  /// ular xiralashmasligi kerak.
  final bool enabled;

  /// Karta foni. Berilmasa `surface` (yorug' temada toza oq).
  final Color? background;

  /// Hover'da neytral soyaga QO'SHIMCHA ravishda aksent rangli porlash
  /// qo'shiladi.
  ///
  /// Nega: neytral soya kartani ko'taradi, lekin "bu element sizga javob
  /// beryapti" degan ma'no bermaydi — u har qanday qatlamda bir xil.
  /// Rangli porlash esa kartani AYNAN shu fanning/harakatning rangiga
  /// bog'laydi. Statistika kabi bosilmaydigan kartalarda `false` qiling.
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
    // qatlam bo'lib qo'shiladi (almashtirmaydi): neytral soya chuqurlikni,
    // rangli soya esa "tirik" hissini beradi. Faqat rangli soya qolsa karta
    // fonda suzayotgandek ko'rinadi.
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

    // O'chirilgan karta 45% shaffof: "bor, lekin hozir mumkin emas" degan
    // ma'no. Butunlay yashirish yomonroq — foydalanuvchi nima yo'qolganini
    // bilmaydi ("Geometriya qani?").
    final body = AnimatedOpacity(
      duration: Motion.fast,
      // 0.45 EMAS. O'sha darajada karta ichidagi matn kontrasti WCAG AA dan
      // pastga tushardi va "tayyor emas" o'rniga "buzuq" degan taassurot
      // berardi. 0.62 — farq baribir bir qarashda seziladi, lekin matn
      // o'qiladigan bo'lib qoladi.
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

/// Apelsin porlashli asosiy harakat tugmasi.
///
/// `FloatingActionButton` ning o'z `elevation` i neytral kulrang soya beradi —
/// u oq fonda deyarli ko'rinmaydi va tugma sahifaga "yopishib" qoladi.
/// Rangli soya esa tugmani ko'taradi va uni sahifadagi asosiy harakat qilib
/// ko'rsatadi.
/// ## 2026-08-07: porlash "nafas oladi"
///
/// Porlash kuchi 3.6 soniyalik siklda 0.28 ↔ 0.44 orasida o'zgaradi.
///
/// Nega AYNAN porlash, karta emas: brifda "kartalar nafas olsin" degan
/// taklif bor edi, lekin `scale` bilan pulsatsiya matnni HAR KADRDA qayta
/// rasterizatsiya qiladi va u doimiy xira ko'rinadi (bu `HoverCard` da
/// `scale` o'rniga `translateY` ishlatilishining ham sababi). FAB da esa
/// pulsatsiya faqat SOYAGA tegadi — tugma o'zi va uning matni mutlaqo
/// qimirlamaydi, ya'ni xiralik yo'q, lekin ko'z harakatni ilg'aydi va
/// sahifadagi asosiy harakatni topadi.
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
    // `reverse: true` — 0→1→0. Aks holda har siklning oxirida porlash
    // birdan so'nib, "chirog' o'chdi" degan sakrash bo'lardi.
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
      // FAB `child` da — har kadrda qayta qurilmaydi.
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
