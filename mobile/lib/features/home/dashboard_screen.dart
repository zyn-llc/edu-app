import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../../core/breakpoints.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/motion.dart';
import '../../theme/spacing.dart';
import '../../widgets/app_footer.dart';
import '../../widgets/avatar.dart';
import '../../widgets/currency.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/guest_notice.dart';
import '../../widgets/ru_content_notice.dart';
import '../../widgets/stats.dart';
import '../analysis/topic_mastery_view.dart';
import '../news/news_screen.dart';
import '../notes/notes_screen.dart';
import '../quiz/picker_screen.dart';
import '../settings/settings_screen.dart';
import '../subjects/subject_card.dart';
import '../subjects/subjects.dart';
import 'activity_sections.dart';

///
///
///
///
/// ```
///   Salomlashuv            — kim ekanligim
///   Fanlar                 — grid (kashfiyot)
///   Bellashuv              — keyingi qadam
/// ```
///
///
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final subjectsAsync = ref.watch(subjectsProvider);
    final meAsync = ref.watch(meOverviewProvider);
    final analysisAsync = ref.watch(analysisProvider);

    const hPad = EdgeInsets.symmetric(horizontal: Spacing.md);

    return Scaffold(
      //
      // yumshoq issiq gradient (yuqori chetda apelsin tinti, pastga qarab
      // ustida aniq ajraladi.
      //
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: _pageGradient(context)),
        child: ContentWidth(
        maxWidth: 1100,
        child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(subjectsProvider);
            ref.invalidate(meOverviewProvider);
            ref.invalidate(analysisProvider);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _Header()),

              // ---- ogohlantirishlar --------------------------------------
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      Spacing.md, Spacing.sm, Spacing.md, 0),
                  child: Column(children: [
                    RuContentNotice(),
                    GuestNotice(),
                  ]),
                ),
              ),

              subjectsAsync.maybeWhen(
                data: (subjects) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.md, Spacing.md, Spacing.md, 0),
                    child: DailyGoalCard(
                      subjects: subjects,
                      progress: meAsync.valueOrNull?.progress,
                    ),
                  ),
                ),
                orElse: () =>
                    const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),

              if (meAsync.valueOrNull != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.md, Spacing.ms, Spacing.md, 0),
                    child: WeekStrip(progress: meAsync.value!.progress),
                  ),
                ),

              // ---- fanlar --------------------------------------------------
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.md, Spacing.xl, Spacing.md, 0),
                sliver: SliverToBoxAdapter(
                  child: SectionHeader(
                    l.subjects,
                    subtitle: l.subjectEmptyHint,
                    icon: Icons.category_outlined,
                  ),
                ),
              ),
              subjectsAsync.when(
                loading: () => const _SubjectSkeletonSliver(),
                error: (e, _) => SliverToBoxAdapter(
                  child: SizedBox(
                    height: 300,
                    child: EmptyState(
                      compact: true,
                      icon: Icons.wifi_off_rounded,
                      title: l.errNoConnection,
                      message: humanError(e, l),
                      actionLabel: l.retry,
                      onAction: () => ref.invalidate(subjectsProvider),
                    ),
                  ),
                ),
                data: (subjects) {
                  if (subjects.isEmpty) {
                    return SliverToBoxAdapter(
                      child: SizedBox(
                        height: 300,
                        child: EmptyState(
                          compact: true,
                          icon: Icons.library_books_outlined,
                          title: l.subjects,
                          message: l.noQuestions,
                          actionLabel: l.retry,
                          onAction: () => ref.invalidate(subjectsProvider),
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: hPad,
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 340,
                        crossAxisSpacing: Spacing.ms,
                        mainAxisSpacing: Spacing.ms,
                        mainAxisExtent: subjectCardHeight(context),
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => SubjectCard(
                          subject: subjects[i],
                          streakDays:
                              meAsync.valueOrNull?.progress.streakDays ?? 0,
                          onTap: () => Navigator.push(
                            ctx,
                            MaterialPageRoute(
                                builder: (_) => PickerScreen(subjects[i])),
                          ),
                        ).enterStaggered(i),
                        childCount: subjects.length,
                      ),
                    ),
                  );
                },
              ),

              // ---- davom ettiring -----------------------------------------
              //
              // orasidan "men qayerda to'xtagandim" ni topish qiyin.
              subjectsAsync.maybeWhen(
                data: (subjects) => ContinueCard.pick(subjects) == null
                    ? const SliverToBoxAdapter(child: SizedBox.shrink())
                    : SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Spacing.md, Spacing.xl, Spacing.md, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SectionHeader(l.dashContinueTitle,
                                  icon: Icons.play_circle_outline_rounded),
                              ContinueCard(subjects: subjects),
                            ],
                          ),
                        ),
                      ),
                orElse: () =>
                    const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),

              if (meAsync.valueOrNull != null) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.md, Spacing.xl, Spacing.md, 0),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(l.dashResultsTitle,
                        icon: Icons.insights_outlined),
                  ),
                ),
                SliverToBoxAdapter(child: _StatsStrip(me: meAsync.value!)),
              ],

              analysisAsync.maybeWhen(
                data: (a) => (a == null || a.topics.isEmpty)
                    ? const SliverToBoxAdapter(child: SizedBox.shrink())
                    : SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Spacing.md, Spacing.sm, Spacing.md, 0),
                          child: TopicMasteryView(analysis: a),
                        ),
                      ),
                orElse: () =>
                    const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),

              // ---- bellashuv ----------------------------------------------
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      Spacing.md, Spacing.xl, Spacing.md, 0),
                  child: ChallengeCta(),
                ),
              ),

              // ---- footer --------------------------------------------------
              const FooterSliver(full: true),
            ],
          ),
        ),
        ),
      ),
      ),
    );
  }
}

