// Lug'at moduli — klient tomondagi qarorlar.
//
// Takrorlash JADVALI bu yerda test qilinmaydi: u serverda (SM-2,
// `services/srs.py`, 27 ta test). Bu yerda faqat klient o'zi qaror
// qiladigan narsalar, va ularning har biri jim buziladigan turdan:
//
//   1. Baho tugmasi SM-2 ning qaysi bahosiga tushadi. Noto'g'ri bo'lsa,
//      "Bildim" so'zni ertaga qaytarardi va buni hech kim sezmaydi.
//   2. Tarjima qaysi tildan olinadi. Nemis lug'atida `ru` MANBADA YO'Q
//      (2950 tadan hech birida) — rus interfeysi bo'sh kartochka
//      ko'rsatmasligi kerak.
//   3. Nemis oti artikl bilan ko'rinadi.
//
// Ishga tushirish:
//     flutter test test/vocab_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:topagon/features/vocab/vocab_data.dart';

VocabEntry entry({
  String display = 'book',
  String? uz = 'kitob',
  String? ru = 'книга',
  String? en,
  String? article,
  String? ipa = '/bʊk/',
}) =>
    VocabEntry(
      id: 'en_A1_0001',
      language: 'en',
      display: display,
      lemma: 'book',
      ipa: ipa,
      pos: 'noun',
      topic: 'school',
      cefrLevel: 'A1',
      article: article,
      freqRank: 100,
      trUz: uz,
      trRu: ru,
      trEn: en,
      inDeck: false,
      state: null,
    );

