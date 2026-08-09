import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/motion.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import '../quiz/picker_screen.dart';
import 'subject_card.dart';
import 'subjects.dart';

/// Fanlar gridi.
///
/// Ustunlar soni `crossAxisCount` bilan qattiq belgilanmagan: `maxCrossAxisExtent`
/// har bir kartaga eng ko'pi 340 px beradi va ustunlar soni ekran kengligidan
/// o'zi kelib chiqadi. Telefonda 1–2, planshetda 3, desktopda 4–5 bo'ladi va
/// oraliq o'lchamlarda ham hech narsa siqilib qolmaydi.
class SubjectGridScreen extends ConsumerWidget {
  const SubjectGridScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final subjectsAsync = ref.watch(subjectsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.subjects)),
      body: subjectsAsync.when(
        loading: () => const _SubjectGridSkeleton(),
        error: (e, _) => EmptyState(
          icon: Icons.wifi_off_rounded,
          title: l.errNoConnection,
          message: '$e',
          actionLabel: l.retry,
          onAction: () => ref.invalidate(subjectsProvider),
        ),
        data: (subjects) {
          if (subjects.isEmpty) {
            return EmptyState(
              icon: Icons.library_books_outlined,
              title: l.subjects,
              message: l.noQuestions,
              actionLabel: l.retry,
              onAction: () => ref.invalidate(subjectsProvider),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, Spacing.lg),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 340,
              crossAxisSpacing: Spacing.ms,
              mainAxisSpacing: Spacing.ms,
              // Balandlik ATAYLAB piksel bilan berilgan, `childAspectRatio`
              // bilan emas: nisbat ishlatilganda keng ekranda karta cho'zilib,
              // ichida yana bo'sh joy paydo bo'lardi. Shrift kattalashtirilsa
              // balandlik ham o'sadi — aks holda matn kesilib qolardi.
              mainAxisExtent: subjectCardHeight(context),
            ),
            itemCount: subjects.length,
            itemBuilder: (_, i) => SubjectCard(
              subject: subjects[i],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PickerScreen(subjects[i])),
              ),
            ).enterStaggered(i),
          );
        },
      ),
    );
  }
}

class _SubjectGridSkeleton extends StatelessWidget {
  const _SubjectGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm, Spacing.md, Spacing.lg),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        crossAxisSpacing: Spacing.ms,
        mainAxisSpacing: Spacing.ms,
        mainAxisExtent: subjectCardHeight(context),
      ),
      itemCount: 6,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Skeleton(width: 44, height: 44, radius: Radii.md),
              Gap.ms(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(height: 16),
                    Gap.sm(),
                    Skeleton(width: 90, height: 12),
                  ],
                ),
              ),
            ]),
            Gap.lg(),
            Skeleton(height: 12),
            Gap.sm(),
            Skeleton(height: 6, radius: Radii.pill),
            Gap.lg(),
            Skeleton(width: 100, height: 14),
          ],
        ),
      ),
    );
  }
}
