/// IPA o'rniga — O'ZBEK LOTINIDA o'qiladigan talaffuz.
///
/// MUAMMO. Bank'da talaffuz IPA'da yozilgan: `rʲɪˈʂɛnʲɪjə`, `ˈʔapfaːt`.
/// Maktab o'quvchisi IPA'ni o'qiy olmaydi, ustiga-ustak `ʂ`, `ɐ`, `t͡ɕ`
/// kabi belgilar ko'p shriftda umuman chizilmaydi va ekranda quti
/// (`□`) bo'lib chiqadi. Ya'ni maydon foyda emas, zarar keltirardi.
///
/// YECHIM. Ikki xil yo'l, manbaga qarab:
///   * RUS TILI — so'zning O'ZI kirill alifbosida, uni o'zbek lotiniga
///     o'girish aniq va yo'qotishsiz: `решение` -> `reshéniye`.
///   * INGLIZ / NEMIS — so'z allaqachon lotin alifbosida, lekin yozilishi
///     talaffuzga teng emas. Shuning uchun IPA o'qiladigan harflarga
///     yaqinlashtiriladi: `/ˈeɪprʌl/` -> `éypril`.
///
/// URG'U. IPA'dagi `ˈ` belgisi urg'uli BO'G'INdan oldin turadi. O'sha
/// bo'g'inning birinchi unlisiga o'tkir belgi qo'yiladi (á é í ó ú).
/// Urg'u — o'quvchi uchun eng foydali bitta ma'lumot, ayniqsa rus tilida.
///
/// BU TAXMINIY VA SHUNDAY DEB KO'RSATILADI. Maqsad — fonetik aniqlik
/// emas, o'quvchi so'zni ovoz chiqarib ayta olishi. Aniq talaffuz uchun
/// tinglash tugmasi bor.
library;

const _cyrToLatin = <String, String>{
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'ye', 'ё': 'yo',
  'ж': 'j', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
  'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
  'ф': 'f', 'х': 'x', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
  'ъ': '', 'ы': 'i', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
};

/// IPA belgisi -> o'qiladigan lotin. Uzunroq belgilar OLDIN kelishi kerak,
/// aks holda `t͡ʃ` ning faqat `t` qismi almashadi.
const _ipaToLatin = <String, String>{
  't͡ʃ': 'ch', 't͡ɕ': 'ch', 'd͡ʒ': 'j', 'ʧ': 'ch', 'ʤ': 'j',
  'eɪ': 'ey', 'aɪ': 'ay', 'ɔɪ': 'oy', 'aʊ': 'au', 'oʊ': 'ou', 'əʊ': 'ou',
  'ɪə': 'ia', 'eə': 'ea', 'ʊə': 'ua',
  'iː': 'i', 'uː': 'u', 'ɑː': 'a', 'ɔː': 'o', 'ɜː': 'yo', 'aː': 'a',
  'eː': 'e', 'oː': 'o', 'øː': 'yo', 'yː': 'yu',
  'ʃ': 'sh', 'ʒ': 'j', 'ʂ': 'sh', 'ɕ': 'sh', 'ʐ': 'j',
  'θ': 's', 'ð': 'z', 'ŋ': 'ng', 'x': 'x', 'ç': 'x',
  'æ': 'a', 'ʌ': 'a', 'ɑ': 'a', 'ɐ': 'a', 'ɒ': 'o', 'ɔ': 'o',
  'ə': 'e', 'ɛ': 'e', 'ɪ': 'i', 'ɨ': 'i', 'ʊ': 'u', 'ʏ': 'yu',
  'y': 'yu', 'ø': 'yo', 'œ': 'yo', 'ɵ': 'o',
  'ɡ': 'g', 'ɫ': 'l', 'ɾ': 'r', 'ʁ': 'r', 'ʀ': 'r',
  'ʔ': '', 'ʲ': '', 'ˑ': '', 'ː': '', '͡': '', '̯': '', '̥': '', '̩': '',
  '/': '', '[': '', ']': '', '.': '',
};

const _vowels = 'aeiouáéíóú';
const _acute = <String, String>{
  'a': 'á', 'e': 'é', 'i': 'í', 'o': 'ó', 'u': 'ú',
};