void main() {
  group('RecallGrade', () {
    test('maps the three buttons onto the SM-2 grades the server expects', () {
      // 0 = lapse, 3 = the lowest passing grade, 5 = perfect. Anything else
      // and the schedule quietly diverges from what the button promised.
      expect(RecallGrade.forgot.value, 0);
      expect(RecallGrade.hard.value, 3);
      expect(RecallGrade.easy.value, 5);
    });

    test('"forgot" is below the server pass mark, the others are not', () {
      expect(RecallGrade.forgot.value, lessThan(3));
      expect(RecallGrade.hard.value, greaterThanOrEqualTo(3));
      expect(RecallGrade.easy.value, greaterThanOrEqualTo(3));
    });

    test('exactly three buttons — six-way self-grading slows a session', () {
      expect(RecallGrade.values.length, 3);
    });
  });

  group('VocabEntry.translation', () {
    test('uzbek interface prefers uz', () {
      expect(entry().translation('uz'), 'kitob');
    });

    test('russian interface prefers ru', () {
      expect(entry().translation('ru'), 'книга');
    });

    test('russian falls back to uz when ru is missing', () {
      // Every German entry is in this state: 2950/2950 have no ru.
      expect(entry(ru: null).translation('ru'), 'kitob');
      expect(entry(ru: '').translation('ru'), 'kitob');
    });

    test('uzbek falls back to ru when uz is missing', () {
      expect(entry(uz: null).translation('uz'), 'книга');
    });

    test('falls back to en only when both others are missing', () {
      expect(entry(uz: null, ru: null, en: 'book').translation('uz'), 'book');
      expect(entry(uz: null, ru: null, en: 'book').translation('ru'), 'book');
    });

    test('returns null rather than an empty card', () {
      expect(entry(uz: null, ru: null).translation('uz'), isNull);
      expect(entry(uz: '  ', ru: '').translation('ru'), isNull);
    });
  });

  group('VocabEntry.fromJson', () {
    test('keeps the article the server already folded into display', () {
      // "Tisch" is not a usable flashcard; "der Tisch" is. The server
      // assembles it so that every screen shows the same thing.
      final e = VocabEntry.fromJson(const {
        'id': 'de_A1_0007',
        'language': 'de',
        'display': 'der Tisch',
        'lemma': 'Tisch',
        'cefr_level': 'A1',
        'article': 'der',
        'tr_uz': 'stol',
      });
      expect(e.display, 'der Tisch');
      expect(e.article, 'der');
      expect(e.translation('uz'), 'stol');
    });

    test('survives the nulls the bank actually contains', () {
      // No example sentence exists in any of the 16915 entries, and German
      // has no ru/en at all.
      final e = VocabEntry.fromJson(const {
        'id': 'de_B1_0100',
        'language': 'de',
        'display': 'laufen',
        'lemma': 'laufen',
        'cefr_level': 'B1',
      });
      expect(e.ipa, isNull);
      expect(e.trRu, isNull);
      expect(e.inDeck, isFalse);
      expect(e.state, isNull);
    });

    test('in_deck and state come through for a card already added', () {
      final e = VocabEntry.fromJson(const {
        'id': 'en_A1_0001',
        'language': 'en',
        'display': 'book',
        'lemma': 'book',
        'cefr_level': 'A1',
        'in_deck': true,
        'state': 'review',
      });
      expect(e.inDeck, isTrue);
      expect(e.state, 'review');
    });
  });

  group('VocabStats', () {
    test('an empty deck does not divide by zero', () {
      expect(VocabStats.empty.masteredShare, 0);
      expect(
        const VocabStats(
                deckSize: 0, learning: 0, review: 0, mastered: 0, dueToday: 0)
            .masteredShare,
        0,
      );
    });

    test('mastered share is a 0..1 fraction of the deck', () {
      const s = VocabStats(
          deckSize: 40, learning: 10, review: 20, mastered: 10, dueToday: 3);
      expect(s.masteredShare, 0.25);
      expect(s.masteredShare, inInclusiveRange(0, 1));
    });

    test('missing fields default to zero rather than throwing', () {
      final s = VocabStats.fromJson(const {});
      expect(s.deckSize, 0);
      expect(s.dueToday, 0);
    });
  });

  group('VocabQuery', () {
    const base = VocabQuery(language: 'en', level: 'A1', topic: 'school');

    test('clearing a filter actually clears it', () {
      // copyWith(level: null) cannot distinguish "unset" from "clear", which
      // is why the explicit flags exist. Without them the chips could not be
      // deselected.
      expect(base.copyWith(clearLevel: true).level, isNull);
      expect(base.copyWith(clearTopic: true).topic, isNull);
      expect(base.copyWith(clearLevel: true).topic, 'school');
    });

    test('value equality — providers are keyed by this', () {
      // FutureProvider.family caches on ==; identity would refetch forever.
      expect(const VocabQuery(language: 'en', level: 'A1'),
          const VocabQuery(language: 'en', level: 'A1'));
      expect(const VocabQuery(language: 'en', level: 'A1').hashCode,
          const VocabQuery(language: 'en', level: 'A1').hashCode);
      expect(const VocabQuery(language: 'en', level: 'A1'),
          isNot(const VocabQuery(language: 'en', level: 'A2')));
    });
  });

  group('VocabLanguage', () {
    test('name follows the interface language', () {
      const lang = VocabLanguage(
          code: 'de',
          nameUz: 'Nemis tili',
          nameRu: 'Немецкий язык',
          vocabCount: 2950);
      expect(lang.name('uz'), 'Nemis tili');
      expect(lang.name('ru'), 'Немецкий язык');
      expect(lang.name('uz-Latn'), 'Nemis tili');
    });
  });

  group('ReviewResult', () {
    test('reads the schedule the server decided', () {
      final r = ReviewResult.fromJson(const {
        'entry_id': 'en_A1_0001',
        'state': 'review',
        'due_on': '2026-10-03',
        'interval_days': 6,
        'reviewed_today': 11,
        'coins_awarded': 5,
      });
      expect(r.dueOn, '2026-10-03');
      expect(r.intervalDays, 6);
      expect(r.coinsAwarded, 5);
    });

    test('no coins is the normal case, not an error', () {
      final r = ReviewResult.fromJson(const {'entry_id': 'x'});
      expect(r.coinsAwarded, 0);
      expect(r.state, 'learning');
    });
  });
}
