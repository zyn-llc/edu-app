import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/spacing.dart';
import '../../widgets/app_footer.dart';
import '../../widgets/empty_state.dart';
import '../../theme/elevation.dart';
import '../../theme/motion.dart';
import '../../widgets/avatar.dart';
import '../auth/login_sheet.dart';
import '../home/home_shell.dart';
import '../referral/invite_friends.dart';
import '../subjects/subjects.dart';
import 'leaderboard_data.dart';

/// Reyting ekrani.
///
/// Ilgari bu ekran shunchaki bir xil qatorlar ro'yxati edi — musobaqa hissi
/// yo'q edi. Endi eng yuqori uchtasi PODIUM ko'rinishida: birinchi o'rin
/// o'rtada va balandroq turadi. Bu shunchaki bezak emas — o'quvchi bir
/// qarashda "cho'qqi" qayerdaligini ko'radi va o'z qatorigacha bo'lgan masofa
/// aniq bo'ladi.
///
/// Qolgan qatorlar oddiy ro'yxat; foydalanuvchining o'z qatori ajratib
/// ko'rsatiladi, ro'yxatdan tashqarida bo'lsa pastda yopishib turadi.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  String? _subjectCode; // tanlangan fan bo'yicha reyting

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.navLeaderboard),
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: l.lbTotal),
            Tab(text: l.lbSubject),
            Tab(text: l.lbRegion),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          const _BoardList(scope: 'total', boardKey: null),
          _SubjectBoard(
            selected: _subjectCode,
            onSelect: (c) => setState(() => _subjectCode = c),
          ),
          const _RegionBoard(),
        ],
      ),
    );
  }
}

/// Fan tabi: yuqorida fan tanlagich, pastida shu fan bo'yicha reyting.
class _SubjectBoard extends ConsumerWidget {
  const _SubjectBoard({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final subjectsAsync = ref.watch(subjectsProvider);

    return subjectsAsync.when(
      loading: () => const _BoardSkeleton(),
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
            icon: Icons.emoji_events_outlined,
            title: l.lbEmptyTitle,
            message: l.lbEmptyHint,
            actionLabel: l.retry,
            onAction: () => ref.invalidate(subjectsProvider),
          );
        }
        final code = selected ?? subjects.first.code;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.ms, Spacing.md, Spacing.xs),
              child: DropdownButtonFormField<String>(
                initialValue: code,
                decoration: const InputDecoration(isDense: true),
                items: [
                  for (final s in subjects)
                    DropdownMenuItem(value: s.code, child: Text(s.name)),
                ],
                onChanged: (v) {
                  if (v != null) onSelect(v);
                },
              ),
            ),
            Expanded(child: _BoardList(scope: 'subject', boardKey: code)),
          ],
        );
      },
    );
  }
}

/// Hudud tabi: kirgan foydalanuvchining hududi bo'yicha.
class _RegionBoard extends ConsumerWidget {
  const _RegionBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final auth = ref.watch(authControllerProvider);
    final region = auth.user?.regionCode;

    if (!auth.isAuthenticated) {
      return EmptyState(
        icon: Icons.login_rounded,
        title: l.navLeaderboard,
        message: l.lbLoginPrompt,
        actionLabel: l.authLoginTitle,
        onAction: () => LoginSheet.show(context, reason: l.lbLoginPrompt),
      );
    }
    if (region == null || region.isEmpty) {
      return EmptyState(
        icon: Icons.map_outlined,
        title: l.lbRegion,
        message: l.lbRegionNeedsProfileFull,
      );
    }
    return _BoardList(scope: 'region', boardKey: region);
  }
}

class _BoardList extends ConsumerWidget {
  const _BoardList({required this.scope, required this.boardKey});

  final String scope;
  final String? boardKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final auth = ref.watch(authControllerProvider);
    final args = (scope: scope, key: boardKey);
    final async = ref.watch(leaderboardProvider(args));

