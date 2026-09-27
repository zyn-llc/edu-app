import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import 'grammar_data.dart';
import 'grammar_practice_screen.dart';

/// Grammatika: daraja bo'yicha o'sish, mavzular, mashqni boshlash.
class GrammarHomeScreen extends ConsumerStatefulWidget {
  const GrammarHomeScreen({super.key, required this.language});

  final String language;

  @override
  ConsumerState<GrammarHomeScreen> createState() => _GrammarHomeScreenState();
}

const _levels = ['A1', 'A2', 'B1', 'B2'];

class _GrammarHomeScreenState extends ConsumerState<GrammarHomeScreen> {
  String? _level;

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
    ref.invalidate(grammarTopicsProvider(
        GrammarQuery(language: widget.language, level: _level)));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final signedIn = ref.watch(authControllerProvider).isAuthenticated;
    final q = GrammarQuery(language: widget.language, level: _level);
    final topics = ref.watch(grammarTopicsProvider(q));

    return Scaffold(
      appBar: AppBar(title: Text(l.grammarTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('grammar-start'),
        onPressed: () => _practice(),
        icon: const Icon(Icons.play_arrow),
        label: Text(l.grammarStart),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.md, Spacing.md, 96),
        children: [
          // ---- daraja filtri -------------------------------------------
          Wrap(
            spacing: Spacing.xs,
            children: [
              FilterChip(
                key: const Key('grammar-level-all'),
                label: Text(l.vocabAllLevels),
                selected: _level == null,
                onSelected: (_) => setState(() => _level = null),
              ),
              for (final lv in _levels)
                FilterChip(
                  key: Key('grammar-level-$lv'),
                  label: Text(lv),
                  selected: _level == lv,
                  onSelected: (_) =>
                      setState(() => _level = _level == lv ? null : lv),
                ),
            ],
          ),
          const Gap.md(),

          // ---- o'sish ---------------------------------------------------
          if (signedIn) _MasteryCard(language: widget.language,
              onPractiseTopic: (t) => _practice(topic: t))
          else
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Text(l.grammarSignInBody,
                    style: theme.textTheme.bodySmall),
              ),
            ),
          const Gap.lg(),

          // ---- mavzular -------------------------------------------------
          Text(l.grammarTopicsTitle, style: theme.textTheme.titleMedium),
          const Gap.sm(),
          topics.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => EmptyState(
              icon: Icons.cloud_off,
              title: l.vocabLoadFailedTitle,
              message: humanError(e, l),
              actionLabel: l.retry,
              onAction: () => ref.invalidate(grammarTopicsProvider(q)),
              compact: true,
            ),
            data: (items) => items.isEmpty
                ? EmptyState(
                    key: const Key('grammar-topics-empty'),
                    icon: Icons.search_off,
                    title: l.grammarNoQuestionsTitle,
                    message: l.grammarNoQuestionsBody,
                    compact: true,
                  )
                : Column(
                    key: const Key('grammar-topics'),
                    children: [
                      for (final t in items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: _StateDot(t.state),
                          title: Text(t.topic,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(t.attempts == 0
                              ? l.grammarTopicUnseen(t.questions)
                              : l.grammarTopicSeen(
                                  t.correct, t.attempts, t.questions)),
                          trailing: const Icon(Icons.play_circle_outline),
                          onTap: () => _practice(topic: t.topic),
                        ),
                    ],
                  ),
          ),
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
      loading: () => const Card(
        margin: EdgeInsets.zero,
        child: SizedBox(
            height: 90, child: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Text(humanError(e, l)),
        ),
      ),
      data: (data) => Card(
        key: const Key('grammar-mastery'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.grammarProgressTitle,
                  style: theme.textTheme.titleMedium),
              const Gap.sm(),
              for (final lv in data.levels) ...[
                Row(children: [
                  SizedBox(width: 34, child: Text(lv.cefrLevel)),
                  Expanded(
                    child: LinearProgressIndicator(value: lv.shareMastered),
                  ),
                  const SizedBox(width: Spacing.sm),
                  // Mavzular bo'yicha, savollar bo'yicha EMAS: o'quvchi
                  // "shart gaplarni bildim" deb o'ylaydi.
                  Text('${lv.mastered}/${lv.topics}',
                      style: theme.textTheme.bodySmall),
                ]),
                const Gap.xs(),
              ],
              if (data.weakTopics.isNotEmpty) ...[
                const Gap.sm(),
                Text(l.grammarWeakTitle, style: theme.textTheme.labelLarge),
                const Gap.xs(),
                for (final w in data.weakTopics)
                  ActionChip(
                    key: Key('grammar-weak-${w.topic}'),
                    avatar: const Icon(Icons.trending_down, size: 16),
                    label: Text(
                      '${w.topic}  ${((w.accuracy ?? 0) * 100).round()}%',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => onPractiseTopic(w.topic),
                  ),
              ] else if (data.nextTopic != null) ...[
                const Gap.sm(),
                ActionChip(
                  key: const Key('grammar-next-topic'),
                  avatar: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(data.nextTopic!,
                      overflow: TextOverflow.ellipsis),
                  onPressed: () => onPractiseTopic(data.nextTopic!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StateDot extends StatelessWidget {
  const _StateDot(this.state);

  final TopicState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, colour) = switch (state) {
      TopicState.mastered => (Icons.check_circle, cs.primary),
      TopicState.weak => (Icons.error_outline, cs.error),
      TopicState.learning => (Icons.timelapse, cs.tertiary),
      TopicState.unseen => (Icons.circle_outlined, cs.outlineVariant),
    };
    return Icon(icon, color: colour);
  }
}
