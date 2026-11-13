import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'genai_audio_recorder.dart';
import 'genai_audio_recorder_stub.dart';
import 'wav_encoder.dart';

GenAiAudioRecorder createGenAiAudioRecorder() =>
    Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux
    ? _NativeRecorder()
    : GenAiAudioRecorderStub();

final class _NativeRecorder implements GenAiAudioRecorder {
  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    numChannels: 1,
    sampleRate: 16000,
  );

  AudioRecorder? _recorder;
  Future<BytesBuilder>? _capture;
  int _generation = 0;

  @override
  bool get isSupported => true;
  @override
  bool get isRecording => _capture != null;
  @override
  Future<bool> hasPermission() => (_recorder ??= AudioRecorder()).hasPermission();

  @override
  Future<void> start() async {
    final generation = ++_generation;
    final recorder = _recorder ??= AudioRecorder();
    final stream = await recorder.startStream(_config);
    if (generation != _generation) return;
    _capture = stream.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (bytes, chunk) => bytes..add(chunk),
    );
  }

  @override
  Future<Uint8List?> stop() async {
    final capture = _capture;
    if (capture == null) return null;
    _capture = null;
    final generation = _generation;
    await _recorder!.stop();
    final bytes = (await capture).takeBytes();
    if (generation != _generation || bytes.isEmpty) return null;
    return WavEncoder.encodeMonoPcm16(bytes, sampleRate: _config.sampleRate);
  }

  @override
  Future<void> cancel() async {
    _generation++;
    _capture = null;
    await _recorder?.cancel();
  }

  @override
  void dispose() {
    _generation++;
    _capture = null;
    final recorder = _recorder;
    _recorder = null;
    unawaited(recorder?.dispose());
  }
}
