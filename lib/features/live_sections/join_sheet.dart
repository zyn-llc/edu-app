import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/api_error.dart';
import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../geo/geo_data.dart';
import 'live_sections_data.dart';

/// Join a live section: region (picked) + district, mahalla and school
/// number (typed), then `POST .../register`.
///
/// WHY TYPED (2026-09-19). This sheet used to be two cascading pickers.
/// In production the reference tables were empty — 14 regions, zero
/// districts, zero mahallas, zero schools — so the cascade stopped at
/// "Bu viloyat uchun tumanlar hali kiritilmagan" and registration was
/// impossible for everyone. Populating every mahalla in Uzbekistan by hand
/// was never going to happen, so the student types instead and the server
/// turns the text into reference rows.
///
/// Typing is not the same as the free text that migration 040 removed:
/// nothing typed here lands on the registration row. The server resolves it
/// to a `districts` / `mahallas` / `schools` row first (matched on
/// `lower(name)`), so "chilonzor" and "Chilonzor" converge instead of
/// splitting the hokimiyat report in two.
///
/// Whatever has already been entered is offered back as chips, so the
/// second student in a district reuses the first one's spelling rather than
/// inventing a near-duplicate.
///
/// Takes an already-loaded [LiveSectionDetail] instead of fetching it, so
/// the caller owns when the network happens — and so a widget test can pump
/// every branch without any HTTP.
class JoinSheet extends ConsumerStatefulWidget {
  const JoinSheet({super.key, required this.detail, this.initialRegionCode});

  final LiveSectionDetail detail;

  /// The student's own region, used to preselect the dropdown. Passed in
  /// rather than read from auth here: that keeps the sheet free of the
  /// auth/SharedPreferences chain, so a widget test can pump it directly.
  final String? initialRegionCode;

