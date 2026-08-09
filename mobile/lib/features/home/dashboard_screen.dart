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

/// Bosh ekran.
///
/// ## 2026-08-08 — sahifa RITMI qayta qurildi
///
/// Muammo shundaki, ekran boshdan oxirigacha BIR XIL edi: har bir blok
/// "ikonka → sarlavha → kulrang izoh → apelsin tugma" shaklida. Ko'z bunday
/// sahifada to'xtaydigan joy topolmaydi va butun interfeys shablon bo'lib
/// ko'rinadi — sinovchilar aynan shuni aytdi.
///
/// Endi bloklar TURLI zichlikda va turli maqsadda:
///
/// ```
///   Salomlashuv            — kim ekanligim
///   Bugungi maqsad         — HARAKAT (progress chizig'i, raqam o'zgaradi)
///   Bu hafta               — 7 ta nuqta, bitta qator (juda zich)
///   Fanlar                 — grid (kashfiyot)
///   Davom ettiring         — bitta keng karta (griddan boshqacha shakl)
///   Sizning natijalaringiz — raqamlar lentasi + kuchli/kuchsiz mavzular
///   Bellashuv              — keyingi qadam
///   Footer                 — sahifa tugadi
/// ```
///
/// ## Nega "boshqa o'quvchilar" bloki yo'q
///
/// "Hozir 1 284 o'quvchi faol" tipidagi blok rejalashtirilgan edi va ATAYLAB
/// olib tashlandi: platformada hozircha bir necha sinovchi bor. Bunday raqam
/// yo bo'sh turadi, yo to'g'ri bo'lmaydi. Bo'sh joy soxta raqamdan yaxshiroq —
/// ishonchni bir marta yo'qotsang, qolgan raqamlarga ham ishonishmaydi.
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
      // Fon TOZA OQ/KULRANG EMAS.
      //
      // Yassi bir rangli fon ustida oq kartalar "qog'ozga chizilgan" bo'lib
      // ko'rinadi — chuqurlik faqat soyadan keladi va u yetarli emas. Juda
      // yumshoq issiq gradient (yuqori chetda apelsin tinti, pastga qarab
      // neytral fonga o'tadi) ekranga "yorug'lik manbai" beradi: ko'z
      // yuqoridan pastga tabiiy harakatlanadi va oq kartalar gradient
      // ustida aniq ajraladi.
      //
      // Kuchi ATAYLAB juda past (6% → 0%): sezilarli gradient bir haftadan
      // keyin bezor qiladi va skrinshotda "shablon" bo'lib ko'rinadi. Bu
      // yerdagi maqsad — sezilishi emas, YO'QLIGI sezilishi.
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
            // Kontent ekranga sig'ib qolsa ham tortib yangilash ishlashi uchun.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _Header()),

              // ---- ogohlantirishlar --------------------------------------
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      Spacing.md, Spacing.sm, Spacing.md, 0),
                  child: Column(children: [
                    // Rus tili tanlangan bo'lsa: savollar hali o'zbekcha.
                    // Yashirin fallback o'rniga ochiq xabar.
                    RuContentNotice(),
                    GuestNotice(),
                  ]),
                ),
              ),

              // ---- bugungi maqsad ----------------------------------------
              //
              // ENG TEPADA (ilgari statistika lentasi turardi). Sabab: bu
              // sahifadagi yagona blok bo'lib, u KUN DAVOMIDA O'ZGARADI.
              // Umumiy XP/daraja esa o'zgarmas identifikator — u pastga,
              // "Sizning natijalaringiz" bo'limiga ko'chirildi.
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

              // ---- bu hafta ----------------------------------------------
              // Server `week` ni bermasa (eski backend) blokning o'zi
              // `SizedBox.shrink()` qaytaradi — bu yerda shart kerak emas.
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
                    // Ilgari bu «Fan tanlang» edi va kartalarning HAR BIRIDA
                    // yana «Bu fandan hali savol yechmadingiz...» takrorlanardi
                    // — 7 ta kartada 7 marta bir xil jumla. Tavsiya endi shu
                    // yerda BIR MARTA turadi, kartalar esa faqat farq
                    // qiladigan ma'lumotni ko'rsatadi.
                    subtitle: l.subjectEmptyHint,
                    icon: Icons.category_outlined,
                  ),
                ),
              ),
              subjectsAsync.when(
                loading: () => const _SubjectSkeletonSliver(),
                // DIQQAT: `EmptyState` ichida `SingleChildScrollView` bor.
                // Sliver ichida balandlik CHEKSIZ bo'ladi va vertikal viewport
                // "unbounded height" bilan yiqiladi — shuning uchun `SizedBox`
                // bilan balandlik cheklanadi.
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
                          // Seriya UMUMIY (fanga xos emas). Karta uni faqat
                          // shu fandan BUGUN mashq qilinmagan bo'lsa
                          // ko'rsatadi — «bugun uzilib qolmasin» ishorasi.
                          streakDays:
                              meAsync.valueOrNull?.progress.streakDays ?? 0,
                          onTap: () => Navigator.push(
                            ctx,
                            MaterialPageRoute(
                                builder: (_) => PickerScreen(subjects[i])),
                          ),
                          // Grid ketma-ket ochiladi. Kechikish 8-elementdan
                          // keyin o'smaydi: pastdagi kartalar baribir
                          // ekrandan tashqarida.
                        ).enterStaggered(i),
                        childCount: subjects.length,
                      ),
                    ),
                  );
                },
              ),

              // ---- davom ettiring -----------------------------------------
              //
              // Griddan KEYIN va boshqa shaklda: o'nta bir xil kartochka
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

              // ---- sizning natijalaringiz ---------------------------------
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

              // ---- tahlil (kuchli/kuchsiz mavzular) -----------------------
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
              // `SliverToBoxAdapter` EMAS: kontent kalta bo'lganda (masalan,
              // fanlar hali yuklanmagan) footer ekran o'rtasida qolib,
              // ostida bo'sh oq joy paydo bo'lardi.
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