    return async.when(
      loading: () => const _BoardSkeleton(),
      error: (e, _) => EmptyState(
        icon: Icons.wifi_off_rounded,
        title: l.errNoConnection,
        message: l.authNetworkError,
        actionLabel: l.retry,
        onAction: () => ref.invalidate(leaderboardProvider(args)),
      ),
      data: (data) {
        if (data.entries.isEmpty) {
          return EmptyState(
            icon: Icons.emoji_events_outlined,
            title: l.lbEmptyTitle,
            message: l.lbEmptyHint,
            actionLabel: l.retry,
            onAction: () => ref.invalidate(leaderboardProvider(args)),
          );
        }

        // YOLG'IZ HOLAT. Bitta qatorli "reyting" ma'lumotlar bazasining
        // tasodifan bitta yozuvi qolgan jadvaliga o'xshaydi — mahsulotga
        // emas. Bu holat ATAYLAB boshqacha ko'rsatiladi: o'rin va ball
        // yirik, ostida esa nima uchun ro'yxat bo'shligi tushuntiriladi va
        // buni tuzatadigan yagona harakat taklif qilinadi.
        //
        // Soxta ishtirokchi QO'SHILMAYDI. Bo'shlikni to'ldirish uchun
        // o'ylab topilgan ismlar birinchi qarashda ishlaydi, keyin esa
        // butun reytingga ishonchni yo'q qiladi.
        if (data.entries.length == 1 && data.entries.first.isMe) {
          return _SoloBoard(entry: data.entries.first);
        }

        // Podium faqat uchtadan kam bo'lmaganda mantiqiy: ikkita ishtirokchili
        // "podium" bo'sh va g'alati ko'rinadi.
        final hasPodium = data.entries.length >= 3;
        final top = hasPodium ? data.entries.take(3).toList() : const <LbEntry>[];
        final rest = hasPodium ? data.entries.skip(3).toList() : data.entries;

        return Column(
          children: [
            if (!auth.isAuthenticated) _LoginBanner(message: l.lbLoginPrompt),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(leaderboardProvider(args)),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          Spacing.md, Spacing.md, Spacing.md, Spacing.lg),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          if (hasPodium) ...[
                            _Podium(top: top).enterFade(),
                            const Gap.lg(),
                          ],
                          // Qatorlar yuqoridan pastga ketma-ket ochiladi —
                          // reyting "hisoblanayotgandek" ko'rinadi va ko'z
                          // birinchi o'rinlardan boshlab pastga suriladi.
                          for (final (i, e) in rest.indexed) ...[
                            _Row(entry: e).enterStaggered(i),
                            const Gap.sm(),
                          ],
                        ]),
                      ),
                    ),
                    const FooterSliver(),
                  ],
                ),
              ),
            ),
            if (data.meIsOffPage) _MeCard(entry: data.me!),
          ],
        );
      },
    );
  }
}

/// Reytingda faqat foydalanuvchining o'zi bor.
///
/// Ro'yxat ko'rinishida bu "1 · Siz · 3 ball" degan bitta qator bo'lardi va
/// sahifaning qolgan qismi bo'sh qolardi. Bu yerda esa bo'shlik MA'NOLI:
/// natija yirik ko'rsatiladi, sababi aytiladi va keyingi qadam beriladi.
class _SoloBoard extends ConsumerWidget {
  const _SoloBoard({required this.entry});

  final LbEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final username = ref.watch(authControllerProvider).user?.username;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.xl, Spacing.md, 0),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(Spacing.lg),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: Radii.cardRadius,
                        border: Border.all(color: palette.hairline),
                        boxShadow: Shadows.card(context),
                      ),
                      child: Column(
                        children: [
                          // Medal — bu ekrandagi yagona yirik belgi.
                          const Icon(Icons.emoji_events_rounded,
                              size: 56, color: AppColors.gold),
                          const Gap.md(),
                          Text(l.lbSoloTitle,
                              style: text.headlineSmall,
                              textAlign: TextAlign.center),
                          const Gap.sm(),
                          Text(l.lbPoints(entry.score),
                              style: text.headlineMedium
                                  ?.copyWith(color: scheme.primary)),
                        ],
                      ),
                    ),
                    const Gap.lg(),
                    Text(l.lbSoloHint,
                        style: text.bodyMedium, textAlign: TextAlign.center),
                    const Gap.md(),
                    FilledButton.icon(
                      onPressed: () =>
                          InviteFriendsSheet.show(context, username),
                      icon: const Icon(Icons.person_add_alt_rounded),
                      label: Text(l.lbSoloInvite),
                    ),
                    const Gap.sm(),
                    TextButton(
                      // Reyting bosh ekrandagi mashqdan o'sadi — shu sababli
                      // ikkinchi harakat "Asosiy" tabiga qaytarish.
                      onPressed: () =>
                          ref.read(homeTabProvider.notifier).state = 0,
                      child: Text(l.lbSoloPractice),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const FooterSliver(),
      ],
    );
  }
}

/// TOP-3: 1-o'rin o'rtada va balandroq, 2-chi chapda, 3-chi o'ngda.
class _Podium extends StatelessWidget {
  const _Podium({required this.top});

