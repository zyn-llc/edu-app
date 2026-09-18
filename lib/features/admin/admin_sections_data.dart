import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';
import '../geo/geo_data.dart';

/// Admin side of live sections: create a section, give it blocks, check the
/// bank, publish.
///
/// Contract: `backend/app/api/v1/live_sections_admin.py`.
///
/// STATUS IS ONE-WAY on purpose:
///     draft --publish--> scheduled --(time)--> live --> finished
///       \                   \                    \
///        `----------------- cancelled -----------'
/// Only a `draft` can be edited. Once students have registered, changing the
/// question count or the time limit would mean they prepared for a different
/// exam, so the server refuses it.

class AdminBlock {
  final String id;
  final String subjectId;
  final int? grade;
  final int questionCount;
  final int timeLimitSec;
  final int orderIndex;

  const AdminBlock({
    required this.id,
    required this.subjectId,
    required this.grade,
    required this.questionCount,
    required this.timeLimitSec,
    required this.orderIndex,
  });

  factory AdminBlock.fromJson(Map<String, dynamic> j) => AdminBlock(
        id: j['id'] as String,
        subjectId: j['subject_id'] as String,
        grade: (j['grade'] as num?)?.toInt(),
        questionCount: (j['question_count'] as num).toInt(),
        timeLimitSec: (j['time_limit_sec'] as num).toInt(),
        orderIndex: (j['order_index'] as num?)?.toInt() ?? 0,
      );
}

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

class AdminSectionDetail extends AdminSection {
  final List<AdminBlock> blocks;
  final int registrationCount;
  final int attemptCount;

  const AdminSectionDetail({
    required super.id,
    required super.title,
    required super.status,
    required super.startAt,
    required super.endAt,
    required super.schoolId,
    required super.school,
    required this.blocks,
    required this.registrationCount,
    required this.attemptCount,
  });

  factory AdminSectionDetail.fromJson(Map<String, dynamic> j) =>
      AdminSectionDetail(
        id: j['id'] as String,
        title: j['title'] as String,
        status: j['status'] as String? ?? 'draft',
        startAt: DateTime.parse(j['start_at'] as String).toLocal(),
        endAt: DateTime.parse(j['end_at'] as String).toLocal(),
        schoolId: j['school_id'] as String?,
        school: j['school'] == null
            ? null
            : GeoSchool.fromJson(j['school'] as Map<String, dynamic>),
        blocks: [
          for (final b in (j['blocks'] as List? ?? const []))
            AdminBlock.fromJson(b as Map<String, dynamic>)
        ],
        registrationCount: (j['registration_count'] as num?)?.toInt() ?? 0,
        attemptCount: (j['attempt_count'] as num?)?.toInt() ?? 0,
      );

  bool get isDraft => status == 'draft';
  bool get canPublish => isDraft && blocks.isNotEmpty;
  bool get canCancel => status != 'finished' && status != 'cancelled';
}

/// One difficulty band inside a block's availability check.
class BandPreview {
  final String band;
  final int wanted;
  final int available;
  final int short;

  const BandPreview({
    required this.band,
    required this.wanted,
    required this.available,
    required this.short,
  });

  factory BandPreview.fromJson(Map<String, dynamic> j) => BandPreview(
        band: j['band'] as String,
        wanted: (j['wanted'] as num).toInt(),
        available: (j['available'] as num).toInt(),
        short: (j['short'] as num).toInt(),
      );
}

class BlockPreview {
  final String blockId;
  final int requested;
  final int available;
  final bool enough;
  final bool mixSatisfied;
  final List<BandPreview> bands;

  const BlockPreview({
    required this.blockId,
    required this.requested,
    required this.available,
    required this.enough,
    required this.mixSatisfied,
    required this.bands,
  });

  factory BlockPreview.fromJson(Map<String, dynamic> j) => BlockPreview(
        blockId: j['block_id'] as String,
        requested: (j['requested'] as num).toInt(),
        available: (j['available'] as num).toInt(),
        enough: j['enough'] == true,
        mixSatisfied: j['mix_satisfied'] == true,
        bands: [
          for (final b in (j['bands'] as List? ?? const []))
            BandPreview.fromJson(b as Map<String, dynamic>)
        ],
      );
}

class PreviewResult {
  final bool ok;
  final String? reason;
  final List<BlockPreview> blocks;

  const PreviewResult(
      {required this.ok, required this.reason, required this.blocks});

  factory PreviewResult.fromJson(Map<String, dynamic> j) => PreviewResult(
        ok: j['ok'] == true,
        reason: j['reason'] as String?,
        blocks: [
          for (final b in (j['blocks'] as List? ?? const []))
            BlockPreview.fromJson(b as Map<String, dynamic>)
        ],
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

  Future<AdminSectionDetail> detail(String id) async {
    final res = await ref.read(dioProvider).get('/v1/admin/live-sections/$id');
    return AdminSectionDetail.fromJson(res.data as Map<String, dynamic>);
  }

  /// `schoolId == null` -> open to every school.
  Future<AdminSection> create({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String? schoolId,
  }) async {
    final res =
        await ref.read(dioProvider).post('/v1/admin/live-sections', data: {
      'title': title,
      'start_at': startAt.toUtc().toIso8601String(),
      'end_at': endAt.toUtc().toIso8601String(),
      if (schoolId != null) 'school_id': schoolId,
    });
    return AdminSection.fromJson(res.data as Map<String, dynamic>);
  }

  /// `topic_ids` is left empty: the whole subject is in scope. `difficulty_mix`
  /// is omitted so the server applies its own 30/50/20 default — the same
  /// target the question banks are written against.
  Future<AdminBlock> addBlock(
    String sectionId, {
    required String subjectId,
    int? grade,
    required int questionCount,
    required int timeLimitSec,
  }) async {
    final res = await ref
        .read(dioProvider)
        .post('/v1/admin/live-sections/$sectionId/blocks', data: {
      'subject_id': subjectId,
      if (grade != null) 'grade': grade,
      'question_count': questionCount,
      'time_limit_sec': timeLimitSec,
    });
    return AdminBlock.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteBlock(String sectionId, String blockId) =>
      ref.read(dioProvider).delete(
          '/v1/admin/live-sections/$sectionId/blocks/$blockId');

  /// Bank check. Advisory here — `publish` runs it again and is the gate.
  Future<PreviewResult> preview(String sectionId) async {
    final res = await ref
        .read(dioProvider)
        .get('/v1/admin/live-sections/$sectionId/preview');
    return PreviewResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AdminSectionDetail> publish(String sectionId) async {
    final res = await ref
        .read(dioProvider)
        .post('/v1/admin/live-sections/$sectionId/publish');
    return AdminSectionDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AdminSection> cancel(String sectionId) async {
    final res = await ref
        .read(dioProvider)
        .post('/v1/admin/live-sections/$sectionId/cancel');
    return AdminSection.fromJson(res.data as Map<String, dynamic>);
  }
}

final adminSectionsRepositoryProvider =
    Provider<AdminSectionsRepository>((ref) => AdminSectionsRepository(ref));

final adminSectionsProvider = FutureProvider<List<AdminSection>>((ref) async {
  ref.watch(authControllerProvider);
  return ref.read(adminSectionsRepositoryProvider).list();
});

final adminSectionDetailProvider =
    FutureProvider.family<AdminSectionDetail, String>((ref, id) async {
  ref.watch(authControllerProvider);
  return ref.read(adminSectionsRepositoryProvider).detail(id);
});
