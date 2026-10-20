import 'genai_audio_player.dart';

GenAiAudioPlayer createGenAiAudioPlayer() => const _StubAudioPlayer();

final class _StubAudioPlayer implements GenAiAudioPlayer {
  const _StubAudioPlayer();

  @override
  bool get isPlaying => false;

  @override
  set onFinished(void Function()? callback) {}

  @override
  Future<void> playWav(List<int> bytes) async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}
