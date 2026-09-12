import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';
import '../geo/geo_data.dart';

/// Live sections (jonli sinovlar) — participant side.
/// Contract: MOBILE_ARCHITECTURE.md §8.

class LiveBlock {
  final String id;
  final String subjectId;
  final int? grade;
  final int questionCount;
  final int timeLimitSec;
  final int orderIndex;
  final int attemptsUsed;
  final String? openAttemptId;

  const LiveBlock({
    required this.id,
    required this.subjectId,
    required this.grade,
    required this.questionCount,
    required this.timeLimitSec,
    required this.orderIndex,
    required this.attemptsUsed,
    required this.openAttemptId,
  });

  factory LiveBlock.fromJson(Map<String, dynamic> j) => LiveBlock(
        id: j['id'] as String,
        subjectId: j['subject_id'] as String,
        grade: (j['grade'] as num?)?.toInt(),
        questionCount: (j['question_count'] as num).toInt(),
        timeLimitSec: (j['time_limit_sec'] as num).toInt(),
        orderIndex: (j['order_index'] as num?)?.toInt() ?? 0,
        attemptsUsed: (j['attempts_used'] as num?)?.toInt() ?? 0,
        openAttemptId: j['open_attempt_id'] as String?,
      );
}

class LiveSectionSummary {
  final String id;
  final String title;
  final String? description;
  final String status;
  final DateTime startAt;
  final DateTime endAt;
  final DateTime? registrationDeadline;
  final bool registered;
  final bool registrationOpen;
  final bool isProctored;
  final bool schoolFixed;
  final GeoSchool? school;

  const LiveSectionSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.registrationDeadline,
    required this.registered,
    required this.registrationOpen,
    required this.isProctored,
    required this.schoolFixed,
    required this.school,
  });

  factory LiveSectionSummary.fromJson(Map<String, dynamic> j) =>
      LiveSectionSummary(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        status: j['status'] as String? ?? 'scheduled',
        startAt: DateTime.parse(j['start_at'] as String).toLocal(),
        endAt: DateTime.parse(j['end_at'] as String).toLocal(),
        registrationDeadline: j['registration_deadline'] == null
            ? null
            : DateTime.parse(j['registration_deadline'] as String).toLocal(),
        registered: j['registered'] == true,
        registrationOpen: j['registration_open'] == true,
        isProctored: j['is_proctored'] == true,
        schoolFixed: j['school_fixed'] == true,
        school: j['school'] == null
            ? null
            : GeoSchool.fromJson(j['school'] as Map<String, dynamic>),
      );
}

class LiveSectionDetail {
  final String id;
  final String title;
  final String? description;
  final String status;
  final DateTime startAt;
  final DateTime endAt;
  final bool isProctored;
  final int maxAttempts;
  final bool registered;
  final bool schoolFixed;
  final GeoSchool? school;
  final List<LiveBlock> blocks;

  const LiveSectionDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.isProctored,
    required this.maxAttempts,
    required this.registered,
    required this.schoolFixed,
    required this.school,
    required this.blocks,
  });

  factory LiveSectionDetail.fromJson(Map<String, dynamic> j) =>
      LiveSectionDetail(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        status: j['status'] as String? ?? 'scheduled',
        startAt: DateTime.parse(j['start_at'] as String).toLocal(),
        endAt: DateTime.parse(j['end_at'] as String).toLocal(),
        isProctored: j['is_proctored'] == true,
        maxAttempts: (j['max_attempts'] as num?)?.toInt() ?? 1,
        registered: j['registered'] == true,
        schoolFixed: j['school_fixed'] == true,
        school: j['school'] == null
            ? null
            : GeoSchool.fromJson(j['school'] as Map<String, dynamic>),
        blocks: [
          for (final b in (j['blocks'] as List? ?? const []))
            LiveBlock.fromJson(b as Map<String, dynamic>)
        ],
      );
}

// --------------------------------------------------------------------------- //
//  Join gating — PURE. Unit-tested in test/live_section_join_test.dart.        //
// --------------------------------------------------------------------------- //

/// Which fields the join form must collect for one section.
///
/// The rule (§8): mahalla is always required; school is required only when
/// the section has no fixed school. When it does, the server writes its own
/// school and ignores anything the client sends — so the client must not
/// send one at all.
class JoinRequirements {
  final bool needsSchool;
  final bool needsMahalla;

  const JoinRequirements({required this.needsSchool, required this.needsMahalla});

  factory JoinRequirements.forSection({required bool schoolFixed}) =>
      JoinRequirements(needsSchool: !schoolFixed, needsMahalla: true);

  bool isComplete({String? schoolId, String? mahallaId}) =>
      missing(schoolId: schoolId, mahallaId: mahallaId).isEmpty;

