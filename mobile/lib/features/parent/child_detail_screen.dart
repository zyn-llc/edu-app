import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/spacing.dart';
import '../../widgets/avatar.dart';
import '../../widgets/empty_state.dart';
import '../analysis/topic_mastery_view.dart';
import '../home/activity_sections.dart';
import 'parent_data.dart';

/// Bitta farzandning batafsil ko'rinishi — FAQAT O'QISH uchun.
///
/// ## Nega bu ekran qayta yozildi
///
/// U bolaning O'ZI ko'radigan raqamlarni takrorlardi: Daraja, XP, kunlik
/// seriya, umumiy aniqlik. `services/progress.parent_signals` izohida bu
/// aynan xato deb yozilgan edi — ota-ona XP nima ekanini bilmaydi va u
/// bilan hech narsa qila olmaydi. Kod esa o'sha izohga zid ish qilardi.
///
/// Ota-ona amalda ikkita savolga javob izlaydi, va ekran endi shu tartibda
/// javob beradi:
///
///   1. **Bolam umuman shug'ullanyaptimi?**  → haftalik ritm (7 nuqta),
///      oxirgi mashq qachon. Bu raqam emas, SHAKL — bir qarashda tushuniladi
///      va tushuntirish talab qilmaydi.
///   2. **Qayerda qiynalyapti?**            → zaif mavzular, foiz bilan.
///      Bu ota-ona HARAKAT qila oladigan yagona ma'lumot: repetitorga
///      aytadi, o'zi so'raydi, yoki shu mavzuni takrorlashni taklif qiladi.
///
/// Kuchli mavzular ham qoladi, lekin PASTDA: ular xotirjamlik beradi,
/// qaror emas.
///
/// Umumiy XP/daraja ataylab OLIB TASHLANDI — u ota-ona kartochkasida ham,
/// bu yerda ham takrorlanardi, ya'ni ekranning yarmi ma'nosiz edi.
class ChildDetailScreen extends ConsumerWidget {
  final ChildSummary child;
  const ChildDetailScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final palette = Theme.of(context).extension<AppPalette>()!;
    final name = child.displayName?.isNotEmpty == true
        ? child.displayName!
        : l.lbAnonymous;
    final analysisAsync = ref.watch(childAnalysisProvider(child.studentId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Row(
          children: [
            // Avatar shu yergacha yetib kelmagan edi (CLAUDE.md dagi ochiq
            // band). Bir nechta farzandi bor ota-ona uchun u nomdan tezroq
            // ishlaydi.
            UserAvatar(name: name, colorIndex: child.avatarColor, size: 32),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(childAnalysisProvider(child.studentId)),
        child: ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            // ---- 1. Shug'ullanyaptimi -------------------------------------
            _SectionTitle(l.parentRhythmTitle),
            const Gap.sm(),
            WeekStrip(progress: child.progress),
            const Gap.sm(),
            _SignalRow(child: child),

            const Gap.xl(),

            // ---- 2. Qayerda qiynalyapti -----------------------------------
            _SectionTitle(l.parentStrugglesTitle),
            const Gap.sm(),
            analysisAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              // Xato holati ham chiqish yo'li bilan: ilgari bu yerda bitta
              // kulrang qator va kichkina "Qayta urinish" tugmasi turardi.
              error: (_, __) => SizedBox(
                height: 220,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: l.errTitle,
                  message: l.errNoConnection,
                  actionLabel: l.retry,
                  onAction: () =>
                      ref.invalidate(childAnalysisProvider(child.studentId)),
                ),
              ),
              data: (a) {
                if (a.weakest.isEmpty && a.strongest.isEmpty) {
                  // Bo'sh holat ota-onaga QACHON to'lishini aytadi. Ilgari
                  // "Tahlil uchun avval bir nechta savol yeching" derdi —
                  // lekin bu ota-onaning qo'lidagi ish emas, u savol
                  // yechmaydi. Endi matn kimga qaratilgani to'g'ri.
                  return SizedBox(
                    height: 240,
                    child: EmptyState(
                      icon: Icons.insights_rounded,
                      title: l.parentAnalysisEmptyTitle,
                      message: l.parentAnalysisEmptyBody,
                    ),
                  );
                }
                return TopicMasteryView(analysis: a);
              },
            ),

            const Gap.xl(),
            Text(l.parentPrivacyNote,
                style: TextStyle(fontSize: 12, height: 1.45, color: palette.faint)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );
}

/// Ota-onaga xos uchta raqam. Ular `ChildSummary` da allaqachon bor edi va
/// ota-ona kartochkasida ko'rsatilardi — bu ekranda esa nomaʼlum sababga
/// ko'ra XP/daraja bilan almashtirilgan edi.
class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.child});
  final ChildSummary child;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final palette = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;

    final items = <(String, String)>[
      ('${child.answered7d}', l.parentAnsweredWeek),
      ('${child.activeDays7d}/7', l.parentActiveDays),
      ('${(child.accuracy7d * 100).round()}%', l.parentAccuracyWeek),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (value, label) in items)
            Column(
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(fontSize: 11.5, color: palette.muted)),
              ],
            ),
        ],
      ),
    );
  }
}
