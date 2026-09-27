import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';

/// Grammatika mashqi — `/v1/grammar`.
///
/// Kontrakt: `backend/app/api/v1/grammar.py`.
///
/// JAVOB SAVOL BILAN KELMAYDI. `/practice` faqat savol va variantlarni
/// beradi; to'g'ri variant `/answer` javobida, ya'ni o'quvchi tanlagandan
/// KEYIN keladi. Shuning uchun bu yerda "to'g'ri javobni oldindan bilish"
/// degan holat yo'q va bo'lishi ham mumkin emas.

/// Mavzu bo'yicha holat. Nomi SERVERDAN keladi — chegaralar (nechta urinish,
/// qanday aniqlik) bitta joyda, `services/grammar.py` da turishi kerak.
enum TopicState { unseen, learning, weak, mastered }

TopicState topicStateFrom(String? s) => switch (s) {
      'mastered' => TopicState.mastered,
      'weak' => TopicState.weak,
      'learning' => TopicState.learning,
      _ => TopicState.unseen,
    };

class GrammarTopic {
  final String topic;
  final String cefrLevel;
  final int questions;
  final int attempts;
  final int correct;
  final double? accuracy;
  final TopicState state;

  const GrammarTopic({
    required this.topic,
    required this.cefrLevel,
    required this.questions,
    required this.attempts,
    required this.correct,
    required this.accuracy,
    required this.state,
  });

  factory GrammarTopic.fromJson(Map<String, dynamic> j) => GrammarTopic(
        topic: j['topic'] as String,
        cefrLevel: j['cefr_level'] as String? ?? 'A1',
        questions: (j['questions'] as num?)?.toInt() ?? 0,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        state: topicStateFrom(j['state'] as String?),
      );
}

class GrammarOption {
  final String id;
  final String text;

  const GrammarOption({required this.id, required this.text});

  factory GrammarOption.fromJson(Map<String, dynamic> j) =>
      GrammarOption(id: j['id'] as String, text: j['text'] as String);
}

class GrammarQuestion {
  final String id;
  final String language;
  final String cefrLevel;
  final String topic;
  final String questionText;
  final List<GrammarOption> options;

  const GrammarQuestion({
    required this.id,
    required this.language,
    required this.cefrLevel,
    required this.topic,
    required this.questionText,
    required this.options,
  });

  factory GrammarQuestion.fromJson(Map<String, dynamic> j) => GrammarQuestion(
        id: j['id'] as String,
        language: j['language'] as String? ?? 'en',
        cefrLevel: j['cefr_level'] as String? ?? 'A1',
        topic: j['topic'] as String? ?? '',
        questionText: j['question_text'] as String,
        options: [
          for (final o in (j['options'] as List? ?? const []))
            GrammarOption.fromJson(o as Map<String, dynamic>)
        ],
      );
}

class GrammarAnswer {
  final bool correct;
  final String correctOptionId;

  /// Bank'da BITTA savolda ham izoh yo'q (23 600/23 600). Maydon bor,
  /// chunki to'ldirilganda klient o'zgarmasligi kerak.
  final String? explanation;

  /// Izoh yo'qligi uchun hech bo'lmasa qaysi qoida ekani ko'rsatiladi.
  final String topic;
  final int answeredToday;
  final int coinsAwarded;

  const GrammarAnswer({
    required this.correct,
    required this.correctOptionId,
    required this.explanation,
    required this.topic,
    required this.answeredToday,
    required this.coinsAwarded,
  });

  factory GrammarAnswer.fromJson(Map<String, dynamic> j) => GrammarAnswer(
        correct: j['correct'] == true,
        correctOptionId: j['correct_option_id'] as String? ?? '',
        explanation: j['explanation'] as String?,
        topic: j['topic'] as String? ?? '',
        answeredToday: (j['answered_today'] as num?)?.toInt() ?? 0,
        coinsAwarded: (j['coins_awarded'] as num?)?.toInt() ?? 0,
      );
}

class LevelProgress {
  final String cefrLevel;
  final int topics;
  final int unseen;
  final int learning;
  final int weak;
  final int mastered;
  final double shareMastered;

  const LevelProgress({
    required this.cefrLevel,
    required this.topics,
    required this.unseen,
    required this.learning,
    required this.weak,
    required this.mastered,
    required this.shareMastered,
  });