  /// Field names in form order — the same order the server reports them in
  /// `missing_fields`, so the highlighting lines up.
  List<String> missing({String? schoolId, String? mahallaId}) => [
        if (needsSchool && (schoolId == null || schoolId.isEmpty)) 'school_id',
        if (needsMahalla && (mahallaId == null || mahallaId.isEmpty))
          'mahalla_id',
      ];
}

/// Request body for `POST /v1/live-sections/{id}/register`.
///
/// `school_id` is omitted when the section has a fixed school: sending it
/// would be ignored server-side anyway, and leaving it out keeps the client
/// honest about who owns that value.
Map<String, dynamic> buildRegisterBody({
  required bool schoolFixed,
  String? schoolId,
  String? mahallaId,
  String? classLabel,
}) {
  final label = classLabel?.trim() ?? '';
  return {
    if (!schoolFixed && schoolId != null && schoolId.isNotEmpty)
      'school_id': schoolId,
    if (mahallaId != null && mahallaId.isNotEmpty) 'mahalla_id': mahallaId,
    if (label.isNotEmpty) 'class_label': label.toUpperCase(),
  };
}

/// A 422 from the register endpoint, split per field.
///
/// `detail` is deliberately not parsed (§8): it is human prose and may be
/// reworded server-side. Only the machine-readable lists are used.
class RegisterFieldError {
  final String title;
  final List<String> missingFields;
  final List<String> invalidFields;

  const RegisterFieldError({
    required this.title,
    required this.missingFields,
    required this.invalidFields,
  });

  bool get isEmpty => missingFields.isEmpty && invalidFields.isEmpty;

  /// True when the picker showed something the server no longer accepts —
  /// the cached reference list is stale and must be refetched.
  bool get isStale => invalidFields.isNotEmpty;

  static List<String> _list(Object? v) => v is List
      ? [for (final e in v) if (e is String) e]
      : const <String>[];

  /// Returns null when the response is not a field-level 422.
  static RegisterFieldError? fromDio(DioException e) {
    if (e.response?.statusCode != 422) return null;
    final data = e.response?.data;
    if (data is! Map) return null;
    final err = RegisterFieldError(
      title: data['title'] as String? ?? 'Maydonlar to\'ldirilmagan',
      missingFields: _list(data['missing_fields']),
      invalidFields: _list(data['invalid_fields']),
    );
    return err.isEmpty ? null : err;
  }

  /// The widget maps these to localised text; the data layer stays free of
  /// user-facing strings.
  bool isMissing(String field) => missingFields.contains(field);

  bool isInvalid(String field) => invalidFields.contains(field);
}

class RegisterResult {
  final bool registered;
  final bool already;
  final String? schoolId;
  final String? mahallaId;

  const RegisterResult({
    required this.registered,
    required this.already,
    required this.schoolId,
    required this.mahallaId,
  });

  factory RegisterResult.fromJson(Map<String, dynamic> j) => RegisterResult(
        registered: j['registered'] == true,
        already: j['already'] == true,
        schoolId: j['school_id'] as String?,
        mahallaId: j['mahalla_id'] as String?,
      );
}

// --------------------------------------------------------------------------- //
//  Repository + providers                                                      //
// --------------------------------------------------------------------------- //
class LiveSectionRepository {
  final Ref ref;
  LiveSectionRepository(this.ref);

  Future<List<LiveSectionSummary>> list() async {
    final res = await ref.read(dioProvider).get('/v1/live-sections');
    final items = (res.data as Map<String, dynamic>)['items'] as List;
    return [
      for (final e in items)
        LiveSectionSummary.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<LiveSectionDetail> detail(String id) async {
    final res = await ref.read(dioProvider).get('/v1/live-sections/$id');
    return LiveSectionDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<RegisterResult> register(
    String id, {
    required bool schoolFixed,
    String? schoolId,
    String? mahallaId,
    String? classLabel,
  }) async {
    final res = await ref.read(dioProvider).post(
          '/v1/live-sections/$id/register',
          data: buildRegisterBody(
            schoolFixed: schoolFixed,
            schoolId: schoolId,
            mahallaId: mahallaId,
            classLabel: classLabel,
          ),
        );
    return RegisterResult.fromJson(res.data as Map<String, dynamic>);
  }
}

final liveSectionRepositoryProvider =
    Provider<LiveSectionRepository>((ref) => LiveSectionRepository(ref));

final liveSectionsProvider =
    FutureProvider<List<LiveSectionSummary>>((ref) async {
  ref.watch(authControllerProvider);
  return ref.read(liveSectionRepositoryProvider).list();
});

final liveSectionDetailProvider =
    FutureProvider.family<LiveSectionDetail, String>((ref, id) async {
  ref.watch(authControllerProvider);
  return ref.read(liveSectionRepositoryProvider).detail(id);
});
