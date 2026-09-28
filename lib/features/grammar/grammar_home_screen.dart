import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../mascot/mascot.dart';
import '../../theme/level_palette.dart';
import '../../theme/spacing.dart';
import '../../widgets/language_kit.dart';
import '../language/grammar_topics.dart';
import 'grammar_data.dart';
import 'grammar_practice_screen.dart';

/// Grammatika: daraja bo'yicha o'sish, mavzular ro'yxati, mashq.
///
/// UCHTA ESKI MUAMMO SHU YERDA TUZATILGAN:
///   * Mavzu qatorida radio doira turardi — u "bittasini tanlang" degan
///     ma'no berardi, holbuki qator HOLATNI ko'rsatishi kerak.
///   * Suzuvchi tugma ro'yxatning ustiga chiqib, oxirgi qatorlarni
///     yopib qo'yardi. Endi u pastda, o'z joyida turadi va ro'yxat uning
///     balandligicha pastdan bo'sh joy oladi.
///   * Daraja chiziqlari kulrang va bir xil edi. Endi har bir daraja o'z
///     rangida va yonida "12/34" turadi.
/// Alohida ekran sifatida ochilganda — o'z sarlavhasi bilan.
class GrammarHomeScreen extends StatelessWidget {
  const GrammarHomeScreen({super.key, required this.language});

  final String language;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).grammarTitle)),
        body: GrammarTab(language: language),
      );
}

/// Til ekranidagi "Grammatika" varaqasi.
///
/// Sarlavhasiz va Scaffold'siz: varaqa ichida o'z AppBar'i bo'lsa, ekranda
/// ikkita sarlavha paydo bo'lardi.
class GrammarTab extends ConsumerStatefulWidget {
  const GrammarTab({super.key, required this.language});

  final String language;

  @override
  ConsumerState<GrammarTab> createState() => _GrammarHomeScreenState();
}

const _levels = ['A1', 'A2', 'B1', 'B2'];

class _GrammarHomeScreenState extends ConsumerState<GrammarTab> {
  String? _level;

  GrammarQuery get _query =>
      GrammarQuery(language: widget.language, level: _level);

