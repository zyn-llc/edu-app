import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/geo_picker.dart';
import 'admin_section_detail_screen.dart';
import 'admin_sections_data.dart';

/// Admin: live sections list + the "Yangi sinov" creation modal.
///
/// Creating a section is only the first step — it lands as a `draft` and
/// cannot be joined until it has at least one block and has been published.
/// That happens on [AdminSectionDetailScreen], which a row opens.
///
/// Uzbek-only strings: staff screen, same as the rest of the admin surface.
class AdminSectionsScreen extends ConsumerWidget {
  const AdminSectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminSectionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Jonli sinovlar')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final createdId = await NewSectionSheet.show(context);
          if (createdId == null) return;
          ref.invalidate(adminSectionsProvider);
          if (!context.mounted) return;
          // Straight into the detail screen: a section with no blocks cannot
          // be published, so leaving the admin on the list would look like
          // the job was finished when it was not.
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminSectionDetailScreen(sectionId: createdId),
            ),
          );
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
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(adminSectionsProvider),
                child: ListView.builder(
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: "Olib tashlash",
                              onPressed: () => removeSection(context, ref, s),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AdminSectionDetailScreen(sectionId: s.id),
                          ),
                        ),
                      ),
                    );
                  },
                ),
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

  /// Returns the new section's id, or null when cancelled.
  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
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
  final _classesCtrl = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  String? _schoolId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _classesCtrl.dispose();
    super.dispose();
  }

  /// "9-a, 9b" -> ['9-A', '9B']. Upper-cased and de-duplicated here as well
  /// as on the server, so the admin sees exactly what will be stored.
  List<String> get _classes => _classesCtrl.text
      .split(RegExp(r'[,;\n]+'))
      .map((e) => e.trim().toUpperCase())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

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
      final created = await ref.read(adminSectionsRepositoryProvider).create(
            title: _titleCtrl.text.trim(),
            startAt: _start!,
            endAt: _end!,
            schoolId: _schoolId, // null -> open to every school
            classes: _classes, // empty -> open to every class
          );
      if (mounted) Navigator.pop(context, created.id);
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
              child:
                  Text('Maktab (ixtiyoriy)', style: theme.textTheme.labelLarge),
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
                  onPressed:
                      _busy ? null : () => setState(() => _schoolId = null),
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Maktabni olib tashlash'),
                ),
              ),

            const Gap.md(),
            Align(
              alignment: Alignment.centerLeft,
              child: Text("Sinflar (ixtiyoriy)",
                  style: theme.textTheme.labelLarge),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Masalan: 9-A, 9-B. Bo'sh qoldirilsa — hamma sinf qatnasha "
                "oladi. To'ldirilsa, o'quvchi ro'yxatdan o'tishda shu "
                "ro'yxatdan sinfini tanlaydi va boshqa sinf yozila olmaydi.",
                style: theme.textTheme.bodySmall,
              ),
            ),
            const Gap.sm(),
            TextField(
              controller: _classesCtrl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: "Sinflar",
                hintText: "9-A, 9-B",
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_classes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text("Tanlandi: ${_classes.join(', ')}",
                    style: theme.textTheme.bodySmall),
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
            const Gap.sm(),
            Text(
              'Yaratilgandan keyin blok qo\'shib, e\'lon qilish kerak — '
              'shundagina o\'quvchilar ro\'yxatdan o\'ta oladi.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Remove a section from the list.
///
/// The server decides delete-vs-archive (041); the dialog says so plainly,
/// because "delete" on a finished competition would otherwise read as
/// "throw the results away".
Future<void> removeSection(
    BuildContext context, WidgetRef ref, AdminSection s) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("«${s.title}» olib tashlansinmi?"),
      content: const Text(
        "Hech kim ro'yxatdan o'tmagan qoralama butunlay o'chiriladi.\n\n"
        "E'lon qilingan yoki ishtirokchisi bor sinov esa ARXIVLANADI — "
        "ro'yxatdan yo'qoladi, lekin natijalar va statistika bazada qoladi.",
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Bekor")),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Olib tashlash")),
      ],
    ),
  );
  if (ok != true) return;
  try {
    final r = await ref.read(adminSectionsRepositoryProvider).remove(s.id);
    ref.invalidate(adminSectionsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.deleted
            ? "O'chirildi"
            : "Arxivlandi — natijalar bazada saqlanib qoldi"),
      ));
    }
  } on DioException catch (e) {
    final data = e.response?.data;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(data is Map && data["detail"] is String
            ? data["detail"] as String
            : "Olib tashlanmadi"),
      ));
    }
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
