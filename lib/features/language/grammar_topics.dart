/// Grammatika mavzularining O'ZBEKCHA nomi.
///
/// MUAMMO. Bank'da mavzu nomi ingliz tilida: "Present simple — affirmative",
/// "Adverbs of frequency + position". O'zbek maktab o'quvchisi uchun bu
/// ro'yxat begona tilda yozilgan sarlavhalar to'plami.
///
/// NEGA IKKALASI HAM KO'RSATILADI. O'zbekcha nom — asosiy sarlavha,
/// inglizcha nom — ostidagi kichik kulrang satr. Inglizchasi O'CHIRILMAYDI:
/// darslikda, repetitor bilan va imtihonda aynan o'sha atama uchraydi, va
/// o'quvchi ikkisini bog'lay olishi kerak.
///
/// QAMROV — TO'LIQ EMAS VA BU ATAYLAB. Uchala bank'da jami 468 ta turli
/// mavzu bor (ingliz 129, nemis 99, rus 240). Bu yerda ingliz A1 va A2
/// to'liq o'girilgan — o'quvchilarning aksariyati shu yerdan boshlaydi.
/// Qolganlari uchun INGLIZCHA nom asosiy sarlavha bo'lib qoladi: mashina
/// tarjimasini o'ylab topishdan ko'ra, asl atamani ko'rsatish halolroq.
/// Yangi tarjimalar shu jadvalga qo'shiladi, kod o'zgarmaydi.
library;

const _uz = <String, String>{
  // ---- ingliz A1 ---------------------------------------------------------
  'Adjectives + very': 'Sifatlar + very',
  'Adverbs of frequency + position': 'Ravishlar: chastota va o’rni',
  'Basic conjunctions': 'Bog’lovchilar',
  'Cardinal & ordinal numbers': 'Sanoq va tartib sonlar',
  'Common irregular verbs': 'Noto’g’ri fe’llar',
  'Countable vs uncountable (basic)': 'Sanaladigan va sanalmaydigan otlar',
  'Imperative': 'Buyruq mayli',
  "Let's": '“Let’s” — taklif qilish',
  'Object pronouns': 'To’ldiruvchi olmoshlar',
  "Possessive 's": 'Qaratqich: ’s',
  'Possessive adjectives': 'Egalik sifatlari',
  'Prepositions of place': 'O’rin predloglari',
  'Prepositions of time': 'Payt predloglari',
  'Present continuous': 'Hozirgi davomiy zamon',
  'Present simple vs continuous (basic)':
      'Oddiy va davomiy hozirgi zamon farqi',
  'Present simple — affirmative': 'Oddiy hozirgi zamon — tasdiq',
  'Present simple — do / does': 'Oddiy hozirgi zamon — do / does',
  'Regular past -ed': 'O’tgan zamon: -ed qo’shimchasi',
  'Singular / plural nouns': 'Birlik va ko’plik otlar',
  'Subject pronouns': 'Ega olmoshlari',
  'Wh-questions': 'So’roq so’zlari bilan savollar',
  'Word order SVO; adjective before noun':
      'Gap tartibi va sifatning o’rni',
  'a / an': 'a / an artikllari',
  'a vs the (basic)': 'a va the farqi',
  'be going to (plans)': '“be going to” — reja',
  'be — past': '“be” fe’li — o’tgan zamon',
  'be — present': '“be” fe’li — hozirgi zamon',
  "can / can't (ability, permission)": 'can / can’t — qobiliyat va ruxsat',
  "did / didn't": 'did / didn’t',
  'have got / has got': 'have got / has got',
  'like / love / hate + -ing': 'like / love / hate + -ing',
  'there is / there are': 'there is / there are',
  'this / that / these / those': 'this / that / these / those',
  'want to / would like': 'want to / would like',

  // ---- ingliz A2 ---------------------------------------------------------
  '-ed / -ing adjectives': '-ed va -ing sifatlari',
  'Adverbs of manner; adjective vs adverb':
      'Holat ravishlari: sifat va ravish farqi',
  'Articles: zero article vs the': 'Artiklsiz shakl va the',
  'Common phrasal verbs': 'Ko’p ishlatiladigan frazali fe’llar',
  'Comparatives': 'Qiyosiy daraja',
  'Defining relative clauses': 'Aniqlovchi ergash gaplar',
  'First conditional': 'Birinchi shart gap',
  'Indefinite pronouns': 'Noaniq olmoshlar',
  'Irregular comparison': 'Noto’g’ri qiyoslash shakllari',
  'Linkers: so, because, although, then':
      'Bog’lovchilar: so, because, although, then',
  'Past continuous': 'O’tgan davomiy zamon',
  'Past simple vs past continuous':
      'Oddiy va davomiy o’tgan zamon farqi',
  'Possessive pronouns, whose': 'Egalik olmoshlari va whose',
  'Prepositions of movement': 'Harakat predloglari',
  'Present continuous for arrangements':
      'Kelishilgan reja uchun hozirgi davomiy zamon',
  'Present perfect + for / since': 'Present perfect + for / since',
  'Present perfect vs past simple (basic)':
      'Present perfect va oddiy o’tgan zamon farqi',
  'Present perfect — experience': 'Present perfect — tajriba',
  'Present perfect — just / already / yet':
      'Present perfect — just / already / yet',
  'Reflexive pronouns': 'O’zlik olmoshlari',
  'Requests & permission': 'Iltimos va ruxsat so’rash',
  'Subject vs object questions': 'Egaga va to’ldiruvchiga savol',
  'Superlatives': 'Orttirma daraja',
  'Zero conditional': 'Nol shart gap',
  'as … as / not as … as': 'as … as / not as … as',
  'could (past ability)': 'could — o’tmishdagi qobiliyat',
  'could / may / might (possibility)': 'could / may / might — ehtimol',
  'much / many / a lot of / a few / a little':
      'much / many / a lot of / a few / a little',
  'must / have to': 'must / have to',
  "mustn't vs don't have to": 'mustn’t va don’t have to farqi',
  "should / shouldn't (advice)": 'should / shouldn’t — maslahat',
  'some / any / no': 'some / any / no',
  'too / enough': 'too / enough',
  'used to (past habits)': 'used to — o’tmishdagi odat',
  'verb + to-infinitive / -ing (basic)': 'Fe’l + to-infinitive / -ing',
  'will vs going to': 'will va going to farqi',
  'will — predictions, offers, instant decisions':
      'will — taxmin, taklif, shu ondagi qaror',
};

class GrammarTopic {
  /// Asosiy sarlavha — o'zbekcha bo'lsa o'zbekcha, bo'lmasa aslining o'zi.
  final String title;

  /// Ostidagi kichik satr — asl atama. Sarlavha allaqachon asl bo'lsa `null`.
  final String? subtitle;

  const GrammarTopic(this.title, this.subtitle);

  /// Tarjima qilinganmi — hisobot va test uchun.
  bool get translated => subtitle != null;
}

class GrammarTopics {
  GrammarTopics._();

  static GrammarTopic of(String raw) {
    final uz = _uz[raw.trim()];
    return uz == null ? GrammarTopic(raw, null) : GrammarTopic(uz, raw);
  }

  static int get translatedCount => _uz.length;
  static Iterable<String> get translatedKeys => _uz.keys;
}
