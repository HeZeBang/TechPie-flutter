import 'genai_audio_player.dart';

GenAiAudioPlayer createGenAiAudioPlayer() => const _StubAudioPlayer();

final class _StubAudioPlayer implements GenAiAudioPlayer {
  const _StubAudioPlayer();

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
