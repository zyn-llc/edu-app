import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';

class Subject {
  final String id;
  final String code;
  final String name;
  final String? imageUrl;

  final int questionCount;

  final int translatedCount;

  final int topicCount;

  final int answered;
  final int correct;

  final double accuracy;

  final DateTime? lastPracticedAt;

  const Subject({
    required this.id,
    required this.code,
    required this.name,
    this.imageUrl,
    this.questionCount = 0,
    this.translatedCount = 0,
    this.topicCount = 0,
    this.answered = 0,
    this.correct = 0,
    this.accuracy = 0,
    this.lastPracticedAt,
  });

  bool get isStarted => answered > 0;

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        imageUrl: resolveImage(j['image_url'] as String?),
        questionCount: (j['question_count'] as num?)?.toInt() ?? 0,
        translatedCount: (j['translated_count'] as num?)?.toInt() ??
            (j['question_count'] as num?)?.toInt() ??
            0,
        topicCount: (j['topic_count'] as num?)?.toInt() ?? 0,
        answered: (j['answered'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        accuracy: (j['accuracy'] as num?)?.toDouble() ?? 0,
        lastPracticedAt: j['last_practiced_at'] == null
            ? null
            : DateTime.tryParse(j['last_practiced_at'] as String)?.toLocal(),
      );
}

class SubjectsRepository {
  final Ref ref;
  SubjectsRepository(this.ref);

  Future<List<Subject>> fetchSubjects() async {
    final dio = ref.read(dioProvider);
    final res = await dio.get('/v1/subjects');
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    final list = items.map(Subject.fromJson).toList();
    //
    // qo'shildi.
    list.sort((a, b) {
      final ae = a.questionCount <= 0 ? 1 : 0;
      final be = b.questionCount <= 0 ? 1 : 0;
      return ae != be ? ae - be : 0;
    });
    return list;
  }
}

final subjectsRepositoryProvider =
    Provider<SubjectsRepository>((ref) => SubjectsRepository(ref));

final hasTranslatedContentProvider = Provider<bool>((ref) {
  return ref.watch(subjectsProvider).maybeWhen(
        data: (list) => list.any((s) => s.translatedCount > 0),
        orElse: () => false,
      );
});

final subjectsProvider = FutureProvider<List<Subject>>((ref) async {
  ref.watch(localeCodeProvider);
  ref.watch(authControllerProvider);
  return ref.read(subjectsRepositoryProvider).fetchSubjects();
});
