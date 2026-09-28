// Ekranga XOM KALIT chiqmasligi va IPA ko'rinmasligi.
//
// Ikkalasi ham "ishlayotgandek" ko'rinadigan xatolar: ilova yiqilmaydi,
// shunchaki o'quvchi `science_abstract` yoki `rʲɪˈʂɛnʲɪjə` ni ko'radi.

import 'package:flutter_test/flutter_test.dart';
import 'package:topagon/features/language/display_names.dart';
import 'package:topagon/features/language/readable_pronunciation.dart';

void main() {
  group('DisplayNames.topic', () {
    test('every topic key in the bank has an Uzbek name', () {
      // Bank'dagi 20 ta kalit — uchala tilda ham ayni shular.
      const fromBank = [
        'animals_plants', 'body_health', 'city_places', 'clothes',
        'communication_media', 'emotions_character', 'family_people',
        'food_drink', 'function_word', 'home_furniture', 'money_shopping',
        'school_study', 'science_abstract', 'society_state', 'sport_hobbies',
        'technology_internet', 'time_calendar', 'transport_travel',
        'weather_nature', 'work_professions',
      ];
      for (final key in fromBank) {
        final name = DisplayNames.topic(key, 'uz');
        expect(name, isNotEmpty);
        expect(name, isNot(contains('_')), reason: '$key is still raw');
        expect(name, isNot(equals(key)));
      }
      expect(DisplayNames.knownTopicKeys.toSet(), fromBank.toSet());
    });

    test('an unknown key is humanised, never shown raw', () {
      // Bank'ga yangi mavzu qo'shilsa, ilova buzilmasligi kerak.
      expect(DisplayNames.topic('brand_new_topic', 'uz'), 'Brand new topic');
      expect(DisplayNames.topic('brand_new_topic', 'uz'),
          isNot(contains('_')));
    });

    test('empty and null are empty, not "null"', () {
      expect(DisplayNames.topic(null, 'uz'), '');
      expect(DisplayNames.topic('', 'uz'), '');
    });

    test('russian interface gets russian names', () {
      expect(DisplayNames.topic('science_abstract', 'ru'),
          'Наука и отвлечённые понятия');
      expect(DisplayNames.topic('science_abstract', 'uz'),
          'Fan va mavhum tushunchalar');
    });
  });

  group('DisplayNames.pos', () {
    test('every POS key in each bank maps to Uzbek', () {
      const byLanguage = {
        'en': ['abbr', 'adj', 'adv', 'conj', 'det', 'exclam', 'modal',
               'noun', 'num', 'prep', 'pron', 'verb'],
        'de': ['adjective', 'adverb', 'function', 'noun', 'other', 'phrase',
               'verb'],
        'ru': ['adj', 'adv', 'conj', 'interj', 'noun', 'num', 'particle',
               'prep', 'pron', 'verb'],
      };
      byLanguage.forEach((lang, keys) {
        for (final k in keys) {
          final name = DisplayNames.pos(k, lang, 'uz');
          expect(name, isNotEmpty, reason: '$lang/$k');
          expect(name, isNot(equals(k)), reason: '$lang/$k is still raw');
        }
      });
    });

    test('preposition is named per language, as asked', () {
      expect(DisplayNames.pos('prep', 'ru', 'uz'), 'predlog');
      expect(DisplayNames.pos('prep', 'en', 'uz'), 'prepozitsiya');
    });

    test('german "function" is not mistaken for a noun', () {
      // `function` faqat nemis bank'ida bor; umumiy xaritada yo'q.
      expect(DisplayNames.pos('function', 'de', 'uz'), 'yordamchi so’z');
    });

    test('russian interface gets russian part-of-speech names', () {
      expect(DisplayNames.pos('noun', 'en', 'ru'), 'существительное');
    });
  });

  group('readablePronunciation — russian', () {
    test('cyrillic becomes readable latin with a stress mark', () {
      final p = readablePronunciation(
          lemma: 'решение', ipa: 'rʲɪˈʂɛnʲɪjə', language: 'ru');
      expect(p, isNotNull);
      expect(p, 'reshéniye');
    });

    test('no IPA symbol survives into the output', () {
      final p = readablePronunciation(
          lemma: 'что', ipa: 't͡ɕto', language: 'ru');
      for (final bad in ['ʂ', 'ɕ', 'ʲ', 'ɛ', 'ː', 'ˈ', '͡']) {
        expect(p, isNot(contains(bad)));
      }
    });

    test('works without any IPA at all — just no stress mark', () {
      final p =
          readablePronunciation(lemma: 'книга', ipa: null, language: 'ru');
      expect(p, 'kniga');
    });

    test('the tricky cyrillic letters are covered', () {
      expect(readablePronunciation(lemma: 'щука', language: 'ru'), 'shchuka');
      expect(readablePronunciation(lemma: 'жизнь', language: 'ru'), 'jizn');
      expect(readablePronunciation(lemma: 'язык', language: 'ru'), 'yazik');
    });
  });

  group('readablePronunciation — english / german', () {
    test('english is respelled from IPA, not shown as IPA', () {
      final p = readablePronunciation(
          lemma: 'April', ipa: '/ˈeɪprʌl/', language: 'en');
      expect(p, isNotNull);
      expect(p, isNot(contains('ɪ')));
      expect(p, isNot(contains('/')));
      expect(p!.toLowerCase(), startsWith('é'));
    });

    test('german loses the glottal stop and length marks', () {
      final p = readablePronunciation(
          lemma: 'Abfahrt', ipa: 'ˈʔapfaːt', language: 'de');
      expect(p, isNotNull);
      expect(p, isNot(contains('ʔ')));
      expect(p, isNot(contains('ː')));
    });

    test('nothing is shown when there is no IPA to work from', () {
      // Yomon taxminni chiqarishdan ko'ra jim turish yaxshiroq.
      expect(readablePronunciation(lemma: 'book', language: 'en'), isNull);
      expect(
          readablePronunciation(lemma: 'book', ipa: '', language: 'en'), isNull);
    });

    test('nothing is shown when the respelling adds no information', () {
      // `/bʊk/` -> `buk` — farqli, ko'rsatiladi. Lekin aynan teng bo'lsa yo'q.
      expect(readablePronunciation(lemma: 'no', ipa: 'no', language: 'de'),
          isNull);
    });

    test('an empty word never produces a line', () {
      expect(readablePronunciation(lemma: '  ', ipa: 'ˈxyz', language: 'en'),
          isNull);
    });
  });

  group('stressedSyllable', () {
    test('counts vowel groups before the stress mark', () {
      expect(stressedSyllable('ˈeɪprʌl'), 0);
      expect(stressedSyllable('rʲɪˈʂɛnʲɪjə'), 1);
      expect(stressedSyllable('nodrop'), isNull);
      expect(stressedSyllable(null), isNull);
    });
  });
}
