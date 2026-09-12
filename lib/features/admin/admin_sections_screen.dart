import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/geo_picker.dart';
import '../geo/geo_data.dart';

/// Admin: live sections list + the "Yangi sinov" creation modal.
///
/// Scope is deliberately narrow — enough to create a section with an optional
/// fixed school, which is what migration 040 added. Blocks, preview, publish
/// and the participation report belong to the live-sections rebuild
/// (MOBILE_ARCHITECTURE.md §8).
///
/// Uzbek-only strings: staff screen, same as the rest of the admin surface.

class AdminSection {
  final String id;
  final String title;
  final String status;
  final DateTime startAt;
  final DateTime endAt;
  final String? schoolId;
  final GeoSchool? school;

  const AdminSection({
    required this.id,
    required this.title,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.schoolId,
    required this.school,
  });

  factory AdminSection.fromJson(Map<String, dynamic> j) => AdminSection(
        id: j['id'] as String,
        title: j['title'] as String,
        status: j['status'] as String? ?? 'draft',
        startAt: DateTime.parse(j['start_at'] as String).toLocal(),
        endAt: DateTime.parse(j['end_at'] as String).toLocal(),
        schoolId: j['school_id'] as String?,
        school: j['school'] == null
            ? null
            : GeoSchool.fromJson(j['school'] as Map<String, dynamic>),
      );
}

class AdminSectionsRepository {
  final Ref ref;
  AdminSectionsRepository(this.ref);

  Future<List<AdminSection>> list() async {
    final res = await ref.read(dioProvider).get('/v1/admin/live-sections');
    final items = (res.data as Map<String, dynamic>)['items'] as List;
    return [
      for (final e in items) AdminSection.fromJson(e as Map<String, dynamic>)
    ];
  }

  /// `schoolId == null` -> open to every school. §8: omit or send null.
  Future<AdminSection> create({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String? schoolId,
  }) async {
    final res = await ref.read(dioProvider).post('/v1/admin/live-sections', data: {
      'title': title,
      'start_at': startAt.toUtc().toIso8601String(),
      'end_at': endAt.toUtc().toIso8601String(),
      if (schoolId != null) 'school_id': schoolId,
    });
    return AdminSection.fromJson(res.data as Map<String, dynamic>);
  }
}

final adminSectionsRepositoryProvider =
    Provider<AdminSectionsRepository>((ref) => AdminSectionsRepository(ref));

final adminSectionsProvider = FutureProvider<List<AdminSection>>((ref) async {
  ref.watch(authControllerProvider);
  return ref.read(adminSectionsRepositoryProvider).list();
});

class AdminSectionsScreen extends ConsumerWidget {
  const AdminSectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminSectionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Jonli sinovlar')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await NewSectionSheet.show(context);
          if (created == true) ref.invalidate(adminSectionsProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('Yangi sinov'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: EmptyState(
            icon: Icons.wifi_off,
            title: 'Yuklanmadi',
            message: 'Ro\'yxatni olib bo\'lmadi.',
            actionLabel: 'Qayta urinish',
            onAction: () => ref.invalidate(adminSectionsProvider),
          ),
        ),
        data: (rows) => rows.isEmpty
            ? const Center(
                child: EmptyState(
                  icon: Icons.event_note_outlined,
                  title: 'Sinov yo\'q',
                  message: '«Yangi sinov» tugmasi bilan birinchisini yarating.',
                ),
              )
            : ListView.builder(
                padding: Spacing.page(context),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final s = rows[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: Spacing.sm),
                    child: ListTile(
                      title: Text(s.title),
                      subtitle: Text(
                        s.school == null
                            ? '${s.status} · barcha maktablar'
                            : '${s.status} · ${s.school!.label}',
                      ),
                      trailing: s.school == null
                          ? null
                          : const Icon(Icons.school_outlined),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  "Yangi sinov" modal                                                         //
// --------------------------------------------------------------------------- //
class NewSectionSheet extends ConsumerStatefulWidget {
  const NewSectionSheet({super.key});

  static Future<bool?> show(BuildContext context) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const NewSectionSheet(),
      );

  @override
  ConsumerState<NewSectionSheet> createState() => _NewSectionSheetState();
}

class _NewSectionSheetState extends ConsumerState<NewSectionSheet> {
  final _titleCtrl = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  String? _schoolId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _titleCtrl.text.trim().length >= 3 &&
      _start != null &&
      _end != null &&
      _end!.isAfter(_start!);

  Future<void> _pick({required bool start}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: start ? now : (_start ?? now),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    final dt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => start ? _start = dt : _end = dt);
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminSectionsRepositoryProvider).create(
            title: _titleCtrl.text.trim(),
            startAt: _start!,
            endAt: _end!,
            schoolId: _schoolId, // null -> open to every school
          );
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final data = e.response?.data;
      setState(() => _error = data is Map && data['detail'] is String
          ? data['detail'] as String
          : 'Saqlanmadi');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final region = ref.watch(authControllerProvider).user?.regionCode;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Yangi sinov', style: theme.textTheme.titleLarge),
            const Gap.md(),
            TextField(
              controller: _titleCtrl,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Sarlavha'),
              onChanged: (_) => setState(() {}),
            ),
            const Gap.sm(),
            _DateTile(
              label: 'Boshlanishi',
              value: _start,
              onTap: _busy ? null : () => _pick(start: true),
            ),
            _DateTile(
              label: 'Tugashi',
              value: _end,
              onTap: _busy ? null : () => _pick(start: false),
            ),
            if (_start != null && _end != null && !_end!.isAfter(_start!))
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text('Tugash vaqti boshlanishdan keyin bo\'lsin',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            const Gap.md(),

            // ---- optional fixed school (040) -------------------------------
            // Left empty = open competition, exactly as before this change.
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Maktab (ixtiyoriy)',
                  style: theme.textTheme.labelLarge),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tanlansa, barcha ishtirokchilar shu maktabga yoziladi va '
                'ulardan maktab so\'ralmaydi. Bo\'sh qoldirilsa — har kim '
                'o\'z maktabini tanlaydi.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const Gap.sm(),
            GeoPicker(
              key: const Key('new-section-school-picker'),
              target: GeoTarget.school,
              initialRegionCode: region,
              enabled: !_busy,
              onChanged: (id) => setState(() => _schoolId = id),
            ),
            if (_schoolId != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => setState(() => _schoolId = null),
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Maktabni olib tashlash'),
                ),
              ),

            if (_error != null) ...[
              const Gap.sm(),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const Gap.md(),
            FilledButton(
              onPressed: _valid && !_busy ? _create : null,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Yaratish'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.value, this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback? onTap;

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.schedule),
        title: Text(label),
        subtitle: Text(value == null ? 'Tanlanmagan' : _fmt(value!)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: onTap,
      );
}
