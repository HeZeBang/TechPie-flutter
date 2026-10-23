import 'dart:typed_data';

import 'genai_audio_recorder_stub.dart'
    if (dart.library.js_interop) 'genai_audio_recorder_web.dart'
    if (dart.library.io) 'genai_audio_recorder_io.dart';

abstract interface class GenAiAudioRecorder {
  factory GenAiAudioRecorder() => createGenAiAudioRecorder();

  bool get isSupported;

  Future<bool> hasPermission();
  Future<void> start();
  Future<Uint8List?> stop();
  Future<void> cancel();
  bool get isRecording;
  void dispose();
}
