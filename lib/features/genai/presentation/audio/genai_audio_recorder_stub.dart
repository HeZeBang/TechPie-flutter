import 'dart:typed_data';

import 'genai_audio_recorder.dart';

GenAiAudioRecorder createGenAiAudioRecorder() => GenAiAudioRecorderStub();

final class GenAiAudioRecorderStub implements GenAiAudioRecorder {
  @override
  bool get isSupported => false;

  @override
  bool get isRecording => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<void> start() async {
    throw UnsupportedError(
      'Audio recording is not supported on this platform.',
    );
  }

  @override
  Future<Uint8List?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}
