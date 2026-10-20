import 'dart:typed_data';

import 'genai_audio_recorder.dart';

GenAiAudioRecorder createGenAiAudioRecorder() => GenAiAudioRecorderIO();

final class GenAiAudioRecorderIO implements GenAiAudioRecorder {
  GenAiAudioRecorderIO({this.simulatedAudioBytes});

  final Uint8List? simulatedAudioBytes;
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {
    _recording = true;
  }

  @override
  Future<Uint8List?> stop() async {
    if (!_recording) return null;
    _recording = false;
    return simulatedAudioBytes;
  }

  @override
  Future<void> cancel() async {
    _recording = false;
  }

  @override
  void dispose() {
    _recording = false;
  }
}
