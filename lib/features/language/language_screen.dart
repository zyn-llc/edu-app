import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../mascot/mascot.dart';
import '../../theme/spacing.dart';
import '../../theme/subject_palette.dart';
import '../../widgets/language_kit.dart';
import '../grammar/grammar_home_screen.dart';
import '../reading/reading_list_screen.dart';
import '../vocab/vocab_browse_screen.dart';
import '../vocab/vocab_data.dart';
import '../vocab/vocab_review_screen.dart';
import 'display_names.dart';

/// Bitta til — uchta varaqa: Grammatika | So'zlar | Takrorlash.
///
/// NEGA VARAQA. Ilgari til bo'limi tilni tanlaydigan chip qatori bilan
/// boshlanardi, keyin esa tugmalar ro'yxati kelardi — ya'ni o'quvchi
/// nimadir qilishdan oldin ikki marta tanlashi kerak edi va ekran
/// ilovaning qolgan qismiga o'xshamasdi. Til endi fan kartasi orqali
/// tanlanadi, bu yerda esa faqat "nima qilaman" degan savol qoladi.
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key, required this.language});

  final String language;

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final accent = SubjectPalette.of('lang_${widget.language}')
        .color(Theme.of(context).brightness);

    return Scaffold(
      appBar: AppBar(
        title: Text(DisplayNames.language(widget.language, l)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: accent,
          labelColor: accent,
          tabs: [
            Tab(text: l.grammarTitle),
            Tab(text: l.vocabWordsTab),
            Tab(text: l.vocabReviewTitle),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          GrammarTab(language: widget.language),
          _WordsTab(language: widget.language),
          _ReviewTab(language: widget.language),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  So'zlar                                                                     //
// --------------------------------------------------------------------------- //
class _WordsTab extends ConsumerWidget {
  const _WordsTab({required this.language});

  final String language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final signedIn = ref.watch(authControllerProvider).isAuthenticated;
    final stats = ref.watch(vocabStatsProvider(language));

    return SafeArea(
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            // ---- uchta ko'rsatkich -------------------------------------
            stats.when(
              loading: () => const SizedBox(
                  height: 108,
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => _Hint(
                  text: signedIn ? humanError(e, l) : l.vocabSignInBody),
              data: (s) => Row(
                key: const Key('vocab-stats'),
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.local_fire_department_outlined,
                      value: '${s.dueToday}',
                      label: l.vocabDueToday,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      icon: Icons.menu_book_outlined,
                      value: '${s.deckSize}',
                      label: l.vocabDeckSize,
                      color: cs.tertiary,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      icon: Icons.verified_outlined,
                      value: '${s.mastered}',
                      label: l.vocabMastered,
                      color: cs.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const Gap.md(),

            // ---- bugungi takrorlash ------------------------------------
            stats.maybeWhen(
              data: (s) => _TodayCard(language: language, due: s.dueToday),
              orElse: () => const SizedBox.shrink(),
            ),
            const Gap.md(),

            _ActionTile(
              key: const Key('vocab-open-browse'),
              icon: Icons.school_outlined,
              title: l.vocabMemorise,
              subtitle: l.vocabMemoriseBody,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => VocabBrowseScreen(language: language)),
              ).then((_) => ref.invalidate(vocabStatsProvider(language))),
            ),
            const Gap.sm(),
            _ActionTile(
              icon: Icons.library_books_outlined,
              title: l.vocabBrowseAction,
              subtitle: l.vocabBrowseBody,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => VocabBrowseScreen(language: language)),
              ),
            ),
            const Gap.sm(),
            // O'qish varaqaga sig'madi (uchtasi so'ralgan), lekin bo'lim
            // yo'qolmasligi kerak — shuning uchun shu yerda.
            _ActionTile(
              key: const Key('open-reading'),
              icon: Icons.menu_book_rounded,
              title: l.readingOpen,
              subtitle: l.readingTileBody,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ReadingListScreen(language: language)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bugungi takrorlash — bo'lim boshidagi asosiy karta.
///
/// Nol bo'lsa ham KARTA QOLADI, faqat kayfiyati boshqa: bo'sh joy
/// "hech narsa yo'q" emas, "nimadir buzilgan" degan taassurot beradi.
class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.language, required this.due});

  final String language;
  final int due;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final none = due == 0;

    return Container(
      key: const Key('vocab-today'),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: none
              ? [cs.surfaceContainerHigh, cs.surfaceContainerLow]
              : [
                  cs.primary.withValues(alpha: 0.16),
                  cs.primary.withValues(alpha: 0.04),
                ],
        ),
        border: Border.all(
            color: none ? cs.outlineVariant : cs.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          BreathingOwl(
            // Ish tugagan — tinch; ish bor — bayramga tayyor.
            state: none ? OwlState.sleeping : OwlState.cheering,
            size: 76,
          ),
          const Gap.ms(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  none ? l.vocabNothingDueTitle : l.vocabDueCount(due),
                  style: theme.textTheme.titleMedium,
                ),
                const Gap.xs(),
                Text(
                  none ? l.vocabNothingDueBody : l.vocabDueBody,
                  style: theme.textTheme.bodySmall,
                ),
                if (!none) ...[
                  const Gap.sm(),
                  PrimaryButton(
                    key: const Key('vocab-start-review'),
                    label: l.vocabStartReviewShort,
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              VocabReviewScreen(language: language)),
                    ).then(
                        (_) => ref.invalidate(vocabStatsProvider(language))),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  Takrorlash varaqasi                                                         //
// --------------------------------------------------------------------------- //
class _ReviewTab extends ConsumerWidget {
  const _ReviewTab({required this.language});

  final String language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final stats = ref.watch(vocabStatsProvider(language));

    return SafeArea(
      child: ContentWidth(
        child: stats.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: OwlEmptyState(
              state: OwlState.idle,
              title: l.vocabSignInTitle,
              message: humanError(e, l),
            ),
          ),
          data: (s) => s.dueToday == 0
              ? Center(
                  child: OwlEmptyState(
                    key: const Key('review-none'),
                    state: OwlState.sleeping,
                    title: l.vocabNothingDueTitle,
                    message: l.vocabNothingDueBody,
                    actionLabel: l.vocabMemorise,
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              VocabBrowseScreen(language: language)),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(Spacing.md),
                  children: [
                    _TodayCard(language: language, due: s.dueToday),
                    const Gap.lg(),
                    Text(l.vocabLevelsTitle,
                        style: Theme.of(context).textTheme.titleMedium),
                    const Gap.sm(),
                    _DeckBreakdown(stats: s),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DeckBreakdown extends StatelessWidget {
  const _DeckBreakdown({required this.stats});

  final VocabStats stats;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _Bar(label: l.vocabLearning, value: stats.learning,
            total: stats.deckSize, color: cs.tertiary),
        _Bar(label: l.vocabInReview, value: stats.review,
            total: stats.deckSize, color: cs.primary),
        _Bar(label: l.vocabMastered, value: stats.mastered,
            total: stats.deckSize, color: cs.secondary),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = total == 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          SizedBox(
              width: 104,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: v),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              builder: (_, x, __) => ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: x,
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.16),
                ),
              ),
            ),
          ),
          const Gap.sm(),
          Text('$value', style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const Gap.ms(),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          const BreathingOwl(state: OwlState.idle, size: 48),
          const Gap.ms(),
          Expanded(
              child:
                  Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
