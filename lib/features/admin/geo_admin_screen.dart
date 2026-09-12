import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';
import '../../theme/spacing.dart';
import '../../widgets/empty_state.dart';
import '../geo/geo_data.dart';

/// Admin: fill the tuman / mahalla / maktab reference list.
///
/// This unblocks everything else — until a district has mahallas, nobody can
/// register for a live section, because the join form has nothing to pick.
///
/// UZBEK ONLY, deliberately: this screen is for staff, and the admin surface
/// in the shipped bundle was Uzbek too. Student-facing strings go through
/// l10n as usual.
///
/// NO DELETE. The backend exposes create and rename only, on purpose: these
/// rows back official results filed with the hokimiyat, so removing one would
/// rewrite history (MOBILE_ARCHITECTURE.md §8). A typo is fixed by renaming.
class GeoAdminScreen extends StatelessWidget {
  const GeoAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ma\'lumotnoma'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Tumanlar'),
            Tab(text: 'Mahallalar'),
            Tab(text: 'Maktablar'),
          ]),
        ),
        body: const TabBarView(children: [
          _DistrictsTab(),
          _ChildTab(kind: _ChildKind.mahalla),
          _ChildTab(kind: _ChildKind.school),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
//  Tumanlar                                                                    //
// --------------------------------------------------------------------------- //
class _DistrictsTab extends ConsumerStatefulWidget {
  const _DistrictsTab();

  @override
  ConsumerState<_DistrictsTab> createState() => _DistrictsTabState();
}

class _DistrictsTabState extends ConsumerState<_DistrictsTab> {
  String? _region;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeCodeProvider);
    final regions = ref.watch(regionsProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: regions.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Viloyatlar yuklanmadi'),
              data: (rows) => DropdownButtonFormField<String>(
                initialValue: _region,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Viloyat'),
                items: [
                  for (final r in rows)
                    DropdownMenuItem(value: r.code, child: Text(r.name(lang))),
                ],
                onChanged: (v) => setState(() => _region = v),
              ),
            ),
          ),
          if (_region == null)
            const Expanded(
              child: Center(
                child: EmptyState(
                  icon: Icons.map_outlined,
                  title: 'Viloyatni tanlang',
                  message: 'Tumanlar ro\'yxati viloyat bo\'yicha ko\'rsatiladi.',
                ),
              ),
            )
          else ...[
            _SearchBar(onChanged: (v) => setState(() => _q = v)),
            Expanded(
              child: ref.watch(districtsProvider(_region!)).when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => _LoadError(
                        onRetry: () =>
                            ref.invalidate(districtsProvider(_region!))),
                    data: (rows) {
                      if (rows.isEmpty) {
                        return const Center(
                          child: EmptyState(
                            icon: Icons.playlist_add,
                            title: 'Tuman yo\'q',
                            message:
                                'Pastdagi tugma bilan birinchi tumanni qo\'shing.',
                          ),
                        );
                      }
                      final shown = [
                        for (final d in rows)
                          if (_matches(d.name, _q)) d
                      ];
                      if (shown.isEmpty) {
                        return const Center(child: Text('Topilmadi'));
                      }
                      return ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) => ListTile(
                          title: Text(shown[i].name),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _rename(shown[i]),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ],
      ),
      floatingActionButton: _region == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Tuman'),
            ),
    );
  }

  Future<void> _add() async {
    final region = _region;
    if (region == null) return;
    final existing = ref.read(districtsProvider(region)).valueOrNull ?? const [];
    final name = await promptGeoName(context,
        title: 'Yangi tuman', taken: [for (final d in existing) d.name]);
    if (name == null || !mounted) return;
    await runGeoWrite(context, () async {
      await ref.read(geoRepositoryProvider).createDistrict(region, name);
      ref.invalidate(districtsProvider(region));
    });
  }

  Future<void> _rename(GeoDistrict d) async {
    final siblings =
        ref.read(districtsProvider(d.regionCode)).valueOrNull ?? const [];
    final name = await promptGeoName(context,
        title: 'Tuman nomini tuzatish',
        initial: d.name,
        taken: [for (final s in siblings) s.name]);
    if (name == null || !mounted) return;
    await runGeoWrite(context, () async {
      await ref.read(geoRepositoryProvider).renameDistrict(d.id, name);
      ref.invalidate(districtsProvider(d.regionCode));
    });
  }
}

// --------------------------------------------------------------------------- //
//  Mahallalar / Maktablar                                                      //
// --------------------------------------------------------------------------- //
enum _ChildKind { mahalla, school }

class _ChildTab extends ConsumerStatefulWidget {
  const _ChildTab({required this.kind});
  final _ChildKind kind;