  factory LevelProgress.fromJson(Map<String, dynamic> j) => LevelProgress(
        cefrLevel: j['cefr_level'] as String? ?? 'A1',
        topics: (j['topics'] as num?)?.toInt() ?? 0,
        unseen: (j['unseen'] as num?)?.toInt() ?? 0,
        learning: (j['learning'] as num?)?.toInt() ?? 0,
        weak: (j['weak'] as num?)?.toInt() ?? 0,
        mastered: (j['mastered'] as num?)?.toInt() ?? 0,
        shareMastered: (j['share_mastered'] as num?)?.toDouble() ?? 0,
      );
}

class GrammarMastery {
  final String language;
  final List<LevelProgress> levels;
  final List<GrammarTopic> weakTopics;

  /// Server tavsiya qilgan mavzu. `null` — hamma narsa o'zlashtirilgan.
  final String? nextTopic;

  const GrammarMastery({
    required this.language,
    required this.levels,
    required this.weakTopics,
    required this.nextTopic,
  });

  static const empty =
      GrammarMastery(language: '', levels: [], weakTopics: [], nextTopic: null);

  factory GrammarMastery.fromJson(Map<String, dynamic> j) => GrammarMastery(
        language: j['language'] as String? ?? '',
        levels: [
          for (final l in (j['levels'] as List? ?? const []))
            LevelProgress.fromJson(l as Map<String, dynamic>)
        ],
        weakTopics: [
          for (final w in (j['weak_topics'] as List? ?? const []))
            GrammarTopic(
              topic: (w as Map<String, dynamic>)['topic'] as String,
              cefrLevel: '',
              questions: 0,
              attempts: (w['attempts'] as num?)?.toInt() ?? 0,
              correct: 0,
              accuracy: (w['accuracy'] as num?)?.toDouble(),
              state: TopicState.weak,
            )
        ],
        nextTopic: j['next_topic'] as String?,
      );
}

// --------------------------------------------------------------------------- //
//  Repository + providers                                                      //
// --------------------------------------------------------------------------- //
class GrammarQuery {
  final String language;
  final String? level;
  final String? topic;

  const GrammarQuery({required this.language, this.level, this.topic});

  GrammarQuery copyWith({String? level, String? topic,
      bool clearLevel = false, bool clearTopic = false}) =>
      GrammarQuery(
        language: language,
        level: clearLevel ? null : (level ?? this.level),
        topic: clearTopic ? null : (topic ?? this.topic),
      );

  @override
  bool operator ==(Object other) =>
      other is GrammarQuery &&
      other.language == language &&
      other.level == level &&
      other.topic == topic;

  @override
  int get hashCode => Object.hash(language, level, topic);
}

class GrammarRepository {
  final Ref ref;
  GrammarRepository(this.ref);

  Future<List<GrammarTopic>> topics(String language, {String? level}) async {
    final res = await ref.read(dioProvider).get('/v1/grammar/topics',
        queryParameters: {
          'language': language,
          if (level != null) 'level': level,
        });
    return [
      for (final e in (res.data as Map<String, dynamic>)['items'] as List)
        GrammarTopic.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<List<GrammarQuestion>> practice(GrammarQuery q,
      {int limit = 10}) async {
    final res = await ref.read(dioProvider).get('/v1/grammar/practice',
        queryParameters: {
          'language': q.language,
          if (q.level != null) 'level': q.level,
          if (q.topic != null) 'topic': q.topic,
          'limit': limit,
        });
    return [
      for (final e in (res.data as Map<String, dynamic>)['items'] as List)
        GrammarQuestion.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<GrammarAnswer> answer(String questionId, String? optionId,
      {int? responseMs}) async {
    final res = await ref.read(dioProvider).post('/v1/grammar/answer', data: {
      'question_id': questionId,
      if (optionId != null) 'option_id': optionId,
      if (responseMs != null) 'response_ms': responseMs,
    });
    return GrammarAnswer.fromJson(res.data as Map<String, dynamic>);
  }

  Future<GrammarMastery> mastery(String language) async {
    final res = await ref.read(dioProvider).get('/v1/grammar/mastery',
        queryParameters: {'language': language});
    return GrammarMastery.fromJson(res.data as Map<String, dynamic>);
  }
}

final grammarRepositoryProvider =
    Provider<GrammarRepository>((ref) => GrammarRepository(ref));

final grammarTopicsProvider =
    FutureProvider.family<List<GrammarTopic>, GrammarQuery>((ref, q) async {
  ref.watch(authControllerProvider);
  return ref.read(grammarRepositoryProvider).topics(q.language, level: q.level);
});

final grammarMasteryProvider =
    FutureProvider.family<GrammarMastery, String>((ref, language) async {
  ref.watch(authControllerProvider);
  return ref.read(grammarRepositoryProvider).mastery(language);
});
