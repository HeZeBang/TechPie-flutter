import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'genai_audio_player.dart';
import 'genai_audio_player_stub.dart' as stub;

GenAiAudioPlayer createGenAiAudioPlayer() =>
    Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux
    ? _NativePlayer()
    : stub.createGenAiAudioPlayer();

final class _NativePlayer implements GenAiAudioPlayer {
  AudioPlayer? _player;
  Directory? _directory;
  int _generation = 0;

  @override
  void Function(bool completed)? onFinished;
  @override
  bool get isSupported => true;
  @override
  bool get isPlaying => _player != null;

  @override
  Future<void> playWav(List<int> bytes) async {
    final generation = ++_generation;
    await _release();
    if (generation != _generation) return;
    final directory = await Directory.systemTemp.createTemp('techpie-speech-');
    var handedToPlayer = false;
    try {
      final file = File('${directory.path}/reply.wav');
      await file.writeAsBytes(bytes);
      if (generation != _generation) return;
      _directory = directory;
      handedToPlayer = true;
      final player = _player = AudioPlayer();
      void finish(bool completed) {
        if (generation != _generation) return;
        unawaited(stop());
        onFinished?.call(completed);
      }

      player.onPlayerComplete.listen((_) => finish(true), onError: (Object _) => finish(false));
      await player.play(DeviceFileSource(file.path, mimeType: 'audio/wav'));
    } catch (_) {
      if (generation == _generation) await stop();
      rethrow;
    } finally {
      if (!handedToPlayer) await directory.delete(recursive: true);
    }
  }

  Future<void> _release() async {
    final player = _player;
    final directory = _directory;
    _player = null;
    _directory = null;
    try {
      await player?.dispose();
    } finally {
      if (directory != null) await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> stop() {
    _generation++;
    return _release();
  }

  @override
  void dispose() => unawaited(stop());
}