  static Future<bool?> show(
    BuildContext context,
    LiveSectionDetail detail, {
    String? initialRegionCode,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            JoinSheet(detail: detail, initialRegionCode: initialRegionCode),
      );

  @override
  ConsumerState<JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends ConsumerState<JoinSheet> {
  final _districtCtrl = TextEditingController();
  final _mahallaCtrl = TextEditingController();
  final _schoolCtrl = TextEditingController();
  final _classCtrl = TextEditingController();

  String? _regionCode;

  /// Chosen from the dropdown when the section limits classes; the free-text
  /// controller is used only when it does not.
  String? _classPick;
  bool _busy = false;
  RegisterFieldError? _fieldError;
  String? _formError;

  late final JoinRequirements _req = JoinRequirements.forSection(
    schoolFixed: widget.detail.schoolFixed,
    classRestricted: widget.detail.classes.isNotEmpty,
  );

  @override
  void initState() {
    super.initState();
    _regionCode = widget.initialRegionCode;
  }

  @override
  void dispose() {
    _districtCtrl.dispose();
    _mahallaCtrl.dispose();
    _schoolCtrl.dispose();
    _classCtrl.dispose();
    super.dispose();
  }

  /// What actually goes to the server as `class_label`.
  String? get _classLabel =>
      widget.detail.classes.isNotEmpty ? _classPick : _classCtrl.text;

  int? get _schoolNumber => int.tryParse(_schoolCtrl.text.trim());

  bool get _canSubmit =>
      !_busy &&
      _req.isComplete(
        regionCode: _regionCode,
        districtName: _districtCtrl.text,
        mahallaName: _mahallaCtrl.text,
        schoolNumber: _schoolNumber,
        classLabel: _classLabel,
      );

  /// Inline text for one field: required (server said it was missing) or
  /// stale (the value no longer resolves).
  String? _errorFor(String field, L10n l) {
    final e = _fieldError;
    if (e == null) return null;
    if (e.isMissing(field)) return l.joinFieldRequired;
    if (e.isInvalid(field)) return l.joinFieldStale;
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _formError = null;
      _fieldError = null;
    });
    try {
      await ref.read(liveSectionRepositoryProvider).register(
            widget.detail.id,
            schoolFixed: widget.detail.schoolFixed,
            regionCode: _regionCode,
            districtName: _districtCtrl.text,
            mahallaName: _mahallaCtrl.text,
            schoolNumber: _schoolNumber,
            classLabel: _classLabel,
          );
      ref.invalidate(liveSectionsProvider);
      ref.invalidate(liveSectionDetailProvider(widget.detail.id));
      // A new district or mahalla may have just been created, so the chips
      // the next student sees must include it.
      if (_regionCode != null) ref.invalidate(districtsProvider(_regionCode!));
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final fields = RegisterFieldError.fromDio(e);
      if (fields == null) {
        if (mounted) {
          setState(() => _formError = humanError(e, L10n.of(context)));
        }
        return;
      }
      if (mounted) setState(() => _fieldError = fields);
    } catch (e) {
      if (mounted) setState(() => _formError = humanError(e, L10n.of(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Names already in the reference list, offered so spellings converge.
  /// Silent when the list is empty or still loading — this is a convenience,
  /// never a gate.
  Widget _suggestions(List<String> names, TextEditingController ctrl,
      {required Key key}) {
    if (names.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          for (final n in names.take(12))
            ActionChip(
              label: Text(n),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        ctrl.text = n;
                      }),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final detail = widget.detail;
    final theme = Theme.of(context);

    final lang = ref.watch(localeCodeProvider);
    final regions = ref.watch(regionsProvider).valueOrNull ?? const [];

    // Districts already known for the chosen region, and mahallas already
    // known for the typed district (only once that district exists).
    final districts = _regionCode == null
        ? const <GeoDistrict>[]
        : ref.watch(districtsProvider(_regionCode!)).valueOrNull ??
            const <GeoDistrict>[];
    final typedDistrict = normalizeGeoName(_districtCtrl.text).toLowerCase();
    GeoDistrict? matched;
    for (final d in districts) {
      if (d.name.toLowerCase() == typedDistrict) matched = d;
    }
    final mahallas = matched == null
        ? const <GeoMahalla>[]
        : ref.watch(mahallasProvider(matched.id)).valueOrNull ??
            const <GeoMahalla>[];

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
            Text(detail.title, style: theme.textTheme.titleLarge),
            const Gap.xs(),
            Text(l.joinTitle, style: theme.textTheme.bodySmall),
            const Gap.md(),

            // ---- school fixed by the admin ------------------------------
            if (detail.schoolFixed) ...[
              // Shown read-only so the student knows which school the result
              // is filed under; the server ignores any school sent here.
              Card(
                key: const Key('join-fixed-school'),
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: Text(detail.school?.label ?? l.joinFixedSchool),
                  subtitle: detail.school?.district == null
                      ? null
                      : Text(detail.school!.district!,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const Gap.md(),
            ],

            // ---- region (picked: all 14 exist) ---------------------------
            DropdownButtonFormField<String>(
              key: const Key('join-region'),
              initialValue: _regionCode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.geoRegion,
                errorText: _errorFor('region_code', l),
              ),
              items: [
                for (final r in regions)
                  DropdownMenuItem(value: r.code, child: Text(r.name(lang))),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                        _regionCode = v;
                        // The old district belonged to the old region.
                        _districtCtrl.clear();
                        _mahallaCtrl.clear();
                      }),
            ),
            const Gap.md(),

            // ---- district (typed) ---------------------------------------
            TextField(
              key: const Key('join-district'),
              controller: _districtCtrl,
              enabled: !_busy,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l.geoDistrict,
                hintText: 'Chilonzor',
                counterText: '',
                errorText: _errorFor('district_name', l),
              ),
              onChanged: (_) => setState(() {}),
            ),
            _suggestions(
              [for (final d in districts) d.name],
              _districtCtrl,
              key: const Key('join-district-suggestions'),
            ),
            const Gap.md(),

            // ---- mahalla (typed) ----------------------------------------
            TextField(
              key: const Key('join-mahalla'),
              controller: _mahallaCtrl,
              enabled: !_busy,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l.geoMahalla,
                counterText: '',
                errorText: _errorFor('mahalla_name', l),
              ),
              onChanged: (_) => setState(() {}),
            ),
            _suggestions(
              [for (final m in mahallas) m.name],
              _mahallaCtrl,
              key: const Key('join-mahalla-suggestions'),
            ),
            const Gap.md(),

            // ---- school number (typed, only when not fixed) -------------
            if (!detail.schoolFixed) ...[
              TextField(
                key: const Key('join-school-number'),
                controller: _schoolCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  labelText: l.joinSchoolNumber,
                  hintText: '5',
                  errorText: _errorFor('school_number', l),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const Gap.md(),
            ],

            // ---- class ---------------------------------------------------
            // 041. A section may be limited to named classes. Then the class
            // is required and must come from that list, so a dropdown — a
            // free text box would just produce a 422 the student cannot fix.
            if (detail.classes.isNotEmpty)
              DropdownButtonFormField<String>(
                key: const Key('join-class-picker'),
                initialValue: _classPick,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.joinClassRequiredLabel,
                  errorText: _errorFor('class_label', l),
                ),
                items: [
                  for (final c in detail.classes)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged:
                    _busy ? null : (v) => setState(() => _classPick = v),
              )
            else
              TextField(
                key: const Key('join-class-label'),
                controller: _classCtrl,
                enabled: !_busy,
                maxLength: 20,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l.joinClassLabel,
                  hintText: '9-A',
                  counterText: '',
                ),
              ),

            if (_formError != null) ...[
              const Gap.sm(),
              Text(_formError!,
                  key: const Key('join-form-error'),
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const Gap.md(),
            FilledButton(
              key: const Key('join-submit'),
              onPressed: _canSubmit ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.joinSubmit),
            ),
          ],
        ),
      ),
    );
  }
}
