import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart' show AppPalette;
import '../../theme/motion.dart';
import '../../theme/spacing.dart';
import '../../theme/subject_palette.dart';
import '../../widgets/currency.dart';
import '../../widgets/hover_card.dart';
import '../../widgets/stats.dart';
import '../../widgets/subject_icon.dart';
import 'subjects.dart';

/// Bitta to'g'ri javob uchun XP.
///
/// Serverdagi `settings.xp_per_point = 10` ning KO'ZGUSI (`score` bir to'g'ri
/// javob uchun 1). Bu yerda takrorlanishining sababi: kartada mukofotni
/// KO'RSATISH uchun javob yuborilishini kutib bo'lmaydi — o'quvchi mashqni
/// boshlashdan OLDIN nima olishini bilishi kerak.
///
/// DIQQAT: `backend/app/core/config.py` dagi `xp_per_point` o'zgarsa, shu
/// yerni ham yangilang. Aks holda karta va'da qilgan raqam bilan mashqdan
/// keyingi chip mos kelmaydi — bu eng yomon xato turi, chunki foydalanuvchi
/// aldangan deb his qiladi.
const int kXpPerCorrect = 10;

/// Fan kartochkasi.
///
/// ## Nima uchun karta shunchaki tugma emas
///
/// Ilgari kartada ikonka, nom va «Boshlash» bor edi — ya'ni u tugma edi.
/// Endi u o'quvchining shu fandagi HOLATINI ko'rsatadi: qancha yechgan,
/// qanday aniqlik bilan, qachon oxirgi marta, va keyingi savol uchun nima
/// beriladi. Foydalanuvchi kartani o'qib, bosishdan oldin qaror qabul
/// qiladi.
///
/// ## 2026-08-07 dizayn yangilanishi
///
/// | Element              | Nega                                              |
/// |----------------------|---------------------------------------------------|
/// | Animatsiyali ikonka  | Ekran tirik ekanini bildiradi; hover'da tezlashadi |
/// | Aniqlik halqasi      | Foizni bir qarashda beradi, raqamdan tez o'qiladi  |
/// | XP chipi             | Mukofot mashqdan OLDIN ko'rinadi — motivatsiya     |
/// | Seriya chipi         | Yo'qotish qo'rquvi: «4 kun» ni uzishni xohlamaydi  |
/// | O'zgaruvchan CTA     | «Boshlash» har kartada takrorlansa shovqin bo'ladi |
/// | Strelka siljishi     | Hover'da harakat — karta javob berayotgani bilinadi|
class SubjectCard extends StatelessWidget {
  const SubjectCard({
    super.key,
    required this.subject,
    required this.onTap,
    this.streakDays = 0,
  });

  final Subject subject;
  final VoidCallback onTap;

  /// Foydalanuvchining UMUMIY seriyasi (`/v1/me` dan). Fanga xos seriya
  /// serverda yo'q, shuning uchun chip faqat BOSHLANGAN fanlarda va faqat
  /// bugun mashq qilinmagan bo'lsa ko'rsatiladi — «bugun uzilib qolmasin»
  /// degan ma'noda. Har kartada takrorlansa u ma'nosiz bezakka aylanadi.
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final palette = theme.extension<AppPalette>()!;
    final style = SubjectPalette.of(subject.code);
    final accent = style.color(theme.brightness);

    // Savoli yo'q fan (2026-08-09 holatiga ko'ra — geometriya).
    // Karta ko'rinadi, lekin bosilmaydi va sababi ochiq yoziladi. Bo'sh
    // ekranga olib boradigan bosiladigan karta — eng yomon variant:
    // foydalanuvchi ilova buzuq deb o'ylaydi.
    final empty = subject.questionCount <= 0;

