import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
class LinkCode {
  final String code;
  final int expiresInSeconds;
  LinkCode(this.code, this.expiresInSeconds);
  factory LinkCode.fromJson(Map<String, dynamic> j) => LinkCode(
        j['code'] as String,
        (j['expires_in_seconds'] as num?)?.toInt() ?? 600,
      );
}

class ChildSummary {
  final String studentId;
  final String? displayName;
  final int? grade;
  final String? regionCode;
  final int? avatarColor;
  final Progress progress;

  /// shug'ullandi" ni darrov tushunadi.
  final int answered7d;
  final double accuracy7d;
  final int activeDays7d;
  final DateTime? lastPracticedAt;

  ChildSummary(this.studentId, this.displayName, this.grade, this.regionCode,
      this.progress,
      {this.avatarColor,
      this.answered7d = 0,
      this.accuracy7d = 0,
      this.activeDays7d = 0,
      this.lastPracticedAt});

  factory ChildSummary.fromJson(Map<String, dynamic> j) => ChildSummary(
        j['student_id'] as String,
        j['display_name'] as String?,
        (j['grade'] as num?)?.toInt(),
        j['region_code'] as String?,
        Progress.fromJson(j['progress'] as Map<String, dynamic>),
        avatarColor: (j['avatar_color'] as num?)?.toInt(),
        answered7d: (j['answered_7d'] as num?)?.toInt() ?? 0,
        accuracy7d: (j['accuracy_7d'] as num?)?.toDouble() ?? 0,
        activeDays7d: (j['active_days_7d'] as num?)?.toInt() ?? 0,
        lastPracticedAt: j['last_practiced_at'] == null
            ? null
            : DateTime.tryParse(j['last_practiced_at'] as String)?.toLocal(),
      );
}

class ParentRepository {
  final Ref ref;
  ParentRepository(this.ref);

  Future<LinkCode> createLinkCode() async {
    final res = await ref.read(dioProvider).post('/v1/parent/link-code');
    return LinkCode.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> link(String code) async {
    await ref.read(dioProvider).post('/v1/parent/link', data: {'code': code});
  }

  Future<List<ChildSummary>> children() async {
    final res = await ref.read(dioProvider).get('/v1/parent/children');
    final list = (res.data['children'] as List).cast<Map<String, dynamic>>();
    return list.map(ChildSummary.fromJson).toList();
  }

  Future<Analysis> childAnalysis(String studentId) async {
    final res = await ref
        .read(dioProvider)
        .get('/v1/parent/children/$studentId/analysis');
    return Analysis.fromJson(res.data as Map<String, dynamic>);
  }
}

final parentRepositoryProvider =
    Provider<ParentRepository>((ref) => ParentRepository(ref));

final childAnalysisProvider =
    FutureProvider.family<Analysis, String>((ref, studentId) async {
  return ref.read(parentRepositoryProvider).childAnalysis(studentId);
});

/// Ulangan farzandlar.
///
final childrenProvider = FutureProvider<List<ChildSummary>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isAuthenticated) return [];
  return ref.read(parentRepositoryProvider).children();
});
