import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_models.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/elevation.dart';
import '../../theme/motion.dart';
import '../../theme/spacing.dart';
import '../../theme/subject_palette.dart';
import '../../widgets/currency.dart';
import '../../widgets/hover_card.dart';
import '../../widgets/subject_icon.dart';
import '../quiz/picker_screen.dart';
import '../subjects/subjects.dart';
import 'home_shell.dart';

/// Bosh ekranning SHAXSIY bloklari.
///
/// ## Nega bular qo'shildi (2026-08-08)
///
/// Sinovdan kelgan xulosa: ilova "o'lik" ko'rinadi. Sabab dizayn emas edi —
/// ekranda O'ZGARADIGAN hech narsa yo'q edi. Har bir karta bir xil tuzilishda
/// (ikonka → sarlavha → kulrang izoh → apelsin tugma) va hech biri
/// foydalanuvchining bugungi holatini ko'rsatmasdi.
///
/// ## Nega ijtimoiy blok YO'Q
///
/// Birinchi variantda "Hozir Topag'onda: N o'quvchi faol" va boshqalarning
/// faoliyat lentasi bor edi. U OLIB TASHLANDI: hozir platformada bir necha
/// sinovchi bor, ya'ni bunday blok yo bo'sh turadi, yo to'ldirish uchun
/// raqamlarni bo'rttirishga majbur qiladi. Soxta faollik bo'sh joydan
/// ko'ra ko'proq zarar qiladi — foydalanuvchi buni bir marta sezsa, boshqa
/// raqamlarga ham ishonmaydi.
///
/// Shuning uchun bu yerdagi HAR BIR raqam foydalanuvchining o'ziniki va
/// serverdan keladi (`/v1/me` → `progress`). Ma'lumot yetmasa blok umuman
/// ko'rsatilmaydi.

/// Kunlik maqsad — savollar soni.
///
/// NEGA 20. `picker_screen` da standart mashq 10 ta savol, ya'ni ikkita
/// mashq. Bu 10–12 daqiqa: maktabdan keyin real bajariladigan hajm.
const int kDailyTarget = 20;

/// Mashq qilish uchun eng mantiqiy fan: oxirgi marta ishlangani, u bo'lmasa
/// birinchi savoli bor fan. `null` — umuman savol yo'q.
Subject? _resumeTarget(List<Subject> subjects) {
  final playable = [for (final s in subjects) if (s.questionCount > 0) s];
  if (playable.isEmpty) return null;
  Subject best = playable.first;
  DateTime? bestAt;
  for (final s in playable) {
    final at = s.lastPracticedAt;
    if (at != null && (bestAt == null || at.isAfter(bestAt))) {
      bestAt = at;
      best = s;
    }
  }
  return best;
}

// --------------------------------------------------------------------------- //
//  1. Bugungi maqsad                                                          //
// --------------------------------------------------------------------------- //

/// Bugungi maqsad — endi HAQIQIY progress bilan.
///
/// Ilgari bu karta faqat "bajarildi / bajarilmadi" ni bilardi va uni
/// fanlarning `lastPracticedAt` idan TAXMIN qilardi, chunki serverda "bugun
/// nechta savol" maydoni yo'q edi. Endi `/v1/me` `progress.answered_today`
/// ni qaytaradi, ya'ni chiziq to'ladi va raqam o'zgaradi — ekranda kun
/// davomida O'ZGARADIGAN yagona narsa aynan shu.
///
/// Mehmon (`progress == null`) uchun progress ko'rsatilmaydi: uning javoblari
/// saqlanmaydi, ya'ni "0/20" yolg'on bo'lardi.
class DailyGoalCard extends StatelessWidget {
  const DailyGoalCard({
    super.key,
    required this.subjects,
    required this.progress,
  });

  final List<Subject> subjects;
  final Progress? progress;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    final target = _resumeTarget(subjects);
    if (target == null) return const SizedBox.shrink();

    final done = progress?.answeredToday ?? 0;
    final complete = done >= kDailyTarget;
    final accent = complete ? palette.success : scheme.primary;
    final ratio = (done / kDailyTarget).clamp(0.0, 1.0);