  Future<void> _practice({String? topic}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GrammarPracticeScreen(
          query: GrammarQuery(
              language: widget.language, level: _level, topic: topic),
        ),
      ),
    );
    ref.invalidate(grammarMasteryProvider(widget.language));
    ref.invalidate(grammarTopicsProvider(_query));
  }

  TopicStatus _statusOf(TopicState s) => switch (s) {
        TopicState.mastered => TopicStatus.done,
        TopicState.unseen => TopicStatus.notStarted,
        _ => TopicStatus.inProgress,
      };

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final signedIn = ref.watch(authControllerProvider).isAuthenticated;
    final topics = ref.watch(grammarTopicsProvider(_query));

    return SafeArea(
      child: ContentWidth(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.md, Spacing.md, Spacing.md, Spacing.md),
                  children: [
                    // ---- daraja filtri ---------------------------------
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _LevelFilter(
                            key: const Key('grammar-level-all'),
                            label: l.vocabAllLevels,
                            selected: _level == null,
                            onTap: () => setState(() => _level = null),
                          ),
                          for (final lv in _levels)
                            _LevelFilter(
                              key: Key('grammar-level-$lv'),
                              label: lv,
                              color: LevelPalette.color(lv, theme.brightness),
                              selected: _level == lv,
                              onTap: () => setState(
                                  () => _level = _level == lv ? null : lv),
                            ),
                        ],
                      ),
                    ),
                    const Gap.md(),

                    if (signedIn)
                      _MasteryCard(
                        language: widget.language,
                        onPractiseTopic: (t) => _practice(topic: t),
                      )
                    else
                      _SignInHint(text: l.grammarSignInBody),
                    const Gap.lg(),

                    // ---- mavzular ---------------------------------------
                    Text(l.grammarTopicsTitle,
                        style: theme.textTheme.titleMedium),
                    const Gap.sm(),
                    topics.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(Spacing.xl),
                        child:
                            Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => OwlEmptyState(
                        state: OwlState.confused,
                        title: l.vocabLoadFailedTitle,
                        message: humanError(e, l),
                        actionLabel: l.retry,
                        onAction: () =>
                            ref.invalidate(grammarTopicsProvider(_query)),
                        size: 96,
                      ),
                      data: (items) => items.isEmpty
                          ? OwlEmptyState(
                              key: const Key('grammar-topics-empty'),
                              state: OwlState.confused,
                              title: l.grammarNoQuestionsTitle,
                              message: l.grammarNoQuestionsBody,
                              size: 96,
                            )
                          : Column(
                              key: const Key('grammar-topics'),
                              children: [
                                for (final t in items)
                                  _TopicRow(
                                    stat: t,
                                    status: _statusOf(t.state),
                                    onTap: () => _practice(topic: t.topic),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),

              // ---- pastdagi tugma ----------------------------------------
              // Ro'yxatning USTIDA emas, ostida: suzuvchi tugma oxirgi
              // qatorlarni yopib qo'yardi.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                    Spacing.md, Spacing.sm, Spacing.md, Spacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                      top: BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                child: PrimaryButton(
                  key: const Key('grammar-start'),
                  label: l.continueAction,
                  icon: Icons.play_arrow_rounded,
                  expand: true,
                  onPressed: () => _practice(),
                ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelFilter extends StatelessWidget {
  const _LevelFilter({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.only(right: Spacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          decoration: BoxDecoration(
            color: selected ? c : c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? c : c.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? cs.onPrimary : c,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow(
      {required this.stat, required this.status, required this.onTap});

  final GrammarTopic stat;
  final TopicStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // O'zbekcha sarlavha + asl atama kichik satrda.
    final named = GrammarTopics.of(stat.topic);
    return TopicTile(
      title: named.title,
      subtitle: named.subtitle,
      level: stat.cefrLevel,
      status: status,
      progress: stat.attempts == 0 ? 0 : (stat.accuracy ?? 0),
      // Savollar SONI emas, o'quvchining o'z natijasi. "50 ta savol"
      // hech narsani hal qilmaydi; "12/18 to'g'ri" esa hal qiladi.
      meta: stat.attempts == 0
          ? l.grammarTopicNotStarted
          : l.grammarTopicScore(stat.correct, stat.attempts),
      onTap: onTap,
    );
  }
}

class _SignInHint extends StatelessWidget {
  const _SignInHint({required this.text});
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
              child: Text(text,
                  style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _MasteryCard extends ConsumerWidget {
  const _MasteryCard({required this.language, required this.onPractiseTopic});

  final String language;
  final void Function(String topic) onPractiseTopic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final m = ref.watch(grammarMasteryProvider(language));

    return m.when(
      loading: () => const SizedBox(
          height: 120, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => _SignInHint(text: humanError(e, l)),
      data: (data) {
        final everythingDone = data.levels.isNotEmpty &&
            data.levels.every((lv) => lv.mastered >= lv.topics);
        return Container(
          key: const Key('grammar-mastery'),
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(Radii.lg),
            border:
                Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l.grammarProgressTitle,
                        style: theme.textTheme.titleMedium),
                  ),
                  // Hamma daraja tugaganda — bitiruv kayfiyati.
                  if (everythingDone)
                    const OwlMascot(OwlMood.achievement, size: 44),
                ],
              ),
              const Gap.sm(),
              for (final lv in data.levels)
                LevelProgressBar(
                  level: lv.cefrLevel,
                  done: lv.mastered,
                  total: lv.topics,
                ),
              if (data.weakTopics.isNotEmpty) ...[
                const Gap.md(),
                Text(l.grammarWeakTitle,
                    style: theme.textTheme.labelLarge),
                const Gap.xs(),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.xs,
                  children: [
                    for (final w in data.weakTopics)
                      ActionChip(
                        key: Key('grammar-weak-${w.topic}'),
                        avatar: const Icon(Icons.trending_down, size: 16),
                        label: Text(
                          GrammarTopics.of(w.topic).title,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () => onPractiseTopic(w.topic),
                      ),
                  ],
                ),
              ] else if (data.nextTopic != null) ...[
                const Gap.md(),
                ActionChip(
                  key: const Key('grammar-next-topic'),
                  avatar: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(GrammarTopics.of(data.nextTopic!).title,
                      overflow: TextOverflow.ellipsis),
                  onPressed: () => onPractiseTopic(data.nextTopic!),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
