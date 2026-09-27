// O'qish moduli — klient shartnomasi.
//
// ENG MUHIMI: `ReadingQuestion` da DALIL JUMLASI uchun maydon yo'q.
// Dalil — matndagi aynan o'sha gap, ya'ni javobning o'zi. Agar klient uni
// o'qiy oladigan bo'lsa, serverdagi kichik o'zgarish uni ekranga chiqarib
// yuborishi mumkin va o'quvchi matnni umuman o'qimay qo'yardi. Maydonning
// YO'QLIGI — bu xatoni imkonsiz qiladi.
//
// Ishga tushirish:
//     flutter test test/reading_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:topagon/features/reading/reading_data.dart';

void main() {
  group('passageStateFrom', () {
    test('maps the states the server sends', () {
      expect(passageStateFrom('new'), PassageState.newPassage);
      expect(passageStateFrom('started'), PassageState.started);
      expect(passageStateFrom('done'), PassageState.done);
    });

    test('unknown or missing reads as not started', () {
      expect(passageStateFrom(null), PassageState.newPassage);
      expect(passageStateFrom('half_read'), PassageState.newPassage);
    });
  });

  group('ReadingQuestion', () {
    const payload = {
      'id': 'rd_A1_002_q01',
      'question_type': 'literal',
      'question_text': 'Где работает отец?',
      'options': [
        {'id': 'a', 'text': 'В школе'},
        {'id': 'b', 'text': 'В больнице'},
      ],
    };

    test('parses a question from the passage payload', () {
      final q = ReadingQuestion.fromJson(payload);
      expect(q.id, 'rd_A1_002_q01');
      expect(q.questionType, 'literal');
      expect(q.options.length, 2);
    });

    test('the payload carries neither the answer nor the evidence', () {
      expect(payload.containsKey('correct_option_id'), isFalse);
      expect(payload.containsKey('evidence_span'), isFalse);
    });

    test('and the model has nowhere to put them even if sent', () {
      // Passing them anyway must not surface them anywhere.
      final q = ReadingQuestion.fromJson(const {
        'id': 'x',
        'question_text': 'q',
        'options': [],
        'correct_option_id': 'b',
        'evidence_span': 'the sentence that gives it away',
      });
      expect(q.toString().contains('evidence'), isFalse);
      expect(q.toString().contains('give'), isFalse);
    });
  });

  group('ReadingAnswer', () {
    test('carries the evidence back AFTER answering', () {
      final a = ReadingAnswer.fromJson(const {
        'correct': true,
        'correct_option_id': 'b',
        'evidence_span': 'Мой отец работает врачом.',
        'question_type': 'literal',
        'answered': 3,
        'total_questions': 8,
        'state': 'started',
        'coins_awarded': 0,
      });
      expect(a.correct, isTrue);
      expect(a.evidenceSpan, 'Мой отец работает врачом.');
      expect(a.state, PassageState.started);
    });

    test('a wrong answer is the default, never an accidental pass', () {
      final a = ReadingAnswer.fromJson(const {});
      expect(a.correct, isFalse);
      expect(a.coinsAwarded, 0);
      expect(a.state, PassageState.newPassage);
    });

    test('a finished passage reports done and may pay once', () {
      final a = ReadingAnswer.fromJson(const {
        'correct': false,
        'correct_option_id': 'a',
        'answered': 8,
        'total_questions': 8,
        'state': 'done',
        'coins_awarded': 10,
      });
      expect(a.state, PassageState.done);
      expect(a.coinsAwarded, 10);
      // "Done" says the text was read, not that it was understood.
      expect(a.correct, isFalse);
    });
  });

  group('PassageSummary', () {
    PassageSummary s({int questions = 8, int answered = 0}) =>
        PassageSummary.fromJson({
          'id': 'rd_B1_004',
          'language': 'ru',
          'cefr_level': 'B1',
          'topic': 'Наука',
          'word_count': 260,
          'read_minutes': 2,
          'source': 'gold',
          'questions': questions,
          'answered': answered,
          'correct': 0,
          'state': answered == 0 ? 'new' : 'started',
        });

    test('parses the list row', () {
      final p = s();
      expect(p.cefrLevel, 'B1');
      expect(p.readMinutes, 2);
      expect(p.state, PassageState.newPassage);
    });

    test('share answered is a 0..1 fraction', () {
      expect(s(questions: 8, answered: 4).shareAnswered, 0.5);
      expect(s(questions: 8, answered: 8).shareAnswered, 1.0);
    });

    test('a passage with no questions does not divide by zero', () {
      expect(s(questions: 0).shareAnswered, 0);
    });

    test('share never exceeds 1 even if the server over-counts', () {
      // Re-reading can produce more attempts than there are questions.
      expect(s(questions: 4, answered: 9).shareAnswered, 1.0);
    });
  });

  group('ReadingQuery', () {
    test('defaults to russian — the only language with passages', () {
      const q = ReadingQuery();
      expect(q.language, 'ru');
      expect(q.level, isNull);
    });

    test('clearing the level filter works', () {
      const q = ReadingQuery(level: 'B1');
      expect(q.copyWith(clearLevel: true).level, isNull);
    });

    test('value equality — providers are keyed by this', () {
      expect(const ReadingQuery(level: 'A1'), const ReadingQuery(level: 'A1'));
      expect(const ReadingQuery(level: 'A1').hashCode,
          const ReadingQuery(level: 'A1').hashCode);
      expect(const ReadingQuery(level: 'A1'),
          isNot(const ReadingQuery(level: 'A2')));
    });
  });

  group('ReadingLevelProgress', () {
    test('parses a level row', () {
      final p = ReadingLevelProgress.fromJson(
          const {'cefr_level': 'A1', 'passages': 5, 'done': 2,
                 'share_done': 0.4});
      expect(p.passages, 5);
      expect(p.shareDone, 0.4);
    });

    test('an empty level parses to zeros', () {
      final p = ReadingLevelProgress.fromJson(const {});
      expect(p.passages, 0);
      expect(p.shareDone, 0);
    });
  });
}