LinearGradient _pageGradient(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bg = Theme.of(context).scaffoldBackgroundColor;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color.alphaBlend(
          scheme.primary.withValues(alpha: isDark ? 0.04 : 0.06), bg),
      bg,
    ],
    stops: const [0.0, 0.38],
  );
}

/// Salomlashuv qatori + tezkor kirishlar.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    // (palitradan yoki ism hash'idan) tanlaydi.
    final displayName = ref.watch(authControllerProvider).user?.displayName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.ms, Spacing.sm, Spacing.xs),
      child: Row(
        children: [
          UserAvatar(
            name: displayName,
            colorIndex: ref.watch(authControllerProvider).user?.avatarColor,
            size: 44,
          ),
          const Gap.ms(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName != null && displayName.isNotEmpty
                      ? l.greetingNamed(displayName)
                      : l.greetingHi,
                  style: text.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(l.dashGoalLead(kDailyTarget),
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.campaign_outlined),
            tooltip: l.newsTitle,
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NewsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: l.notesTitle,
            onPressed: () => NotesScreen.open(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l.settings,
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }
}

/// Beshta `StatCard` — gorizontal suriladigan lenta.
///
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.me});

  final MeOverview me;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    const perLevel = 100;
    final levelProgress = (me.progress.xp % perLevel) / perLevel;

    //   qizil — olov/seriya, kulrang — neytral o'rin.
    final cards = <Widget>[
      StatCard(
        iconWidget: const XpIcon(size: 18),
        value: '0',
        count: me.progress.xp,
        label: l.statXp,
        accent: scheme.primary,
      ),
      StatCard(
        icon: Icons.military_tech_outlined,
        value: '0',
        count: me.progress.level,
        label: l.statLevel,
        accent: palette.warning,
        progress: levelProgress,
      ),
      StatCard(
        icon: Icons.local_fire_department_rounded,
        value: '0',
        count: me.progress.streakDays,
        label: l.statStreak,
        accent: palette.danger,
      ),
      StatCard(
        iconWidget: const NonCoinIcon(size: 18, sparkle: true),
        value: '0',
        count: me.coins,
        label: l.statCoins,
        accent: Rewards.coinDark,
      ),
      StatCard(
        icon: Icons.leaderboard_outlined,
        //
        // «1-o'rin».
        value: me.rank == null ? '—' : l.statRankValue(me.rank!),
        label: l.statRank,
        accent: palette.muted,
      ),
    ];

    // kartochka eng balandi — `148` da u 16 px ga toshib ketardi.
    final scale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3).toDouble();

    return SizedBox(
      height: 168 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.md, Spacing.md, Spacing.xs),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const Gap.ms(),
        itemBuilder: (_, i) =>
            SizedBox(width: 132, child: cards[i]).enterStaggered(i),
      ),
    );
  }
}

class _SubjectSkeletonSliver extends StatelessWidget {
  const _SubjectSkeletonSliver();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 340,
          crossAxisSpacing: Spacing.ms,
          mainAxisSpacing: Spacing.ms,
          mainAxisExtent: subjectCardHeight(context),
        ),
        delegate: SliverChildBuilderDelegate(
          (_, __) => const Padding(
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
          childCount: 4,
        ),
      ),
    );
  }
}
