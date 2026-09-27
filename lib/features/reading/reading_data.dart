import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';

/// O'qish va tushunish — `/v1/reading`.
///
/// Kontrakt: `backend/app/api/v1/reading.py`.
///
/// DALIL JUMLASI JAVOBDAN KEYIN KELADI. `/passages/{id}` savolni beradi,
/// lekin dalilni ham, to'g'ri variantni ham YUBORMAYDI — dalil matndagi
/// aynan o'sha gap, ya'ni javobning o'zi. Shuning uchun bu yerdagi
/// `ReadingQuestion` da dalil uchun MAYDON HAM YO'Q: server kelajakda
/// yuborib qo'ysa ham, klient uni ko'rsata olmaydi.

enum PassageState { newPassage, started, done }

PassageState passageStateFrom(String? s) => switch (s) {
      'done' => PassageState.done,
      'started' => PassageState.started,
      _ => PassageState.newPassage,
    };

class PassageSummary {
  final String id;
  final String language;
  final String cefrLevel;
  final String? topic;
  final int wordCount;
  final int readMinutes;
  final String? source;
  final int questions;
  final int answered;
  final int correct;
  final PassageState state;

  const PassageSummary({
    required this.id,
    required this.language,
    required this.cefrLevel,
    required this.topic,
    required this.wordCount,
    required this.readMinutes,
    required this.source,
    required this.questions,
    required this.answered,
    required this.correct,
    required this.state,
  });

