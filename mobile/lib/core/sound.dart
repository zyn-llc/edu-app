import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';

class SoundService {
  final Ref ref;
  final AudioPlayer _fx = AudioPlayer();
  final AudioPlayer _ui = AudioPlayer();

  SoundService(this.ref);

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
    }
  }

  void correct() => _play(_fx, 'correct.wav');

  void wrong() => _play(_fx, 'wrong.wav', volume: 0.75);

  
  void complete() => _play(_ui, 'complete.wav');


  void tap() => _play(_ui, 'tap.wav', volume: 0.4);

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
