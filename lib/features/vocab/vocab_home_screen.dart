import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/api_error.dart';
import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import 'vocab_browse_screen.dart';
import 'vocab_data.dart';
import 'vocab_review_screen.dart';

/// Til moduli: tilni tanlash, to'plam holati, takrorlashni boshlash.
class VocabHomeScreen extends ConsumerWidget {
  const VocabHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final uiLang = ref.watch(localeCodeProvider);
    final langs = ref.watch(vocabLanguagesProvider);
    final selected = ref.watch(selectedLanguageProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.vocabTitle)),
      body: langs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: EmptyState(
            icon: Icons.cloud_off,
            title: l.vocabLoadFailedTitle,
            message: humanError(e, l),
            actionLabel: l.retry,
            onAction: () => ref.invalidate(vocabLanguagesProvider),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: EmptyState(
                icon: Icons.translate,
                title: l.vocabNoLanguagesTitle,
                message: l.vocabNoLanguagesBody,
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Text(l.vocabPickLanguage,
                  style: Theme.of(context).textTheme.titleMedium),
              const Gap.sm(),
              Wrap(
                spacing: Spacing.sm,
                children: [
                  for (final lang in items)
                    ChoiceChip(
                      key: Key('vocab-lang-${lang.code}'),
                      label: Text('${lang.name(uiLang)} (${lang.vocabCount})'),
                      selected: selected == lang.code,
                      onSelected: (_) => ref
                          .read(selectedLanguageProvider.notifier)
                          .state = lang.code,
                    ),
                ],
              ),
              const Gap.lg(),
              if (selected == null)
                EmptyState(
                  key: const Key('vocab-pick-first'),
                  icon: Icons.translate,
                  title: l.vocabPickLanguage,
                  message: l.vocabPickLanguageBody,
                  compact: true,
                )
              else
                _LanguageBody(language: selected),
            ],
          );
        },
      ),
    );
  }
}

class _LanguageBody extends ConsumerWidget {
  const _LanguageBody({required this.language});

  final String language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final signedIn = ref.watch(authControllerProvider).isAuthenticated;
    final stats = ref.watch(vocabStatsProvider(language));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: stats.when(
              loading: () => const SizedBox(
                  height: 64, child: Center(child: CircularProgressIndicator())),
              // Kirmagan foydalanuvchida to'plam YO'Q — bu xato emas, shuning
              // uchun xato matni emas, taklif ko'rsatiladi.
              error: (e, _) => Text(
                  signedIn ? humanError(e, l) : l.vocabSignInBody,
                  key: const Key('vocab-stats-error')),
              data: (s) => Column(
                key: const Key('vocab-stats'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Stat(l.vocabDueToday, '${s.dueToday}'),
                      _Stat(l.vocabDeckSize, '${s.deckSize}'),
                      _Stat(l.vocabMastered, '${s.mastered}'),
                    ],
                  ),
                  if (s.deckSize > 0) ...[
                    const Gap.md(),
                    LinearProgressIndicator(value: s.masteredShare),
                  ],
                  const Gap.md(),
                  FilledButton.icon(
                    key: const Key('vocab-start-review'),
                    icon: const Icon(Icons.style_outlined),
                    label: Text(s.dueToday > 0
                        ? l.vocabStartReview(s.dueToday)
                        : l.vocabNothingDueTitle),
                    onPressed: s.dueToday == 0
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    VocabReviewScreen(language: language),
                              ),
                            ).then((_) {
                              ref.invalidate(vocabStatsProvider(language));
                            }),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Gap.md(),
        OutlinedButton.icon(
          key: const Key('vocab-open-browse'),
          icon: const Icon(Icons.menu_book_outlined),
          label: Text(l.vocabBrowseAction),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => VocabBrowseScreen(language: language)),
          ).then((_) => ref.invalidate(vocabStatsProvider(language))),
        ),
        if (!signedIn) ...[
          const Gap.md(),
          Text(l.vocabSignInBody,
              style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(value, style: t.headlineSmall),
        Text(label, style: t.bodySmall),
      ],
    );
  }
}
