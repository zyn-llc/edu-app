// Grammatika moduli — klient tomondagi shartnoma.
//
// O'zlashtirish chegaralari bu yerda TEKSHIRILMAYDI: ular serverda
// (`services/grammar.py`, 38 ta test). Klient faqat holat NOMINI oladi —
// ikki joyda ikki xil chegara bo'lsa, ro'yxatdagi belgi bilan tavsiya bir
// biriga zid bo'lib qolardi.
//
// Ishga tushirish:
//     flutter test test/grammar_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:topagon/features/grammar/grammar_data.dart';

void main() {
  group('topicStateFrom', () {
    test('maps every state the server can send', () {
      expect(topicStateFrom('unseen'), TopicState.unseen);
      expect(topicStateFrom('learning'), TopicState.learning);
      expect(topicStateFrom('weak'), TopicState.weak);
      expect(topicStateFrom('mastered'), TopicState.mastered);
    });

    test('an unknown or missing state falls back to unseen', () {
      // A new state added server-side must not crash an older client; the
      // safe reading is "nothing known about this topic yet".
      expect(topicStateFrom(null), TopicState.unseen);
      expect(topicStateFrom('almost_there'), TopicState.unseen);
      expect(topicStateFrom(''), TopicState.unseen);
    });

    test('the client defines no thresholds of its own', () {
      // If this file ever computes mastery from attempts/correct, the list
      // badge and the recommendation can disagree with each other.
      expect(TopicState.values.length, 4);
    });
  });

  group('GrammarQuestion.fromJson', () {
    const practice = {
      'id': 'gram_en_a1_q0741',
      'language': 'en',
      'cefr_level': 'A1',
      'topic': 'Present simple — affirmative',
      'question_text': 'David ___ in the park every morning.',
      'options': [
        {'id': 'a', 'text': 'walk'},
        {'id': 'b', 'text': 'walks'},
      ],
    };

    test('parses a practice question', () {
      final q = GrammarQuestion.fromJson(practice);
      expect(q.id, 'gram_en_a1_q0741');
      expect(q.options.length, 2);
      expect(q.options.first.text, 'walk');
      expect(q.topic, 'Present simple — affirmative');
    });

    test('the practice payload carries NO answer field to parse', () {
      // The model has nowhere to put a correct answer, so a future server
      // change that leaked one could not be silently displayed.
      expect(practice.containsKey('correct_option_id'), isFalse);
      expect(practice.containsKey('explanation'), isFalse);
    });
  });

  group('GrammarAnswer.fromJson', () {
    test('reads the verdict returned after answering', () {
      final a = GrammarAnswer.fromJson(const {
        'correct': true,
        'correct_option_id': 'b',
        'explanation': null,
        'topic': 'Present simple — affirmative',
        'answered_today': 11,
        'coins_awarded': 5,
      });
      expect(a.correct, isTrue);
      expect(a.correctOptionId, 'b');
      expect(a.coinsAwarded, 5);
    });

    test('a null explanation is the normal case, not an error', () {
      // 23600 of 23600 questions have none.
      final a = GrammarAnswer.fromJson(const {
        'correct': false,
        'correct_option_id': 'c',
        'topic': 'Articles',
      });
      expect(a.explanation, isNull);
      // The topic is what the student gets instead, so it must survive.
      expect(a.topic, 'Articles');
    });

    test('a wrong answer is the default, never an accidental pass', () {
      final a = GrammarAnswer.fromJson(const {});
      expect(a.correct, isFalse);
      expect(a.coinsAwarded, 0);
    });
  });

  group('LevelProgress', () {
    test('parses a level row', () {
      final p = LevelProgress.fromJson(const {
        'cefr_level': 'A1',
        'topics': 34,
        'unseen': 30,
        'learning': 2,
        'weak': 1,
        'mastered': 1,
        'share_mastered': 0.0294,
      });
      expect(p.topics, 34);
      expect(p.unseen + p.learning + p.weak + p.mastered, 34);
      expect(p.shareMastered, closeTo(0.0294, 1e-9));
    });

    test('an empty level parses to zeros, not nulls', () {
      final p = LevelProgress.fromJson(const {});
      expect(p.topics, 0);
      expect(p.shareMastered, 0);
    });
  });

  group('GrammarMastery', () {
    test('parses levels, weak topics and the recommendation', () {
      final m = GrammarMastery.fromJson(const {
        'language': 'en',
        'levels': [
          {'cefr_level': 'A1', 'topics': 10, 'mastered': 3,
           'share_mastered': 0.3},
        ],
        'weak_topics': [
          {'topic': 'Articles', 'attempts': 12, 'accuracy': 0.25},
        ],
        'next_topic': 'Articles',
      });
      expect(m.levels.single.cefrLevel, 'A1');
      expect(m.weakTopics.single.topic, 'Articles');
      expect(m.weakTopics.single.state, TopicState.weak);
      expect(m.nextTopic, 'Articles');
    });

    test('a finished language has no recommendation', () {
      final m = GrammarMastery.fromJson(const {
        'language': 'en', 'levels': [], 'weak_topics': [],
      });
      expect(m.nextTopic, isNull);
      expect(m.weakTopics, isEmpty);
    });
  });

  group('GrammarQuery', () {
    const base = GrammarQuery(language: 'en', level: 'A1', topic: 'Articles');

    test('clearing a filter actually clears it', () {
      expect(base.copyWith(clearLevel: true).level, isNull);
      expect(base.copyWith(clearTopic: true).topic, isNull);
      expect(base.copyWith(clearTopic: true).level, 'A1');
    });

    test('value equality — providers are keyed by this', () {
      expect(const GrammarQuery(language: 'en', level: 'A1'),
          const GrammarQuery(language: 'en', level: 'A1'));
      expect(const GrammarQuery(language: 'en', level: 'A1').hashCode,
          const GrammarQuery(language: 'en', level: 'A1').hashCode);
      expect(const GrammarQuery(language: 'en'),
          isNot(const GrammarQuery(language: 'de')));
    });
  });
}