  /// Aynan uchta element, reyting tartibida (1, 2, 3).
  final List<LbEntry> top;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          Spacing.ms, Spacing.md, Spacing.ms, Spacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: Radii.cardRadius,
      ),
      child: Column(
        children: [
          Text(l.lbPodium, style: text.titleMedium),
          const Gap.md(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                  child: _PodiumSpot(entry: top[1], place: 2, pedestal: 56)),
              Expanded(
                  child: _PodiumSpot(entry: top[0], place: 1, pedestal: 84)),
              Expanded(
                  child: _PodiumSpot(entry: top[2], place: 3, pedestal: 40)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  const _PodiumSpot({
    required this.entry,
    required this.place,
    required this.pedestal,
  });

  final LbEntry entry;
  final int place;

  /// Poydevor balandligi — 1-o'rin eng baland.
  final double pedestal;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final color = switch (place) {
      1 => AppColors.gold,
      2 => AppColors.silver,
      _ => AppColors.bronze,
    };
    final avatar = place == 1 ? 56.0 : 46.0;
    final name = entry.isMe
        ? l.you
        : (entry.displayName?.isNotEmpty == true
            ? entry.displayName!
            : l.lbAnonymous);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (place == 1)
          Icon(Icons.emoji_events_rounded, color: color, size: 22)
        else
          const SizedBox(height: 22),
        const Gap.xs(),
        // Medal rangidagi halqa ICHIDA foydalanuvchining o'z avatari:
        // o'rin (oltin/kumush/bronza) va shaxs (rang + bosh harf) — ikki
        // xil ma'lumot, shuning uchun ikkalasi ham ko'rinadi.
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: UserAvatar(
            name: entry.displayName,
            colorIndex: entry.avatarColor,
            size: avatar,
          ),
        ),
        const Gap.sm(),
        Text(
          name,
          style: text.labelMedium?.copyWith(
              fontWeight: entry.isMe ? FontWeight.w800 : FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const Gap.xs(),
        Text(
          l.lbPoints(entry.score),
          style: text.labelSmall?.copyWith(color: scheme.primary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const Gap.sm(),
        // Poydevor — balandligi o'rinni ko'rsatadi.
        Container(
          height: pedestal,
          margin: const EdgeInsets.symmetric(horizontal: Spacing.xs),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Radii.sm)),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: Spacing.sm),
          child: Text('$place',
              style: text.headlineSmall?.copyWith(color: color)),
        ),
      ],
    );
  }

  // `_initial` olib tashlandi: bosh harfni endi `UserAvatar` o'zi hisoblaydi
  // (`avatarInitials`), ya'ni mantiq bitta joyda.
}

class _Row extends StatelessWidget {
  const _Row({required this.entry});

  final LbEntry entry;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;

    final name = entry.isMe
        ? l.you
        : (entry.displayName?.isNotEmpty == true
            ? entry.displayName!
            : l.lbAnonymous);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.ms),
      decoration: BoxDecoration(
        color: entry.isMe
            ? scheme.primary.withValues(alpha: 0.10)
            : scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(
          color: entry.isMe ? scheme.primary : palette.hairline,
          width: entry.isMe ? 1.4 : 1,
        ),
        // Qatorlar oq fonda "yopishib" turmasin: yengil soya har birini
        // alohida kartochka qilib ko'rsatadi.
        boxShadow: Shadows.card(context),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text('${entry.rank}',
                style: text.labelLarge?.copyWith(color: palette.muted)),
          ),
          UserAvatar(
              name: entry.displayName,
              colorIndex: entry.avatarColor,
              size: 32),
          const Gap.ms(),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: entry.isMe
                  ? text.titleMedium
                  : text.bodyLarge,
            ),
          ),
          const Gap.sm(),
          Text(l.lbPoints(entry.score),
              style: text.labelLarge?.copyWith(color: scheme.primary)),
        ],
      ),
    );
  }
}

/// Foydalanuvchi ro'yxatning ko'rinadigan qismidan tashqarida bo'lsa — pastda
/// yopishib turadigan qator. Skroll qilmasdan o'z o'rnini ko'rsatadi.
class _MeCard extends StatelessWidget {
  const _MeCard({required this.entry});

  final LbEntry entry;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primary.withValues(alpha: 0.10),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.ms),
          child: Row(
            children: [
              Text(l.lbYourRank, style: text.titleMedium),
              const Spacer(),
              Text('#${entry.rank}',
                  style: text.titleMedium?.copyWith(color: scheme.primary)),
              const Gap.ms(),
              Text(l.lbPoints(entry.score), style: text.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginBanner extends StatelessWidget {
  const _LoginBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.login_rounded, color: scheme.primary),
        title: Text(message, style: text.bodySmall),
        trailing: TextButton(
          onPressed: () => LoginSheet.show(context, reason: message),
          child: Text(l.authLoginTitle),
        ),
      ),
    );
  }
}

/// Yuklanish skeleti — podium + uchta qator.
class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        const Skeleton(height: 190, radius: Radii.lg),
        const Gap.lg(),
        for (var i = 0; i < 6; i++) ...[
          const Skeleton(height: 56, radius: Radii.lg),
          const Gap.sm(),
        ],
      ],
    );
  }
}
