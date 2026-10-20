import 'genai_audio_player_stub.dart'
    if (dart.library.js_interop) 'genai_audio_player_web.dart'
    if (dart.library.io) 'genai_audio_player_io.dart';

abstract interface class GenAiAudioPlayer {
  factory GenAiAudioPlayer() => createGenAiAudioPlayer();

  Future<void> playWav(List<int> bytes);
  Future<void> stop();
  bool get isPlaying;
  set onFinished(void Function()? callback);
  void dispose();
}