/// IPA'dagi urg'u BO'G'IN raqami (0 dan). Topilmasa `null`.
///
/// Bo'g'in unlilar bo'yicha sanaladi: `ˈ` dan oldin nechta unli bo'lsa,
/// urg'u shuncha raqamli bo'g'inga tushadi.
int? stressedSyllable(String? ipa) {
  if (ipa == null) return null;
  final i = ipa.indexOf('ˈ');
  if (i < 0) return null;
  var count = 0;
  var prevWasVowel = false;
  for (final ch in ipa.substring(0, i).split('')) {
    final isVowel = _isIpaVowel(ch);
    if (isVowel && !prevWasVowel) count++;
    prevWasVowel = isVowel;
  }
  return count;
}

bool _isIpaVowel(String ch) =>
    'aeiouæʌɑɐɒɔəɛɪɨʊyøœɵ'.contains(ch.toLowerCase());

/// Lotin matnidagi `n`-chi bo'g'inning unlisiga urg'u qo'yish.
String _applyStress(String latin, int? syllable) {
  if (syllable == null) return latin;
  var seen = -1;
  var prevWasVowel = false;
  final out = StringBuffer();
  for (var i = 0; i < latin.length; i++) {
    final ch = latin[i];
    final isVowel = _vowels.contains(ch.toLowerCase());
    if (isVowel && !prevWasVowel) {
      seen++;
      if (seen == syllable) {
        out.write(_acute[ch.toLowerCase()] ?? ch);
        prevWasVowel = true;
        continue;
      }
    }
    prevWasVowel = isVowel;
    out.write(ch);
  }
  return out.toString();
}

const _cyrVowels = 'аеёиоуыэюя';

/// `е` KONTEKSTGA BOG'LIQ va bu yagona shunday harf.
///
/// So'z boshida, unlidan keyin yoki `ъ`/`ь` dan keyin u yotlashadi
/// ("ye"), undoshdan keyin esa oddiy "e" bo'ladi. Har doim "ye" deb
/// o'girilsa, `решение` -> `ryeshyeniye` bo'lib chiqadi — o'qib
/// bo'lmaydigan va noto'g'ri. `ё`, `ю`, `я` esa har doim yotlashgan,
/// shuning uchun ular jadvalda o'zgarmas.
bool _iotatedHere(String word, int i) {
  if (i == 0) return true;
  final prev = word[i - 1].toLowerCase();
  return _cyrVowels.contains(prev) || prev == 'ъ' || prev == 'ь';
}

String _transliterateCyrillic(String word) {
  final out = StringBuffer();
  for (var i = 0; i < word.length; i++) {
    final ch = word[i];
    final lower = ch.toLowerCase();
    String? mapped;
    if (lower == 'е') {
      mapped = _iotatedHere(word, i) ? 'ye' : 'e';
    } else {
      mapped = _cyrToLatin[lower];
    }
    if (mapped == null) {
      out.write(ch);
      continue;
    }
    out.write(ch == lower ? mapped : _capitalise(mapped));
  }
  return out.toString();
}

String _capitalise(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _respellIpa(String ipa) {
  var s = ipa.replaceAll('ˈ', '').replaceAll('ˌ', '');
  // Uzun belgilar oldin — aks holda `t͡ʃ` buziladi.
  final keys = _ipaToLatin.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    s = s.replaceAll(k, _ipaToLatin[k]!);
  }
  return s.trim();
}

bool _hasCyrillic(String s) =>
    s.runes.any((r) => r >= 0x0400 && r <= 0x04FF);

/// O'quvchiga ko'rsatiladigan talaffuz satri, yoki `null`.
///
/// `null` qaytsa — hech narsa ko'rsatilmaydi. Yomon taxminni chiqarishdan
/// ko'ra jim turish yaxshiroq.
String? readablePronunciation({
  required String lemma,
  String? ipa,
  required String language,
}) {
  final word = lemma.trim();
  if (word.isEmpty) return null;
  final stress = stressedSyllable(ipa);

  if (language == 'ru' || _hasCyrillic(word)) {
    final latin = _transliterateCyrillic(word);
    // Kirill bo'lmagan so'z uchun o'girish hech narsa bermaydi.
    if (latin.toLowerCase() == word.toLowerCase()) return null;
    return _applyStress(latin, stress);
  }

  // Ingliz/nemis: yozilishi talaffuzga teng emas, shuning uchun IPA'dan.
  if (ipa == null || ipa.trim().isEmpty) return null;
  final respelled = _respellIpa(ipa);
  if (respelled.isEmpty) return null;
  // O'girish so'zning o'ziga aynan teng bo'lsa, qo'shimcha ma'lumot yo'q.
  if (respelled.toLowerCase() == word.toLowerCase()) return null;
  return _applyStress(respelled, stress);
}
