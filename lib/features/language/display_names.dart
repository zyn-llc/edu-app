import '../../l10n/app_localizations.dart';

/// Bank'dagi TEXNIK kalitlarni odam o'qiydigan nomga aylantirish.
///
/// NEGA KERAK. Bank'da mavzu `science_abstract`, so'z turkumi `noun` deb
/// yotadi — bular ma'lumot kalitlari, sarlavha emas. Ular ekranga
/// to'g'ridan-to'g'ri chiqqanda o'quvchi ingliz tilidagi texnik yozuvni
/// ko'radi va ilova tugallanmagandek tuyuladi.
///
/// NEGA ARB EMAS. Kalitlar BANK'dan keladi va yangi kalit qo'shilishi
/// mumkin. ARB'da bo'lsa, har bir yangi kalit uchun tarjima fayli
/// o'zgarishi kerak bo'lardi va tarjimasi yo'q kalit `gen-l10n` ni
/// yiqitardi. Bu yerda esa noma'lum kalit CHIROYLI ko'rinishga tushadi
/// (`science_abstract` -> `Science abstract`) va ilova ishlashda davom
/// etadi.
///
/// So'z turkumi TILGA BOG'LIQ: nemis bank'ida `function`, ingliz bank'ida
/// `det`/`modal`, rus bank'ida `particle` bor. Bitta umumiy xarita
/// ularning bir qismini tashlab ketardi.

/// Mavzu kalitlari — uchala tilda ham AYNI 20 ta.
const _topicUz = <String, String>{
  'animals_plants': 'Hayvonlar va o’simliklar',
  'body_health': 'Tana va salomatlik',
  'city_places': 'Shahar va joylar',
  'clothes': 'Kiyim-kechak',
  'communication_media': 'Aloqa va media',
  'emotions_character': 'His-tuyg’u va xarakter',
  'family_people': 'Oila va odamlar',
  'food_drink': 'Ovqat va ichimlik',
  'function_word': 'Yordamchi so’zlar',
  'home_furniture': 'Uy va jihozlar',
  'money_shopping': 'Pul va xarid',
  'school_study': 'Maktab va ta’lim',
  'science_abstract': 'Fan va mavhum tushunchalar',
  'society_state': 'Jamiyat va davlat',
  'sport_hobbies': 'Sport va mashg’ulotlar',
  'technology_internet': 'Texnologiya va internet',
  'time_calendar': 'Vaqt va taqvim',
  'transport_travel': 'Transport va sayohat',
  'weather_nature': 'Ob-havo va tabiat',
  'work_professions': 'Kasb va mehnat',
};

const _topicRu = <String, String>{
  'animals_plants': 'Животные и растения',
  'body_health': 'Тело и здоровье',
  'city_places': 'Город и места',
  'clothes': 'Одежда',
  'communication_media': 'Связь и медиа',
  'emotions_character': 'Эмоции и характер',
  'family_people': 'Семья и люди',
  'food_drink': 'Еда и напитки',
  'function_word': 'Служебные слова',
  'home_furniture': 'Дом и мебель',
  'money_shopping': 'Деньги и покупки',
  'school_study': 'Школа и учёба',
  'science_abstract': 'Наука и отвлечённые понятия',
  'society_state': 'Общество и государство',
  'sport_hobbies': 'Спорт и увлечения',
  'technology_internet': 'Технологии и интернет',
  'time_calendar': 'Время и календарь',
  'transport_travel': 'Транспорт и путешествия',
  'weather_nature': 'Погода и природа',
  'work_professions': 'Профессии и труд',
};

/// Uchala tilda uchraydigan umumiy so'z turkumlari.
const _posUzCommon = <String, String>{
  'noun': 'ot',
  'verb': 'fe’l',
  'adj': 'sifat',
  'adjective': 'sifat',
  'adv': 'ravish',
  'adverb': 'ravish',
  'pron': 'olmosh',
  'pronoun': 'olmosh',
  'conj': 'bog’lovchi',
  'conjunction': 'bog’lovchi',
  'num': 'son',
  'numeral': 'son',
  'particle': 'yuklama',
  'interj': 'undov',
  'interjection': 'undov',
};

/// Tilga xos turkumlar. `prep` ataylab har xil: rus tilida bu an'anaviy
/// "predlog", ingliz tilida esa darsliklarda "prepozitsiya" deb yuritiladi.
const _posUzByLanguage = <String, Map<String, String>>{
  'ru': {
    'prep': 'predlog',
    'preposition': 'predlog',
  },
  'en': {
    'prep': 'prepozitsiya',
    'preposition': 'prepozitsiya',
    'det': 'aniqlovchi',
    'modal': 'modal fe’l',
    'exclam': 'undov',
    'abbr': 'qisqartma',
  },
  'de': {
    'prep': 'prepozitsiya',
    'function': 'yordamchi so’z',
    'phrase': 'ibora',
    'other': 'boshqa',
  },
};

