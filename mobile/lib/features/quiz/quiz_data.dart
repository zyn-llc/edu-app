import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../core/math_text.dart';

// ---------------- Catalog (drives the picker) ----------------
class GradeCount {
  final int grade;
  final int count;
  GradeCount(this.grade, this.count);
}

class CtxCount {
  final String code;
  final int count;
  CtxCount(this.code, this.count);
}

class TopicEntry {
  final String id;
  final String title;
  final int count;
  TopicEntry(this.id, this.title, this.count);
}

class Catalog {
  final List<GradeCount> grades;
  final List<CtxCount> contexts;
  final List<TopicEntry> topics;
  Catalog(this.grades, this.contexts, this.topics);

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog(
        [for (final g in (j['grades'] as List)) GradeCount(g['grade'], g['count'])],
        [for (final c in (j['exam_contexts'] as List)) CtxCount(c['code'], c['count'])],
        [for (final t in (j['topics'] as List)) TopicEntry(t['id'], t['title'], t['count'])],
      );
}

// ---------------- Question (public projection — no answer key) ----------------
class QChoice {
  final String optionKey;
  final String text;
  QChoice(this.optionKey, this.text);
}

class Question {
  final String id;
  final String type;
  final String stem;
  final List<QChoice> options;
  Question(this.id, this.type, this.stem, this.options);

  /// chaqirilsa, biri unutilib qolishi aniq.
  factory Question.fromJson(Map<String, dynamic> j) => Question(
        j['id'],
        j['type'],
        renderMathText(j['stem'] as String?),
        [
          for (final o in (j['options'] as List))
            QChoice(o['option_key'], renderMathText(o['text'] as String?))
        ],
      );
}

class GradeResult {
  final bool isCorrect;
  final int score;
  final int maxScore;
  final List<String> correctOptionIds;
  final String? explanation;

  final int xpAwarded;
  final int coinsAwarded;
  final int coinsDelta;
  final String? rewardReason;

  GradeResult(this.isCorrect, this.score, this.maxScore,
      {this.correctOptionIds = const [],
      this.explanation,
      this.xpAwarded = 0,
      this.coinsAwarded = 0,
      this.coinsDelta = 0,
      this.rewardReason});

  factory GradeResult.fromJson(Map<String, dynamic> j) => GradeResult(
        j['is_correct'] ?? false,
        j['score'] ?? 0,
        j['max_score'] ?? 1,
        correctOptionIds: [
          for (final x in (j['correct_option_ids'] ?? [])) x as String
        ],
        explanation: j['explanation'],
        xpAwarded: (j['xp_awarded'] as num?)?.toInt() ?? 0,
        coinsAwarded: (j['coins_awarded'] as num?)?.toInt() ?? 0,
        coinsDelta: (j['coins_delta'] as num?)?.toInt() ?? 0,
        rewardReason: j['reward_reason'] as String?,
      );
}

// ---------------- Repository ----------------
class QuizRepository {
  final Ref ref;
  QuizRepository(this.ref);

  Future<Catalog> fetchCatalog(String subjectId, {int? grade}) async {
    final res = await ref.read(dioProvider).get(
      '/v1/subjects/$subjectId/catalog',
      queryParameters: {if (grade != null) 'grade': grade},
    );
    return Catalog.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Question>> fetchQuestions(
    String subjectId, {
    int? grade,
    String? topicId,
    String? examContext,
    int limit = 10,
  }) async {
    final params = <String, dynamic>{'subject_id': subjectId, 'limit': limit};
    if (grade != null) params['grade'] = grade;
    if (topicId != null) params['topic_id'] = topicId;
    if (examContext != null) params['exam_context'] = examContext;
    final res = await ref.read(dioProvider).get('/v1/questions', queryParameters: params);
    return [for (final q in (res.data['items'] as List)) Question.fromJson(q)];
  }

  Future<GradeResult> submit(String questionId, String? optionKey, int responseMs) async {
    return submitPayload(
        questionId,
        {'option_ids': optionKey == null ? [] : [optionKey]},
        responseMs);
  }

  /// Generic form — typed answers send {'value': ...} (numeric) or
  Future<GradeResult> submitPayload(
      String questionId, Map<String, dynamic> payload, int responseMs) async {
    final res = await ref.read(dioProvider).post('/v1/submissions', data: {
      'question_id': questionId,
      'payload': payload,
      'response_ms': responseMs,
    });
    return GradeResult.fromJson(res.data as Map<String, dynamic>);
  }
}

final quizRepositoryProvider = Provider<QuizRepository>((ref) => QuizRepository(ref));

typedef CatalogArgs = ({String subjectId, int? grade});

final catalogProvider =
    FutureProvider.family<Catalog, CatalogArgs>((ref, args) async {
  ref.watch(localeCodeProvider);
  return ref
      .read(quizRepositoryProvider)
      .fetchCatalog(args.subjectId, grade: args.grade);
});
