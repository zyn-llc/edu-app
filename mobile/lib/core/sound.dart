import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';

/// Ovoz effektlari.
///
/// Nega ikkita player: to'g'ri/xato ovozi ketma-ket savollarda bir-birini
/// bo'lishi kerak (`_fx`), lekin "mashq tugadi" fanfari alohida kanalda
/// yangrasin (`_ui`) — aks holda oxirgi javob ovozi uni kesib tashlaydi.
///
/// Har bir chaqiruv `soundEnabledProvider` ni tekshiradi: sozlamada o'chirilgan
/// bo'lsa hech narsa yangramaydi.
///
/// Xatolar yutiladi. Ovoz fayli topilmasa yoki qurilma band bo'lsa ham quiz
/// to'xtamasligi kerak — ovoz bezak, mahsulot emas.
class SoundService {
  final Ref ref;
  final AudioPlayer _fx = AudioPlayer();
  final AudioPlayer _ui = AudioPlayer();

  SoundService(this.ref);

  /// Webda brauzer birinchi foydalanuvchi harakatigacha audio chalishga ruxsat
  /// bermaydi (`NotAllowedError`). Shu sababli `AudioContext` ni ilk `tap()` da
  /// "ochamiz" — undan keyingi barcha ovozlar normal chaladi. Androidda bu
  /// bayroq hech narsani o'zgartirmaydi.
  bool _unlocked = false;

  Future<void> _play(AudioPlayer player, String asset,
      {double volume = 1.0}) async {
    if (!ref.read(soundEnabledProvider)) return;
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.play(AssetSource('sounds/$asset'));
      _unlocked = true;
    } catch (_) {
      // ovoz muvaffaqiyatsizligi hech qachon quizga ta'sir qilmasin
    }
  }

  /// To'g'ri javob — ko'tariluvchi ikki nota.
  void correct() => _play(_fx, 'correct.wav');

  /// Xato javob — pastga tushuvchi yumshoq ohang.
  /// Ataylab o'tkir emas: o'quvchini jazolayotgandek eshitilmasligi kerak.
  void wrong() => _play(_fx, 'wrong.wav', volume: 0.75);

  /// Mashq tugadi — uch notali kichik fanfar.
  ///
  /// `_ui` kanalida: oxirgi javob ovozi (`_fx`) uni kesib tashlamasin.
  void complete() => _play(_ui, 'complete.wav');

  /// Variant tanlandi — juda qisqa klik.
  ///
  /// Bu ilovada foydalanuvchi eng birinchi bosadigan ovozli element, shuning
  /// uchun webdagi autoplay qulfini aynan shu ochadi.
  void tap() => _play(_ui, 'tap.wav', volume: 0.4);

  /// Web autoplay qulfi ochilganmi. Diagnostika uchun.
  bool get isUnlocked => _unlocked;

  void dispose() {
    _fx.dispose();
    _ui.dispose();
  }
}

final soundServiceProvider = Provider<SoundService>((ref) {
  final s = SoundService(ref);
  ref.onDispose(s.dispose);
  return s;
});