import 'genai_audio_player.dart';

/// Native playback is unavailable until an audio plugin is wired.
GenAiAudioPlayer createGenAiAudioPlayer() => GenAiAudioPlayerIo();

final class GenAiAudioPlayerIo implements GenAiAudioPlayer {
  @override
  bool get isSupported => false;
  @override
  bool get isPlaying => false;
  @override
  set onFinished(void Function()? callback) {}
  @override
  Future<void> playWav(List<int> bytes) async =>
      throw UnsupportedError('Audio playback is unavailable on this platform.');
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}
