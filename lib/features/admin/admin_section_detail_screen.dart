import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import '../quiz/quiz_data.dart';
import '../subjects/subjects.dart';
import 'admin_sections_data.dart';
import 'admin_sections_screen.dart' show removeSection;

/// Admin: one live section — blocks, bank check, publish.
///
/// This is what makes a section hostable. Creating it is not enough: a
/// section with no blocks can never be published, because `publish` refuses
/// it (and would have nothing to serve). The flow is:
///
///     yarating -> blok qo'shing -> bank tekshiruvi -> e'lon qiling
///
/// Uzbek-only strings: staff screen, like the rest of the admin surface.
class AdminSectionDetailScreen extends ConsumerStatefulWidget {
  const AdminSectionDetailScreen({super.key, required this.sectionId});

  final String sectionId;

  @override
  ConsumerState<AdminSectionDetailScreen> createState() =>
      _AdminSectionDetailScreenState();
}

class _AdminSectionDetailScreenState
    extends ConsumerState<AdminSectionDetailScreen> {
  PreviewResult? _preview;
  bool _busy = false;

  String get _id => widget.sectionId;

  void _refresh() {
    ref.invalidate(adminSectionDetailProvider(_id));
    ref.invalidate(adminSectionsProvider);
  }

  /// The server's `detail` is the useful part of a 400/409 here — it says
  /// which rule was broken ("kamida bitta blok kerak", "savol yetarli emas").
  void _showError(Object e) {
    if (!mounted) return;
    String msg = 'Amal bajarilmadi';
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) {
        msg = data['detail'] as String;
      } else if (data is Map && data['title'] is String) {
        msg = data['title'] as String;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addBlock() async {
    final input = await showModalBottomSheet<_BlockInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddBlockSheet(),
    );
    if (input == null || !mounted) return;
    await _run(() async {
      await ref.read(adminSectionsRepositoryProvider).addBlock(
            _id,
            subjectId: input.subjectId,
            grade: input.grade,
            questionCount: input.questionCount,
            timeLimitSec: input.minutes * 60,
            topicIds: input.topicIds,
          );
      setState(() => _preview = null); // blocks changed -> old check is stale
      _refresh();
    });
  }

  Future<void> _deleteBlock(String blockId) => _run(() async {
        await ref
            .read(adminSectionsRepositoryProvider)
            .deleteBlock(_id, blockId);
        setState(() => _preview = null);
        _refresh();
      });

  Future<void> _runPreview() => _run(() async {
        final r = await ref.read(adminSectionsRepositoryProvider).preview(_id);
        if (mounted) setState(() => _preview = r);
      });

  Future<void> _publish() => _run(() async {
        await ref.read(adminSectionsRepositoryProvider).publish(_id);
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('E\'lon qilindi — o\'quvchilar ro\'yxatdan '
                'o\'ta boshlashi mumkin'),
          ));
        }
      });

  Future<void> _remove(AdminSectionDetail s) async {
    await removeSection(context, ref, s);
    // Gone from the list either way (deleted or archived), so this screen
    // has nothing left to show.
    if (mounted) Navigator.pop(context);
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sinovni bekor qilish'),
        content: const Text(
            'Bekor qilingan sinovni qaytarib bo\'lmaydi. Davom etilsinmi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Yo\'q')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Bekor qilish')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await ref.read(adminSectionsRepositoryProvider).cancel(_id);
      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminSectionDetailProvider(_id));
    final subjects = ref.watch(subjectsProvider).valueOrNull ?? const [];
    final names = {for (final s in subjects) s.id: s.name};

    return Scaffold(
      appBar: AppBar(title: const Text('Sinov')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: EmptyState(
            icon: Icons.wifi_off,
            title: 'Yuklanmadi',
            message: 'Sinov ma\'lumotini olib bo\'lmadi.',
            actionLabel: 'Qayta urinish',
            onAction: _refresh,
          ),
        ),
        data: (s) => ListView(
          padding: Spacing.page(context),
          children: [
            _Header(section: s),
            const Gap.md(),

            Row(
              children: [
                Text('Bloklar', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (s.isDraft)
                  TextButton.icon(
                    onPressed: _busy ? null : _addBlock,
                    icon: const Icon(Icons.add),
                    label: const Text('Blok qo\'shish'),
                  ),
              ],
            ),
            if (s.blocks.isEmpty)
              const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.all(Spacing.md),
                  child: Text(
                    'Blok yo\'q. Kamida bitta blok qo\'shmasdan sinovni '
                    'e\'lon qilib bo\'lmaydi.',
                  ),
                ),
              )
            else
              for (final b in s.blocks)
                Card(
                  margin: const EdgeInsets.only(bottom: Spacing.sm),
                  child: ListTile(
                    title: Text(names[b.subjectId] ?? 'Fan'),
                    subtitle: Text(
                      '${b.grade == null ? "Barcha sinflar" : "${b.grade}-sinf"}'
                      ' · ${b.questionCount} savol'
                      ' · ${(b.timeLimitSec / 60).round()} daqiqa'
                      '${b.topicIds.isEmpty ? "" : " · ${b.topicIds.length} mavzu"}',
                    ),
                    trailing: s.isDraft
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed:
                                _busy ? null : () => _deleteBlock(b.id),
                          )
                        : null,
                  ),
                ),

            const Gap.md(),
            if (_preview != null) _PreviewPanel(result: _preview!, names: names),

            const Gap.md(),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || s.blocks.isEmpty ? null : _runPreview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Bank tekshiruvi'),
                ),
                if (s.isDraft)
                  FilledButton.icon(
                    onPressed: _busy || !s.canPublish ? null : _publish,
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('E\'lon qilish'),
                  ),
                if (s.canCancel)
                  TextButton.icon(
                    onPressed: _busy ? null : _cancel,
                    icon: const Icon(Icons.block),
                    label: const Text('Bekor qilish'),
                  ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _remove(s),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text("Olib tashlash"),
                ),
              ],
            ),
            if (s.isDraft)
              const Padding(
                padding: EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  'E\'lon qilingandan keyin sinovni tahrirlab bo\'lmaydi — '
                  'o\'quvchi boshqa shartlarga tayyorlanib qolmasligi uchun.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.section});
  final AdminSectionDetail section;

  static String fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = section;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title, style: theme.textTheme.titleLarge),
            const Gap.xs(),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                Chip(
                  label: Text(s.status),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: const Icon(Icons.school_outlined, size: 16),
                  label: Text(s.school?.label ?? 'Barcha maktablar'),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: const Icon(Icons.groups_outlined, size: 16),
                  label: Text(s.classes.isEmpty
                      ? 'Barcha sinflar'
                      : s.classes.join(', ')),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const Gap.xs(),
            Text('Boshlanishi: ${fmt(s.startAt)}',
                style: theme.textTheme.bodySmall),
            Text('Tugashi: ${fmt(s.endAt)}', style: theme.textTheme.bodySmall),
            const Gap.xs(),
            Text('${s.registrationCount} ro\'yxatdan o\'tgan · '
                '${s.attemptCount} urinish'),
          ],
        ),
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.result, required this.names});
  final PreviewResult result;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(result.ok ? Icons.check_circle : Icons.error_outline,
                    color: result.ok
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    result.ok
                        ? 'Bank yetarli — e\'lon qilsa bo\'ladi'
                        : result.reason ?? 'Savol yetarli emas',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            for (final b in result.blocks) ...[
              const Gap.sm(),
              Text(
                '${b.requested} ta so\'raldi · ${b.available} ta mavjud'
                '${b.enough ? "" : "  ← yetmaydi"}',
                style: TextStyle(
                    color: b.enough ? null : theme.colorScheme.error),
              ),
              if (!b.mixSatisfied)
                for (final band in b.bands)
                  if (band.short > 0)
                    Text(
                      '   ${band.band}: ${band.available}/${band.wanted} '
                      '(${band.short} ta kam)',
                      style: theme.textTheme.bodySmall,
                    ),
            ],
            if (!result.ok) ...[
              const Gap.sm(),
              Text(
                'Savol sonini kamaytiring yoki boshqa fan/sinf tanlang. '
                'Qiyinlik taqsimoti to\'lmasa ham sinov o\'tadi — server '
                'yetishmagan darajani boshqasidan to\'ldiradi.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  Blok qo'shish                                                               //
// --------------------------------------------------------------------------- //
class _BlockInput {
  final String subjectId;
  final int? grade;
  final int questionCount;
  final int minutes;

  /// Empty = the whole subject.
  final List<String> topicIds;

  const _BlockInput(this.subjectId, this.grade, this.questionCount,
      this.minutes, this.topicIds);
}

/// Fan -> sinf -> (ixtiyoriy) mavzular.
///
/// A bottom sheet rather than a dialog because the topic list is long — maths
/// grade 6 alone has 63 topics, which a dialog cannot show.
class _AddBlockSheet extends ConsumerStatefulWidget {
  const _AddBlockSheet();

  @override
  ConsumerState<_AddBlockSheet> createState() => _AddBlockSheetState();
}

class _AddBlockSheetState extends ConsumerState<_AddBlockSheet> {
  final _formKey = GlobalKey<FormState>();
  final _countCtrl = TextEditingController(text: '20');
  final _minutesCtrl = TextEditingController(text: '30');
  String? _subjectId;
  int? _grade;
  final Set<String> _topicIds = {};

  @override
  void dispose() {
    _countCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  /// Subject or grade changed -> the old picks may not exist in the new
  /// catalogue, and the server rejects a topic outside the subject.
  void _resetTopics() => _topicIds.clear();

  int get _requested => int.tryParse(_countCtrl.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = ref.watch(subjectsProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Blok qo\'shish', style: theme.textTheme.titleLarge),
              const Gap.md(),
              subjects.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Fanlar yuklanmadi'),
                data: (rows) => DropdownButtonFormField<String>(
                  initialValue: _subjectId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Fan'),
                  items: [
                    for (final s in rows)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  validator: (v) => v == null ? 'Fanni tanlang' : null,
                  onChanged: (v) => setState(() {
                    _subjectId = v;
                    _resetTopics();
                  }),
                ),
              ),
              DropdownButtonFormField<int?>(
                initialValue: _grade,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sinf'),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Barcha sinflar')),
                  for (var g = 1; g <= 11; g++)
                    DropdownMenuItem<int?>(value: g, child: Text('$g-sinf')),
                ],
                onChanged: (v) => setState(() {
                  _grade = v;
                  _resetTopics();
                }),
              ),
              TextFormField(
                controller: _countCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Savollar soni'),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null) return 'Raqam kiriting';
                  if (n < 1 || n > 200) return '1 dan 200 gacha';
                  return null;
                },
              ),
              TextFormField(
                controller: _minutesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Vaqt (daqiqa)'),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null) return 'Raqam kiriting';
                  // Server chegarasi: 30..14400 soniya.
                  if (n < 1 || n > 240) return '1 dan 240 daqiqagacha';
                  return null;
                },
              ),
              const Gap.md(),
              if (_subjectId != null) _topics(theme),
              const Gap.md(),
              FilledButton(
                onPressed: () {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
                  Navigator.pop(
                    context,
                    _BlockInput(
                      _subjectId!,
                      _grade,
                      int.parse(_countCtrl.text.trim()),
                      int.parse(_minutesCtrl.text.trim()),
                      _topicIds.toList(),
                    ),
                  );
                },
                child: const Text('Qo\'shish'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topics(ThemeData theme) {
    // The catalogue is already filtered by subject AND grade, so picking
    // "9-sinf matematika" offers exactly that grade's topics.
    final async =
        ref.watch(catalogProvider((subjectId: _subjectId!, grade: _grade)));

    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const Text('Mavzular yuklanmadi'),
      data: (cat) {
        if (cat.topics.isEmpty) {
          return Text('Bu fan va sinf uchun mavzu belgilanmagan — '
              'blok butun fandan oladi.',
              style: theme.textTheme.bodySmall);
        }
        final available = cat.topics
            .where((t) => _topicIds.contains(t.id))
            .fold<int>(0, (sum, t) => sum + t.count);
        final short = _topicIds.isNotEmpty && available < _requested;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Mavzular', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (_topicIds.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_resetTopics),
                    child: const Text('Tozalash'),
                  ),
              ],
            ),
            Text(
              _topicIds.isEmpty
                  ? 'Bo\'sh qoldirilsa — butun fandan olinadi.'
                  : '$available ta savol tanlangan mavzularda',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: short ? theme.colorScheme.error : null),
            ),
            if (short)
              Text(
                'So\'ralgani $_requested ta — savol sonini kamaytiring yoki '
                'yana mavzu qo\'shing, aks holda e\'lon qilib bo\'lmaydi.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            const Gap.sm(),
            Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xs,
              children: [
                for (final t in cat.topics)
                  FilterChip(
                    label: Text('${t.title} (${t.count})'),
                    selected: _topicIds.contains(t.id),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _topicIds.add(t.id);
                      } else {
                        _topicIds.remove(t.id);
                      }
                    }),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
