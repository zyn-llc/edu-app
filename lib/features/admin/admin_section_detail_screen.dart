import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import '../subjects/subjects.dart';
import 'admin_sections_data.dart';

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
    final input = await showDialog<_BlockInput>(
      context: context,
      builder: (_) => const _AddBlockDialog(),
    );
    if (input == null || !mounted) return;
    await _run(() async {
      await ref.read(adminSectionsRepositoryProvider).addBlock(
            _id,
            subjectId: input.subjectId,
            grade: input.grade,
            questionCount: input.questionCount,
            timeLimitSec: input.minutes * 60,
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
                      ' · ${(b.timeLimitSec / 60).round()} daqiqa',
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
  const _BlockInput(
      this.subjectId, this.grade, this.questionCount, this.minutes);
}

class _AddBlockDialog extends ConsumerStatefulWidget {
  const _AddBlockDialog();

  @override
  ConsumerState<_AddBlockDialog> createState() => _AddBlockDialogState();
}

class _AddBlockDialogState extends ConsumerState<_AddBlockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _countCtrl = TextEditingController(text: '20');
  final _minutesCtrl = TextEditingController(text: '30');
  String? _subjectId;
  int? _grade;

  @override
  void dispose() {
    _countCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(subjectsProvider);

    return AlertDialog(
      title: const Text('Blok qo\'shish'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  onChanged: (v) => setState(() => _subjectId = v),
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
                onChanged: (v) => setState(() => _grade = v),
              ),
              TextFormField(
                controller: _countCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Savollar soni'),
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor')),
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
              ),
            );
          },
          child: const Text('Qo\'shish'),
        ),
      ],
    );
  }
}