  @override
  ConsumerState<_ChildTab> createState() => _ChildTabState();
}

class _ChildTabState extends ConsumerState<_ChildTab> {
  String? _region;
  String? _districtId;
  String _q = '';

  bool get _isSchool => widget.kind == _ChildKind.school;

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeCodeProvider);
    final regions = ref.watch(regionsProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              children: [
                regions.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Viloyatlar yuklanmadi'),
                  data: (rows) => DropdownButtonFormField<String>(
                    initialValue: _region,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Viloyat'),
                    items: [
                      for (final r in rows)
                        DropdownMenuItem(
                            value: r.code, child: Text(r.name(lang))),
                    ],
                    onChanged: (v) => setState(() {
                      _region = v;
                      _districtId = null;
                    }),
                  ),
                ),
                if (_region != null) ...[
                  const Gap.sm(),
                  ref.watch(districtsProvider(_region!)).when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) => const Text('Tumanlar yuklanmadi'),
                        data: (rows) => rows.isEmpty
                            ? const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                    'Avval «Tumanlar» bo\'limida tuman qo\'shing.'),
                              )
                            : DropdownButtonFormField<String>(
                                initialValue: _districtId,
                                isExpanded: true,
                                decoration:
                                    const InputDecoration(labelText: 'Tuman'),
                                items: [
                                  for (final d in rows)
                                    DropdownMenuItem(
                                        value: d.id, child: Text(d.name)),
                                ],
                                onChanged: (v) =>
                                    setState(() => _districtId = v),
                              ),
                      ),
                ],
              ],
            ),
          ),
          if (_districtId == null)
            const Expanded(
              child: Center(
                child: EmptyState(
                  icon: Icons.holiday_village_outlined,
                  title: 'Tumanni tanlang',
                  message: 'Ro\'yxat tanlangan tuman bo\'yicha ko\'rsatiladi.',
                ),
              ),
            )
          else ...[
            _SearchBar(onChanged: (v) => setState(() => _q = v)),
            Expanded(child: _list()),
          ],
        ],
      ),
      floatingActionButton: _districtId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: Text(_isSchool ? 'Maktab' : 'Mahalla'),
            ),
    );
  }

  Widget _list() {
    final districtId = _districtId!;

    if (_isSchool) {
      return ref.watch(schoolsProvider(districtId)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => _LoadError(
                onRetry: () => ref.invalidate(schoolsProvider(districtId))),
            data: (rows) {
              if (rows.isEmpty) {
                return const Center(
                  child: EmptyState(
                    icon: Icons.playlist_add,
                    title: 'Maktab yo\'q',
                    message: 'Pastdagi tugma bilan birinchi maktabni qo\'shing.',
                  ),
                );
              }
              final shown = [
                for (final s in rows)
                  if (_matches(s.label, _q)) s
              ];
              if (shown.isEmpty) return const Center(child: Text('Topilmadi'));
              return ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(shown[i].label),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editSchool(shown[i]),
                ),
              );
            },
          );
    }

    return ref.watch(mahallasProvider(districtId)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _LoadError(
              onRetry: () => ref.invalidate(mahallasProvider(districtId))),
          data: (rows) {
            if (rows.isEmpty) {
              return const Center(
                child: EmptyState(
                  icon: Icons.playlist_add,
                  title: 'Mahalla yo\'q',
                  message: 'Pastdagi tugma bilan birinchi mahallani qo\'shing.',
                ),
              );
            }
            final shown = [
              for (final m in rows)
                if (_matches(m.name, _q)) m
            ];
            if (shown.isEmpty) return const Center(child: Text('Topilmadi'));
            return ListView.builder(
              itemCount: shown.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(shown[i].name),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _renameMahalla(shown[i]),
              ),
            );
          },
        );
  }

  Future<void> _add() async {
    final districtId = _districtId;
    if (districtId == null) return;

    if (_isSchool) {
      final input = await promptSchool(context);
      if (input == null || !mounted) return;
      await runGeoWrite(context, () async {
        final r = await ref
            .read(geoRepositoryProvider)
            .createSchool(districtId, input.number, name: input.name);
        ref.invalidate(schoolsProvider(districtId));
        if (r.linkedExisting && mounted) {
          // Not a duplicate: a school a student had typed into their profile
          // before 040 was adopted into the reference list (§8).
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bu maktab profil orqali kiritilgan edi — '
                'ma\'lumotnomaga ulandi'),
          ));
        }
      });
      return;
    }

    final existing =
        ref.read(mahallasProvider(districtId)).valueOrNull ?? const [];
    final name = await promptGeoName(context,
        title: 'Yangi mahalla', taken: [for (final m in existing) m.name]);
    if (name == null || !mounted) return;
    await runGeoWrite(context, () async {
      await ref.read(geoRepositoryProvider).createMahalla(districtId, name);
      ref.invalidate(mahallasProvider(districtId));
    });
  }

  Future<void> _renameMahalla(GeoMahalla m) async {
    final siblings =
        ref.read(mahallasProvider(m.districtId)).valueOrNull ?? const [];
    final name = await promptGeoName(context,
        title: 'Mahalla nomini tuzatish',
        initial: m.name,
        taken: [for (final s in siblings) s.name]);
    if (name == null || !mounted) return;
    await runGeoWrite(context, () async {
      await ref.read(geoRepositoryProvider).renameMahalla(m.id, name);
      ref.invalidate(mahallasProvider(m.districtId));
    });
  }

  Future<void> _editSchool(GeoSchool s) async {
    final input = await promptSchool(context, number: s.number, name: s.name);
    if (input == null || !mounted) return;
    await runGeoWrite(context, () async {
      await ref
          .read(geoRepositoryProvider)
          .patchSchool(s.id, number: input.number, name: input.name);
      final d = s.districtId;
      if (d != null) ref.invalidate(schoolsProvider(d));
    });
  }
}