    void start() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PickerScreen(target)),
        );

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: complete
            ? palette.success.withValues(alpha: 0.10)
            : palette.primaryTint,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: accent.withValues(alpha: 0.30)),
        boxShadow: Shadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(complete ? Icons.check_circle_rounded : Icons.flag_rounded,
                  color: accent),
              const Gap.ms(),
              Expanded(
                child: Text(
                  complete ? l.dashGoalDone : l.dashGoalTitle,
                  style: text.titleMedium?.copyWith(color: accent),
                ),
              ),
              // Raqam O'NGDA va yirik: ko'z avval "12 / 20" ni topadi,
              // keyin chiziqni. Teskarisida chiziq bezakka aylanadi.
              if (progress != null)
                Text('$done / $kDailyTarget',
                    style: text.titleMedium?.copyWith(
                        color: accent, fontWeight: FontWeight.w700)),
            ],
          ),
          const Gap.ms(),

          if (progress == null)
            // Mehmon: raqam yo'q, faqat maqsadning o'zi.
            Text(l.dashGoalLead(kDailyTarget), style: text.bodySmall)
          else ...[
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 700),
              curve: Motion.enter,
              builder: (_, v, __) => ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  backgroundColor: scheme.surface,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ),
            const Gap.sm(),
            Text(
              complete
                  ? l.dashGoalTomorrow(kDailyTarget)
                  : l.dashGoalRemaining(kDailyTarget - done),
              style: text.bodySmall,
            ),
          ],

          // Bugungi natija chiplari — faqat HAQIQATAN bor bo'lsa.
          if (progress != null && progress!.answeredToday > 0) ...[
            const Gap.ms(),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                if (progress!.xpToday > 0)
                  RewardChip.xp(l.rewardXp(progress!.xpToday)),
                _MetaChip(
                  icon: Icons.track_changes_rounded,
                  label: l.dashAccuracyValue(
                      ((progress!.accuracyToday ?? 0) * 100).round()),
                  color: palette.muted,
                ),
                if (progress!.streakDays > 0)
                  _MetaChip(
                    icon: Icons.local_fire_department_rounded,
                    label: l.dashStreakDays(progress!.streakDays),
                    color: palette.danger,
                  ),
              ],
            ),
          ],

          if (!complete) ...[
            const Gap.md(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: start,
                child: Text(done > 0 ? l.continueLabel : l.dashQuickStart),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kichik ma'lumot chipi. `RewardChip` valyuta uchun; bu esa neytral
/// ko'rsatkichlar uchun (aniqlik, seriya) — ular mukofot EMAS.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: Radii.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const Gap.xs(),
          Text(label,
              style: text.labelSmall
                  ?.copyWith(color: c, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  2. Bu hafta                                                                //
// --------------------------------------------------------------------------- //

/// Haftalik chiziq: Du–Ya nuqtalari + yig'indi.
///
/// NEGA AYNAN NUQTALAR, diagramma emas. Ettita ustunli diagramma "nechta
/// savol" ni ko'rsatadi, lekin o'quvchi uchun muhimi boshqa: KUN O'TKAZIB
/// YUBORILDIMI. To'ldirilgan/bo'sh doira bu savolga bir qarashda javob
/// beradi va bo'sh kunlar ko'zga tashlanadi — seriya mantig'i ham xuddi shu.
///
/// Server har doim 7 ta kun yuboradi (bo'shlari ham), shuning uchun bu yerda
/// sana to'ldirish mantig'i yo'q. Eski serverda `week` bo'sh keladi — u
/// holda blok umuman ko'rsatilmaydi.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    final week = progress.week;
    if (week.isEmpty) return const SizedBox.shrink();

    // `weekdayShorts` — vergul bilan ajratilgan 7 ta qisqartma (Du,Se,...).
    // Bitta kalitda: `weekdayMon`..`weekdaySun` degan yettita kalit tarjima
    // faylini shishiradi va tartibni buzish oson.
    final names = l.weekdayShorts.split(',');

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
        children: [
          Text(l.dashWeekTitle, style: text.titleSmall),
          const Gap.ms(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < week.length; i++)
                _DayDot(
                  // `DateTime.weekday`: 1 = dushanba … 7 = yakshanba.
                  label: names.length == 7
                      ? names[week[i].date.weekday - 1]
                      : '',
                  day: week[i],
                  index: i,
                ),
            ],
          ),
          const Gap.ms(),
          Wrap(
            spacing: Spacing.ms,
            runSpacing: Spacing.xs,
            children: [
              Text(l.dashQuestionsCount(progress.answered7d),
                  style: text.bodySmall),
              if (progress.xp7d > 0)
                Text(l.rewardXp(progress.xp7d),
                    style: text.bodySmall
                        ?.copyWith(color: Rewards.xp, fontWeight: FontWeight.w700)),
              Text(l.dashDaysActive(progress.activeDays7d),
                  style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.label, required this.day, required this.index});

  final String label;
  final DayStat day;
  final int index;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    final filled = day.isActive;
    final color = filled ? scheme.primary : palette.surfaceAlt;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: text.labelSmall?.copyWith(
            color: day.isToday ? scheme.primary : palette.muted,
            fontWeight: day.isToday ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        const Gap.xs(),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            // Bugungi kun HAR DOIM halqa bilan belgilanadi — hatto bo'sh
            // bo'lsa ham. "Bugun hali qilinmagan" — bu ham ma'lumot.
            border: day.isToday
                ? Border.all(color: scheme.primary, width: 2)
                : null,
          ),
          child: filled
              ? Icon(Icons.check_rounded,
                  size: 16, color: scheme.onPrimary)
              : null,
        ),
      ],
    ).enterStaggered(index);
  }
}