  factory PassageSummary.fromJson(Map<String, dynamic> j) => PassageSummary(
        id: j['id'] as String,
        language: j['language'] as String? ?? 'ru',
        cefrLevel: j['cefr_level'] as String? ?? 'A1',
        topic: j['topic'] as String?,
        wordCount: (j['word_count'] as num?)?.toInt() ?? 0,
        readMinutes: (j['read_minutes'] as num?)?.toInt() ?? 1,
        source: j['source'] as String?,
        questions: (j['questions'] as num?)?.toInt() ?? 0,
        answered: (j['answered'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        state: passageStateFrom(j['state'] as String?),
      );

  /// 0..1, savollar bo'yicha. Bo'sh matnda 0 — nolga bo'lish emas.
  double get shareAnswered =>
      questions == 0 ? 0 : (answered / questions).clamp(0, 1).toDouble();
}

class ReadingOption {
  final String id;
  final String text;

  const ReadingOption({required this.id, required this.text});

  factory ReadingOption.fromJson(Map<String, dynamic> j) =>
      ReadingOption(id: j['id'] as String, text: j['text'] as String);
}

class ReadingQuestion {
  final String id;
  final String questionType;
  final String questionText;
  final List<ReadingOption> options;

  // Dalil jumlasi uchun maydon ATAYLAB yo'q — yuqoridagi izohga qara.

  const ReadingQuestion({
    required this.id,
    required this.questionType,
    required this.questionText,
    required this.options,
  });

  factory ReadingQuestion.fromJson(Map<String, dynamic> j) => ReadingQuestion(
        id: j['id'] as String,
        questionType: j['question_type'] as String? ?? '',
        questionText: j['question_text'] as String,
        options: [
          for (final o in (j['options'] as List? ?? const []))
            ReadingOption.fromJson(o as Map<String, dynamic>)
        ],
      );
}

class PassageDetail {
  final String id;
  final String cefrLevel;
  final String? topic;
  final String body;
  final int wordCount;
  final int readMinutes;
  final List<ReadingQuestion> questions;

  const PassageDetail({
    required this.id,
    required this.cefrLevel,
    required this.topic,
    required this.body,
    required this.wordCount,
    required this.readMinutes,
    required this.questions,
  });

  factory PassageDetail.fromJson(Map<String, dynamic> j) => PassageDetail(
        id: j['id'] as String,
        cefrLevel: j['cefr_level'] as String? ?? 'A1',
        topic: j['topic'] as String?,
        body: j['body'] as String? ?? '',
        wordCount: (j['word_count'] as num?)?.toInt() ?? 0,
        readMinutes: (j['read_minutes'] as num?)?.toInt() ?? 1,
        questions: [
          for (final q in (j['questions'] as List? ?? const []))
            ReadingQuestion.fromJson(q as Map<String, dynamic>)
        ],
      );
}

class ReadingAnswer {
  final bool correct;
  final String correctOptionId;

  /// Matndagi AYNAN o'sha gap. 326/326 savolda bor — modulda "nega
  /// shunday" degan savolga javob beradigan yagona narsa.
  final String? evidenceSpan;

  final String questionType;
  final int answered;
  final int totalQuestions;
  final PassageState state;
  final int coinsAwarded;

  const ReadingAnswer({
    required this.correct,
    required this.correctOptionId,
    required this.evidenceSpan,
    required this.questionType,
    required this.answered,
    required this.totalQuestions,
    required this.state,
    required this.coinsAwarded,
  });

  factory ReadingAnswer.fromJson(Map<String, dynamic> j) => ReadingAnswer(
        correct: j['correct'] == true,
        correctOptionId: j['correct_option_id'] as String? ?? '',
        evidenceSpan: j['evidence_span'] as String?,
        questionType: j['question_type'] as String? ?? '',
        answered: (j['answered'] as num?)?.toInt() ?? 0,
        totalQuestions: (j['total_questions'] as num?)?.toInt() ?? 0,
        state: passageStateFrom(j['state'] as String?),
        coinsAwarded: (j['coins_awarded'] as num?)?.toInt() ?? 0,
      );
}

class ReadingLevelProgress {
  final String cefrLevel;
  final int passages;
  final int done;
  final double shareDone;

  const ReadingLevelProgress({
    required this.cefrLevel,
    required this.passages,
    required this.done,
    required this.shareDone,
  });

  factory ReadingLevelProgress.fromJson(Map<String, dynamic> j) =>
      ReadingLevelProgress(
        cefrLevel: j['cefr_level'] as String? ?? 'A1',
        passages: (j['passages'] as num?)?.toInt() ?? 0,
        done: (j['done'] as num?)?.toInt() ?? 0,
        shareDone: (j['share_done'] as num?)?.toDouble() ?? 0,
      );
}

// --------------------------------------------------------------------------- //
//  Repository + providers                                                      //
// --------------------------------------------------------------------------- //
class ReadingQuery {
  final String language;
  final String? level;

  const ReadingQuery({this.language = 'ru', this.level});

  ReadingQuery copyWith({String? level, bool clearLevel = false}) =>
      ReadingQuery(
          language: language, level: clearLevel ? null : (level ?? this.level));

  @override
  bool operator ==(Object other) =>
      other is ReadingQuery &&
      other.language == language &&
      other.level == level;

  @override
  int get hashCode => Object.hash(language, level);
}

class ReadingRepository {
  final Ref ref;
  ReadingRepository(this.ref);

  Future<List<PassageSummary>> passages(ReadingQuery q) async {
    final res = await ref.read(dioProvider).get('/v1/reading/passages',
        queryParameters: {
          'language': q.language,
          if (q.level != null) 'level': q.level,
        });
    return [
      for (final e in (res.data as Map<String, dynamic>)['items'] as List)
        PassageSummary.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<PassageDetail> passage(String id) async {
    final res = await ref.read(dioProvider).get('/v1/reading/passages/$id');
    return PassageDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ReadingAnswer> answer(String questionId, String? optionId,
      {int? responseMs}) async {
    final res = await ref.read(dioProvider).post('/v1/reading/answer', data: {
      'question_id': questionId,
      if (optionId != null) 'option_id': optionId,
      if (responseMs != null) 'response_ms': responseMs,
    });
    return ReadingAnswer.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<ReadingLevelProgress>> progress(String language) async {
    final res = await ref.read(dioProvider).get('/v1/reading/progress',
        queryParameters: {'language': language});
    return [
      for (final e in (res.data as Map<String, dynamic>)['levels'] as List)
        ReadingLevelProgress.fromJson(e as Map<String, dynamic>)
    ];
  }
}

final readingRepositoryProvider =
    Provider<ReadingRepository>((ref) => ReadingRepository(ref));

final passagesProvider =
    FutureProvider.family<List<PassageSummary>, ReadingQuery>((ref, q) async {
  ref.watch(authControllerProvider);
  return ref.read(readingRepositoryProvider).passages(q);
});

final passageProvider =
    FutureProvider.family<PassageDetail, String>((ref, id) async {
  ref.watch(authControllerProvider);
  return ref.read(readingRepositoryProvider).passage(id);
});
