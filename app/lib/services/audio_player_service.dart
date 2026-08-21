// audio_player_service.dart — servicio centralizado para reproducir historias/pines.
// Fix: backend ahora devuelve audio_url absoluta; iOS necesita AVAudioSessionCategory.playback para sonar en silencio.

import 'package:audioplayers/audioplayers.dart';

class AudioPlayerService {
  AudioPlayerService._();
  static final AudioPlayerService instance = AudioPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
    _configured = true;
  }

  /// [audioUrl] debe ser URL absoluta (https://mercurio-9haf.onrender.com/uploads/...)
  Future<void> play(String audioUrl) async {
    await _ensureConfigured();
    await _player.stop();
    await _player.play(UrlSource(audioUrl));
  }

  Future<void> stop() => _player.stop();
  Future<void> pause() => _player.pause();
  Stream<PlayerState> get onStateChanged => _player.onPlayerStateChanged;
  void dispose() => _player.dispose();
}
