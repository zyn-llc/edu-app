import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_settings.dart';

/// So'z talaffuzi — qurilmaning/brauzerning ovoz sintezatori orqali.
///
/// NEGA SINTEZATOR, YOZIB OLINGAN AUDIO EMAS. Bank'da audio BITTA
/// yozuvda ham yo'q (`LANGUAGE_BANKS.md`), 16 915 so'zni studiyada yozish
/// esa alohida loyiha. Sintezator — bugun mavjud bo'lgan yagona yo'l.
///
/// ENG MUHIM QOIDA: TIL UCHUN OVOZ YO'Q BO'LSA — JIM TURAMIZ.
/// Nemischa so'zni inglizcha ovoz bilan o'qitish — noto'g'ri talaffuzni
/// O'RGATISH demak, ya'ni jim turishdan YOMONROQ. Qurilmada mos ovoz
/// bo'lmasa, tugma umuman ko'rsatilmaydi va o'quvchi IPA transkripsiyasini
/// ko'radi (u 100 % ingliz yozuvlarida bor).
///
/// Brauzerda ovozlar ro'yxati kech yuklanadi va qurilmaga qarab farq
/// qiladi, shuning uchun qo'llab-quvvatlash bir marta tekshirilib, keshda
/// saqlanadi.
class PronounceService {
  PronounceService(this.ref);

  final Ref ref;
  final FlutterTts _tts = FlutterTts();

  bool _ready = false;
  final Map<String, bool> _supported = {};

  /// Modul tili -> BCP-47. Sintezatorlar to'liq kodni kutadi; "en" ba'zi
  /// platformalarda topilmaydi, "en-US" esa topiladi.
  static const _locales = {
    'en': 'en-US',
    'de': 'de-DE',
    'ru': 'ru-RU',
  };

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    try {
      // Boshqa ekranga o'tganda gap davom etmasligi kerak.
      await _tts.awaitSpeakCompletion(true);
      // Yot tildagi so'zni sekinroq aytish — bu talaffuz namunasi,
      // tabiiy nutq emas.
      await _tts.setSpeechRate(0.42);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      // Sintezator yo'q platformada ham ilova ishlashda davom etadi.
    }
  }

  /// Shu til uchun ovoz bormi. Javob keshlanadi.
  Future<bool> supports(String language) async {
    final locale = _locales[language];
    if (locale == null) return false;
    final cached = _supported[language];
    if (cached != null) return cached;

    await _init();
    bool ok = false;
    try {
      ok = (await _tts.isLanguageAvailable(locale)) == true;
    } catch (_) {
      ok = false;
    }
    _supported[language] = ok;
    return ok;
  }

  /// So'zni aytish. Ovoz yo'q bo'lsa — HECH NARSA qilmaydi (jim).
  Future<void> say(String text, String language) async {
    if (!ref.read(soundEnabledProvider)) return;
    final word = text.trim();
    if (word.isEmpty) return;
    if (!await supports(language)) return;

    try {
      await _tts.stop();
      await _tts.setLanguage(_locales[language]!);
      await _tts.speak(word);
    } catch (_) {
      // Ovoz chiqmasa ham ekran ishlashda davom etadi.
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

final pronounceServiceProvider = Provider<PronounceService>((ref) {
  final s = PronounceService(ref);
  ref.onDispose(s.stop);
  return s;
});

/// Shu til uchun talaffuz mavjudmi. `false` bo'lsa tugma KO'RSATILMAYDI.
final pronounceSupportedProvider =
    FutureProvider.family<bool, String>((ref, language) async {
  return ref.read(pronounceServiceProvider).supports(language);
});