// --------------------------------------------------------------------------- //
//  3. Davom ettiring                                                          //
// --------------------------------------------------------------------------- //

/// Oxirgi ishlangan fanga qaytish kartasi.
///
/// NEGA GRIDDAN KEYIN VA BOSHQA SHAKLDA. Fanlar gridida o'nta bir xil
/// kartochka bor; ular orasidan "men qayerda to'xtagandim" degan savolga
/// javob topish uchun o'quvchi har birini o'qib chiqishi kerak. Bu karta —
/// keng, bitta va boshqacha tuzilishda, ya'ni ko'z uni grid deb o'qimaydi.
///
/// Faqat KAMIDA BIR MARTA mashq qilingan bo'lsa chiqadi.
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.subjects});

  final List<Subject> subjects;

  /// Ko'rsatishga arziydigan fan bormi.
  static Subject? pick(List<Subject> subjects) {
    Subject? best;
    DateTime? bestAt;
    for (final s in subjects) {
      final at = s.lastPracticedAt;
      if (s.questionCount <= 0 || at == null || s.answered <= 0) continue;
      if (bestAt == null || at.isAfter(bestAt)) {
        bestAt = at;
        best = s;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final brightness = Theme.of(context).brightness;

    final s = pick(subjects);
    if (s == null) return const SizedBox.shrink();

    final style = SubjectPalette.of(s.code);
    final color = style.color(brightness);
    final pct = (s.accuracy * 100).round();

    return HoverCard(
      accent: color,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PickerScreen(s)),
      ),
      contentBuilder: (context, hovered) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(Spacing.ms),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: AnimatedSubjectIcon(
                code: s.code, color: color, size: 26, active: hovered),
          ),
          const Gap.md(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.name,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const Gap.xs(),
                Text(
                  '${l.dashQuestionsCount(s.answered)} · '
                  '${l.dashAccuracyValue(pct)}',
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap.sm(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: s.accuracy.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 700),
                    curve: Motion.enter,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: palette.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap.ms(),
          // Strelka hover'da o'ngga suriladi — "bu yo'l davom etadi".
          AnimatedSlide(
            offset: hovered ? const Offset(0.25, 0) : Offset.zero,
            duration: Motion.fast,
            curve: Motion.interactive,
            child: Icon(Icons.arrow_forward_rounded, color: color),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  4. Bellashuv taklifi                                                       //
// --------------------------------------------------------------------------- //

/// Bellashuv bo'limiga olib boruvchi karta.
///
/// ATAYLAB ishtirokchi soni, taymer yoki "hozir 18 kishi o'ynayapti" YO'Q:
/// bellashuv — do'st bilan 1v1 va jadval bo'yicha turnir emas. Bunday
/// raqamlarni ko'rsatish uchun ularni o'ylab topish kerak bo'lardi.
///
/// Karta faqat sahifaning oxirida turadi va vazifasi bitta: sahifa
/// "tugadi" degan hissiyot bilan emas, keyingi qadam bilan yakunlansin.
class ChallengeCta extends ConsumerWidget {
  const ChallengeCta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: palette.hairline),
        boxShadow: Shadows.card(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(Spacing.ms),
            decoration: BoxDecoration(
              color: Rewards.coinDark.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: const Icon(Icons.emoji_events_rounded,
                color: Rewards.coinDark, size: 26),
          ),
          const Gap.md(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.navChallenges, style: text.titleMedium),
                const Gap.xs(),
                Text(l.dashChallengeBody, style: text.bodySmall),
                const Gap.ms(),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(homeTabProvider.notifier).state = 2,
                  child: Text(l.dashChallengeCta),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