// --------------------------------------------------------------------------- //
//  Shared bits                                                                 //
// --------------------------------------------------------------------------- //
bool _matches(String s, String q) =>
    q.isEmpty || s.toLowerCase().contains(q.toLowerCase());

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        child: TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Qidirish',
            isDense: true,
          ),
          onChanged: onChanged,
        ),
      );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: EmptyState(
          icon: Icons.wifi_off,
          title: 'Yuklanmadi',
          message: 'Ro\'yxatni olib bo\'lmadi.',
          actionLabel: 'Qayta urinish',
          onAction: onRetry,
        ),
      );
}

/// Name dialog with the two validations the server also enforces: at least
/// two characters after trimming, and no duplicate inside the same parent.
/// Checking locally keeps the common mistake off the network; the server's
/// 409 is still handled, because another admin may have added it meanwhile.
Future<String?> promptGeoName(
  BuildContext context, {
  required String title,
  String? initial,
  List<String> taken = const [],
}) async {
  final ctrl = TextEditingController(text: initial ?? '');
  final lower = [
    for (final t in taken)
      if (initial == null || t.toLowerCase() != initial.toLowerCase())
        t.toLowerCase()
  ];
  final formKey = GlobalKey<FormState>();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: ctrl,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Nom', counterText: ''),
          validator: (v) {
            final s = (v ?? '').trim();
            if (s.length < 2) return 'Kamida 2 ta belgi';
            if (lower.contains(s.toLowerCase())) {
              return 'Bunday nom allaqachon bor';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(ctx, true);
            }
          },
          child: const Text('Saqlash'),
        ),
      ],
    ),
  );
  final value = ctrl.text.trim();
  ctrl.dispose();
  return ok == true ? value : null;
}

typedef SchoolInput = ({int number, String? name});

Future<SchoolInput?> promptSchool(BuildContext context,
    {int? number, String? name}) async {
  final numCtrl = TextEditingController(text: number?.toString() ?? '');
  final nameCtrl = TextEditingController(text: name ?? '');
  final formKey = GlobalKey<FormState>();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(number == null ? 'Yangi maktab' : 'Maktabni tuzatish'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: numCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Maktab raqami'),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null) return 'Raqam kiriting';
                if (n < 1 || n > 9999) return '1 dan 9999 gacha';
                return null;
              },
            ),
            TextFormField(
              controller: nameCtrl,
              maxLength: 200,
              decoration: const InputDecoration(
                  labelText: 'Nomi (ixtiyoriy)', counterText: ''),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(ctx, true);
            }
          },
          child: const Text('Saqlash'),
        ),
      ],
    ),
  );
  final n = int.tryParse(numCtrl.text.trim());
  final nm = nameCtrl.text.trim();
  numCtrl.dispose();
  nameCtrl.dispose();
  if (ok != true || n == null) return null;
  return (number: n, name: nm.isEmpty ? null : nm);
}

/// Runs a write and turns the expected failures into a readable message:
/// 409 (duplicate) and everything else.
Future<void> runGeoWrite(
    BuildContext context, Future<void> Function() run) async {
  try {
    await run();
  } on GeoConflict catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  } on DioException catch (e) {
    if (context.mounted) {
      final data = e.response?.data;
      final msg = data is Map && data['detail'] is String
          ? data['detail'] as String
          : 'Saqlanmadi';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
