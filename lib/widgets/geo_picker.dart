import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../features/geo/geo_data.dart';
import '../l10n/app_localizations.dart';
import '../theme/spacing.dart';

/// Cascading reference-geography picker: region -> district -> (mahalla | school).
///
/// Shared by the live-section join sheet and the admin "Yangi sinov" modal so
/// the two can never disagree on what a valid selection is.
///
/// The leaf step opens a searchable sheet instead of a dropdown: a district
/// can hold hundreds of mahallas and a long `DropdownButton` menu is unusable
/// on a phone. Search is client-side over the one cached fetch (`geo_data.dart`),
/// so typing never re-hits the network.
enum GeoTarget { mahalla, school }

class GeoPicker extends ConsumerStatefulWidget {
  const GeoPicker({
    super.key,
    required this.target,
    required this.onChanged,
    this.initialRegionCode,
    this.errorText,
    this.enabled = true,
  });

  final GeoTarget target;

  /// Fires with the selected id, or `null` whenever the selection becomes
  /// incomplete (region or district changed) — callers use that to keep the
  /// submit button disabled.
  final ValueChanged<String?> onChanged;

  /// Opens the cascade on the student's own region (profile `region_code`).
  final String? initialRegionCode;

  /// Server-side validation message, e.g. from a 422 `missing_fields`.
  final String? errorText;

  final bool enabled;

  @override
  ConsumerState<GeoPicker> createState() => _GeoPickerState();
}

class _GeoPickerState extends ConsumerState<GeoPicker> {
  String? _region;
  String? _districtId;
  String? _valueId;
  String? _valueLabel;

  @override
  void initState() {
    super.initState();
    _region = widget.initialRegionCode;
  }

  bool get _isSchool => widget.target == GeoTarget.school;

  void _emit(String? id, String? label) {
    setState(() {
      _valueId = id;
      _valueLabel = label;
    });
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final lang = ref.watch(localeCodeProvider);
    final regionsAsync = ref.watch(regionsProvider);
    final enabled = widget.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        regionsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => Text(l.geoLoadFailed,
              style: TextStyle(color: theme.colorScheme.error)),
          data: (regions) => DropdownButtonFormField<String>(
            key: const Key('geo-region'),
            initialValue: _region,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.geoRegion),
            items: [
              for (final r in regions)
                DropdownMenuItem(value: r.code, child: Text(r.name(lang))),
            ],
            onChanged: !enabled
                ? null
                : (v) {
                    setState(() {
                      _region = v;
                      _districtId = null;
                    });
                    _emit(null, null); // a cascade reset invalidates the leaf
                  },
          ),
        ),
        const Gap.sm(),
        if (_region != null)
          ref.watch(districtsProvider(_region!)).when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => Text(l.geoLoadFailed,
                    style: TextStyle(color: theme.colorScheme.error)),
                data: (districts) => districts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: Spacing.xs),
                        child: Text(l.geoNoDistricts,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.outline)),
                      )
                    : DropdownButtonFormField<String>(
                        key: const Key('geo-district'),
                        initialValue: _districtId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: l.geoDistrict),
                        items: [
                          for (final d in districts)
                            DropdownMenuItem(value: d.id, child: Text(d.name)),
                        ],
                        onChanged: !enabled
                            ? null
                            : (v) {
                                setState(() => _districtId = v);
                                _emit(null, null);
                              },
                      ),
              ),
        const Gap.sm(),
        if (_districtId != null)
          InkWell(
            key: Key(_isSchool ? 'geo-leaf-school' : 'geo-leaf-mahalla'),
            onTap: enabled ? () => _openSearch(context) : null,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: _isSchool ? l.geoSchool : l.geoMahalla,
                errorText: widget.errorText,
                suffixIcon: const Icon(Icons.search),
              ),
              child: Text(
                _valueLabel ?? l.geoSelect,
                style: _valueId == null
                    ? TextStyle(color: theme.hintColor)
                    : null,
              ),
            ),
          )
        else if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(widget.errorText!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
          ),
      ],
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final districtId = _districtId;
    if (districtId == null) return;
    final l = L10n.of(context);

    final picked = await showModalBottomSheet<({String id, String label})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchSheet(
        title: _isSchool ? l.geoPickSchool : l.geoPickMahalla,
        districtId: districtId,
        target: widget.target,
      ),
    );
    if (picked != null) _emit(picked.id, picked.label);
  }
}

/// Searchable list of one district's mahallas or schools.
class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet({
    required this.title,
    required this.districtId,
    required this.target,
  });

  final String title;
  final String districtId;
  final GeoTarget target;

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isSchool = widget.target == GeoTarget.school;
    final async = isSchool
        ? ref.watch(schoolsProvider(widget.districtId))
        : ref.watch(mahallasProvider(widget.districtId));

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.md,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const Gap.sm(),
            TextField(
              key: const Key('geo-search'),
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.geoSearch,
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
            const Gap.sm(),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(child: Text(l.geoLoadFailed)),
                data: (rows) {
                  final all = <({String id, String label})>[
                    for (final r in rows)
                      if (isSchool)
                        (id: (r as GeoSchool).id, label: r.label)
                      else
                        (id: (r as GeoMahalla).id, label: r.name),
                  ];
                  final items = [
                    for (final e in all)
                      if (_q.isEmpty || e.label.toLowerCase().contains(_q)) e
                  ];
                  if (items.isEmpty) {
                    return Center(
                        child: Text(all.isEmpty ? l.geoEmptyList : l.geoNotFound));
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(items[i].label),
                      onTap: () => Navigator.pop(context, items[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