/// Sahifa foni: yuqori chetdan tushadigan juda yumshoq issiq nur.
///
/// Nega chiziqli, radial emas: radial gradientning markazi ekran ichida
/// qoladi va u "projektor dog'i" bo'lib ko'rinadi — ayniqsa keng ekranda,
/// kontent 1100 px bilan cheklanganda dog' kontentdan tashqarida qolardi.
/// Chiziqli gradient esa har qanday kenglikda bir xil o'qiladi.
///
/// `stops: [0, 0.38]` — nur ekranning yuqori uchdan biridayoq tugaydi:
/// pastda toza fon qoladi va uzun sahifada gradient "cho'zilib ketmaydi".
///
/// Qorong'i temada tint 4% ga tushiriladi: qora fonda issiq rang tez
/// "iflos" ko'rinadi.
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
    // Nur ekranning yuqori uchdan biridayoq tugaydi — pastda toza fon.
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
    // `scheme` olib tashlandi: avatar endi `UserAvatar` bo'lib, rangni o'zi
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
                // «Fan tanlang» BU YERDA EMAS. U pastdagi «Fanlar» bo'limi
                // sarlavhasining ostida ham turadi — bitta ekranda ikki
                // marta bir xil ko'rsatma foydasiz takror. Bu yerda esa
                // salomlashuvni to'ldiradigan narsa kerak, buyruq emas.
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
            // Keng ekranda markazlashgan modal, telefonda to'liq sahifa —
            // qarorni `NotesScreen.open` o'zi qabul qiladi.
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
/// Nega `Row` emas: telefon kengligida beshta karta sig'maydi va `Row` overflow
/// beradi. Lenta esa har qanday kenglikda ishlaydi va keng ekranda beshtasi
/// baribir bir vaqtda ko'rinadi.
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.me});

  final MeOverview me;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    // Server: `level = 1 + xp // 100` (config.xp_per_level). Shu sababli
    // keyingi darajagacha bo'lgan ulush — XP ning yuzga qoldig'i.
    const perLevel = 100;
    final levelProgress = (me.progress.xp % perLevel) / perLevel;

    // Ranglar ma'no tashiydi, bezak emas:
    //   apelsin — energiya (XP), sariq — yutuq/pul (daraja, tanga),
    //   qizil — olov/seriya, kulrang — neytral o'rin.
    // Ilgari «O'rin» kartasi `scheme.secondary` ni olardi, u esa bu temada
    // `primary` ga TENG — natijada beshta kartadan uchtasi bir xil apelsin
    // bo'lib, lenta yagona rangli chiziqqa aylanib qolgandi.
    final cards = <Widget>[
      StatCard(
        // Material ikonkasi emas — XP BELGISI (oltiburchak ichida chaqmoq).
        // U reyting, quiz mukofot chipi va shu kartochkada bir xil, ya'ni
        // foydalanuvchi uni ilova bo'ylab tanib oladi.
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
        // noncoin kristali. `sparkle: true` faqat SHU YERDA — bu ilovada
        // valyuta balansi ko'rsatiladigan yagona doimiy joy. Ro'yxatlarda
        // yoki chiplarda yaltirash yoqilsa ekran diskotekaga aylanadi.
        iconWidget: const NonCoinIcon(size: 18, sparkle: true),
        value: '0',
        count: me.coins,
        label: l.statCoins,
        accent: Rewards.coinDark,
      ),
      StatCard(
        icon: Icons.leaderboard_outlined,
        // Reytingga hali tushmagan bo'lsa raqam yo'q — «—» sanalmaydi.
        //
        // «#1» EMAS: panjara belgisi ingliz tilidagi konvensiya va
        // o'zbekcha interfeysda o'qilmaydi. To'g'ri shakl — tartib son:
        // «1-o'rin».
        value: me.rank == null ? '—' : l.statRankValue(me.rank!),
        label: l.statRank,
        accent: palette.muted,
      ),
    ];

    // Balandlik shrift kattaligiga qarab o'sadi. Progress chizig'i bor
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
        // Kartalar chapdan o'ngga ketma-ket ochiladi — ko'z tabiiy ravishda
        // XP dan boshlab o'ngga suriladi va lenta scroll qilinishini payqaydi.
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