const _posRuCommon = <String, String>{
  'noun': 'существительное',
  'verb': 'глагол',
  'adj': 'прилагательное',
  'adjective': 'прилагательное',
  'adv': 'наречие',
  'adverb': 'наречие',
  'pron': 'местоимение',
  'pronoun': 'местоимение',
  'conj': 'союз',
  'conjunction': 'союз',
  'num': 'числительное',
  'numeral': 'числительное',
  'particle': 'частица',
  'interj': 'междометие',
  'interjection': 'междометие',
  'prep': 'предлог',
  'preposition': 'предлог',
  'det': 'артикль',
  'modal': 'модальный глагол',
  'exclam': 'междометие',
  'abbr': 'сокращение',
  'function': 'служебное слово',
  'phrase': 'выражение',
  'other': 'другое',
};

/// O'QISH matnlarining mavzusi — kalit emas, RUSCHA MATN
/// ("город и транспорт"). Lug'at mavzularidan alohida ro'yxat, chunki
/// bular boshqa manbadan keladi va kalit shakliga ega emas.
///
/// Interfeys o'zbekcha bo'lgani uchun ular ham o'zbekchaga o'giriladi.
/// Tarjimasi topilmasa, ASLI ko'rsatiladi: ruscha sarlavha ham xom
/// kalitdan ko'ra tushunarliroq va yolg'on emas.
const _readingTopicUz = <String, String>{
  'город и транспорт': 'Shahar va transport',
  'еда и покупки': 'Ovqat va xarid',
  'интернет и техника': 'Internet va texnika',
  'книги и кино': 'Kitob va kino',
  'общество': 'Jamiyat',
  'погода и времена года': 'Ob-havo va fasllar',
  'природа и животные': 'Tabiat va hayvonlar',
  'путешествия': 'Sayohat',
  'работа и профессии': 'Ish va kasblar',
  'семья и дом': 'Oila va uy',
  'спорт и здоровье': 'Sport va salomatlik',
  'традиции и праздники': 'An’ana va bayramlar',
  'школа и учёба': 'Maktab va ta’lim',
};


/// Noma'lum kalitni hech bo'lmaganda O'QILADIGAN qilish:
/// `some_new_key` -> `Some new key`. Xom kalit ekranga CHIQMAYDI.
String _humanise(String key) {
  final words = key.replaceAll('_', ' ').trim();
  if (words.isEmpty) return '';
  return words[0].toUpperCase() + words.substring(1);
}

class DisplayNames {
  DisplayNames._();

  /// Mavzu kalitining ko'rinadigan nomi.
  static String topic(String? key, String uiLang) {
    if (key == null || key.isEmpty) return '';
    final map = uiLang == 'ru' ? _topicRu : _topicUz;
    return map[key] ?? _humanise(key);
  }

  /// So'z turkumi. `language` — O'RGANILAYOTGAN til (en/de/ru), chunki
  /// kalitlar shunga qarab farq qiladi.
  static String pos(String? key, String language, String uiLang) {
    if (key == null || key.isEmpty) return '';
    final k = key.toLowerCase();
    if (uiLang == 'ru') return _posRuCommon[k] ?? _humanise(k);
    return _posUzByLanguage[language]?[k] ?? _posUzCommon[k] ?? _humanise(k);
  }

  /// O'qish matnining mavzusi.
  ///
  /// `uiLang == 'ru'` bo'lsa ASLI qaytadi — u allaqachon ruscha va
  /// o'zbekchadan o'girib qaytarish ma'nosiz bo'lardi.
  static String readingTopic(String? raw, String uiLang) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return '';
    if (uiLang == 'ru') return t;
    return _readingTopicUz[t.toLowerCase()] ?? t;
  }

  /// Tilning nomi — l10n'dan, chunki bu uchta qiymat o'zgarmaydi.
  static String language(String code, L10n l) => switch (code) {
        'en' => l.langEnglish,
        'ru' => l.langRussian,
        'de' => l.langGerman,
        _ => code.toUpperCase(),
      };

  /// Testlar va hisobot uchun: qaysi kalitlar tarjima qilingan.
  static Iterable<String> get knownTopicKeys => _topicUz.keys;
  static Iterable<String> get knownReadingTopics =>
      _readingTopicUz.keys;
  static Iterable<String> get knownPosKeys => _posUzCommon.keys;
}