    return HoverCard(
      onTap: empty ? null : onTap,
      // `enabled: false` kartani xiralashtiradi va soyasini oladi —
      // "Geometriya" boshqalardan bir qarashda ajralib turadi.
      enabled: !empty,
      accent: accent,
      padding: const EdgeInsets.all(Spacing.md),
      contentBuilder: (context, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- sarlavha qatori --------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: AnimatedSubjectIcon(
                  code: subject.code,
                  color: accent,
                  size: 26,
                  // Bo'sh fanda harakat YO'Q: xiralashgan karta ustida
                  // qimirlayotgan ikonka "yuklanyapti" degan noto'g'ri
                  // xabar beradi.
                  active: hovered && !empty,
                ),
              ),
              const Gap.ms(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.name,
                        style: text.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const Gap.xs(),
                    if (empty)
                      _Chip(
                        label: l.comingSoonChip,
                        color: accent,
                        background: accent.withValues(alpha: 0.16),
                      )
                    else
                      Text(
                        subject.isStarted
                            ? _lastLine(l)
                            : l.subjectByTopics,
                        style: text.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (subject.isStarted && !empty) ...[
                const Gap.sm(),
                // Halqa 0 dan haqiqiy qiymatgacha to'ladi. Statik halqa
                // shunchaki diagramma; to'layotgan halqa — «shu yergacha
                // yetding» degan ma'no.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: subject.accuracy.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 800),
                  curve: Motion.enter,
                  builder: (_, v, __) => ProgressRing(
                    value: v,
                    size: 46,
                    stroke: 4,
                    color: accent,
                    child: Text(
                      '${(v * 100).round()}%',
                      style: text.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const Gap.md(),

          // ---- o'rta blok --------------------------------------------------
          if (empty)
            Text(
              l.subjectComingSoonHint,
              // `bodySmall` emas: xiralashgan kartada muted matn ustiga
              // shaffoflik tushib, kontrast WCAG AA dan pastga tushardi.
              style: text.bodySmall?.copyWith(color: scheme.onSurface),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            )
          else if (subject.isStarted)
            _ProgressBlock(subject: subject, accent: accent)
          else
            // BOSHLANMAGAN FANDA MATN O'RNIGA MUKOFOT.
            //
            // Ilgari bu yerda har kartada AYNAN bir xil «Bu fandan hali
            // savol yechmadingiz...» jumlasi turardi — 7 ta kartada 7 marta.
            // Bu ma'lumot emas, shovqin edi. Endi bu yerda o'quvchi uchun
            // yangi narsa turadi: birinchi mashqda nima olishi.
            Row(
              children: [
                RewardChip.xp(l.subjectXpPerQuestion(kXpPerCorrect)),
              ],
            ),

          // `Spacer` EMAS: `mainAxisSize: min` bilan u cheksiz balandlik
          // so'raydi va assert beradi.
          const Gap.md(),

          // ---- harakat -----------------------------------------------------
          if (!empty)
            Row(
              children: [
                // Seriya chipi CTA bilan BIR QATORDA: alohida qator karta
                // balandligini o'stirardi va gridda hamma kartaga qo'shimcha
                // bo'sh joy qo'shilardi.
                if (_showStreak) ...[
                  _Chip(
                    label: '$streakDays',
                    icon: Icons.local_fire_department_rounded,
                    color: palette.danger,
                    background: palette.danger.withValues(alpha: 0.12),
                  ),
                  const Gap.sm(),
                ],
                Expanded(
                  child: Text(
                    // Harakat matni DOIM `primary`, fan rangida EMAS.
                    // Ilgari har karta o'z rangida edi va foydalanuvchi
                    // "apelsin = bosiladigan narsa" qoidasini o'rgana
                    // olmasdi. Fan rangi ikonkada qoladi.
                    _cta(l),
                    style: text.labelLarge?.copyWith(color: scheme.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Hover'da strelka 4 px o'ngga suriladi — "bu yo'l shu
                // tomonga" degan ishora. Rang ham to'yinadi.
                AnimatedSlide(
                  offset: Offset(hovered ? 0.28 : 0, 0),
                  duration: Motion.fast,
                  curve: Motion.interactive,
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 18, color: scheme.primary),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Seriya chipi juda tanlab ko'rsatiladi — u kartada eng qizil element va
  /// har joyda chiqsa e'tiborni o'ziga tortib, CTA ni bosib qo'yadi.
  ///
  /// Shartlar: seriya bor, fan boshlangan va BUGUN bu fandan mashq
  /// qilinmagan. Ya'ni chip faqat "bugun uzilib qolishi mumkin" holatida.
  bool get _showStreak {
    if (streakDays <= 0 || !subject.isStarted) return false;
    final at = subject.lastPracticedAt;
    if (at == null) return true;
    final now = DateTime.now();
    return DateTime(at.year, at.month, at.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }

  String _lastLine(L10n l) =>
      '${l.lastPractice}: ${relativeDay(l, subject.lastPracticedAt ?? DateTime.now())}';

  /// Harakat matni: boshlanmagan fanda «Boshlash», boshlanganida
  /// «Davom etish». Boshqa variant YO'Q.
  ///
  /// TARIX. Ilgari bu yerda `code` va sanadan hisoblanadigan uch xil matn
  /// bor edi («Ketdik», «Yana bitta», «Davom etamiz», «Bugungi dars») —
  /// maqsad gridda ettita bir xil tugma turmasligi edi.
  ///
  /// NEGA OLIB TASHLANDI (2026-08-08 ko'rigi). Amalda buning ikkita
  /// oqibati bo'ldi:
  ///
  ///  1. **Tugma matni tugma nima qilishini aytmay qo'ydi.** «Yana bitta» —
  ///     yana bitta nima? «Ketdik» esa ta'lim mahsulotiga emas, o'yinga
  ///     xos ko'cha-og'zaki ohang.
  ///  2. **Foydalanuvchi qoidani o'rgana olmadi.** Bir xil holatdagi ikki
  ///     karta turlicha yozilgani interfeysni tasodifiy qilib ko'rsatadi.
  ///
  /// Kartalarni bir-biridan ajratadigan narsa tugma matni EMAS — fan
  /// rangi, animatsiyali ikonka, aniqlik halqasi va seriya chipi buni
  /// allaqachon qiladi.
  String _cta(L10n l) => subject.isStarted ? l.continueLabel : l.startNow;
}

/// Kichik yorliq — chip. Ikonka ixtiyoriy.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: icon == null ? Spacing.sm : 6, vertical: 2),
      decoration:
          BoxDecoration(color: background, borderRadius: Radii.pillRadius),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
        ],
        Text(label,
            style: text.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.subject, required this.accent});

  final Subject subject;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${subject.correct}/${subject.answered} ${l.subjectSolved}',
                style: text.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            RewardChip.xp(l.subjectXpPerQuestion(kXpPerCorrect)),
          ],
        ),
        const Gap.sm(),
        // 0 dan haqiqiy aniqlikka to'ladi.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: subject.accuracy.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 800),
          curve: Motion.enter,
          builder: (_, v, __) => ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: palette.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ),
      ],
    );
  }
}

/// Grid katakchasi balandligi.
///
/// `childAspectRatio` ATAYLAB ishlatilmaydi: nisbat bilan keng ekranda karta
/// cho'zilib, ichida yana bo'sh joy paydo bo'lardi. Shrift kattalashtirilsa
/// balandlik ham o'sadi — aks holda matn kesilib qolardi. `main.dart` da
/// `textScaler` 0.85–1.3 ga cheklangan, shuning uchun shu oraliq yetarli.
///
/// 204 → 216: sarlavha qatoriga XP chipi va progress chizig'i qo'shildi
/// (chiziq 5 → 6 px, chip qatori ~22 px).
///
/// `.toDouble()` shart: `num.clamp()` ning statik turi `num`, `double` emas.
double subjectCardHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3);
  return 216 * scale.toDouble();
}

/// "bugun" / "kecha" / "5 kun oldin".
///
/// `inDays` kalendar kunini emas, 24 soatlik oraliqni sanaydi, shuning uchun
/// avval ikkala sanani kunning boshiga keltiramiz — aks holda kecha kechqurun
/// qilingan mashq bugun ertalab "bugun" bo'lib ko'rinardi.
String relativeDay(L10n l, DateTime at) {
  final now = DateTime.now();
  final a = DateTime(at.year, at.month, at.day);
  final b = DateTime(now.year, now.month, now.day);
  final days = b.difference(a).inDays;
  if (days <= 0) return l.todayLabel;
  if (days == 1) return l.yesterdayLabel;
  return '$days ${l.daysAgoSuffix}';
}
