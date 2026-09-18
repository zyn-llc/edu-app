import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/geo_picker.dart';
import '../geo/geo_data.dart';
import 'live_sections_data.dart';

/// Join a live section: collect mahalla (always) and school (only when the
/// section has no fixed one), then `POST .../register`.
///
/// Takes an already-loaded [LiveSectionDetail] instead of fetching it, so the
/// caller owns when the network happens — and so a widget test can pump both
/// branches (fixed school / open) without any HTTP.
class JoinSheet extends ConsumerStatefulWidget {
  const JoinSheet({super.key, required this.detail, this.initialRegionCode});

  final LiveSectionDetail detail;

  /// The student's own region, used to open the cascade on a sensible step.
  /// Passed in rather than read from auth here: that keeps the sheet free of
  /// the auth/SharedPreferences chain, so a widget test can pump it directly.
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
  final _classCtrl = TextEditingController();
  String? _schoolId;
  String? _mahallaId;

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

  /// What actually goes to the server as `class_label`.
  String? get _classLabel =>
      widget.detail.classes.isNotEmpty ? _classPick : _classCtrl.text;

  @override
  void dispose() {
    _classCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy &&
      _req.isComplete(
        schoolId: _schoolId,
        mahallaId: _mahallaId,
        classLabel: _classLabel,
      );

  /// Inline text for one field: required (server said it was missing) or
  /// stale (the cached list offered something the server rejects).
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
            schoolId: _schoolId,
            mahallaId: _mahallaId,
            classLabel: _classLabel,
          );
      ref.invalidate(liveSectionsProvider);
      ref.invalidate(liveSectionDetailProvider(widget.detail.id));
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final fields = RegisterFieldError.fromDio(e);
      if (fields == null) {
        if (mounted) {
          setState(() => _formError = humanError(e, L10n.of(context)));
        }
        return;
      }
      // A stale pick means the cached reference list no longer matches the
      // server, so drop it — otherwise the next open offers the same dead row.
      if (fields.isStale) {
        ref.invalidate(mahallasProvider);
        ref.invalidate(schoolsProvider);
      }
      if (mounted) {
        setState(() {
          _fieldError = fields;
          if (fields.isInvalid('mahalla_id')) _mahallaId = null;
          if (fields.isInvalid('school_id')) _schoolId = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _formError = humanError(e, L10n.of(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final detail = widget.detail;
    final theme = Theme.of(context);
    final region = widget.initialRegionCode;

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

            // ---- school -------------------------------------------------
            if (detail.schoolFixed) ...[
              // Fixed by the admin: shown read-only so the student knows which
              // school the result is filed under, but never editable — the
              // server ignores a client-sent school for these sections.
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
            ] else ...[
              GeoPicker(
                key: const Key('join-school-picker'),
                target: GeoTarget.school,
                initialRegionCode: region,
                enabled: !_busy,
                errorText: _errorFor('school_id', l),
                onChanged: (id) => setState(() => _schoolId = id),
              ),
              const Gap.md(),
            ],

            // ---- mahalla (always) ---------------------------------------
            GeoPicker(
              key: const Key('join-mahalla-picker'),
              target: GeoTarget.mahalla,
              initialRegionCode: region,
              enabled: !_busy,
              errorText: _errorFor('mahalla_id', l),
              onChanged: (id) => setState(() => _mahallaId = id),
            ),
            const Gap.md(),

            // 041. A section may be limited to named classes. Then the class
            // is required and must come from that list, so a dropdown — a free
            // text box would just produce a 422 the student cannot fix.
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
