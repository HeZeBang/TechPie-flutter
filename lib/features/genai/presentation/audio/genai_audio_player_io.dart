import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'genai_audio_player.dart';

GenAiAudioPlayer createGenAiAudioPlayer() => GenAiAudioPlayerIo();

final class GenAiAudioPlayerIo implements GenAiAudioPlayer {
  bool _playing = false;
  void Function()? _onFinished;
  File? _tempFile;

  @override
  bool get isPlaying => _playing;

  @override
  set onFinished(void Function()? callback) {
    _onFinished = callback;
  }

  @override
  Future<void> playWav(List<int> bytes) async {
    await stop();
    _playing = true;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/genai_tts_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await file.writeAsBytes(bytes);
      _tempFile = file;
    } catch (_) {}
    // Simulated short completion or system open
    _playing = false;
    _onFinished?.call();
  }

  @override
  Future<void> stop() async {
    _playing = false;
    try {
      _tempFile?.deleteSync();
    } catch (_) {}
    _tempFile = null;
  }

  @override
  void dispose() {
    unawaited(stop());
  }
}
