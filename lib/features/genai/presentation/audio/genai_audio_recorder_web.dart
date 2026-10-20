import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'genai_audio_recorder.dart';
import 'wav_encoder.dart';

GenAiAudioRecorder createGenAiAudioRecorder() => GenAiAudioRecorderWeb();

final class GenAiAudioRecorderWeb implements GenAiAudioRecorder {
  web.MediaStream? _mediaStream;
  web.MediaRecorder? _mediaRecorder;
  final List<web.Blob> _chunks = [];
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() async {
    try {
      final _ = web.window.navigator.mediaDevices;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start() async {
    await cancel();
    final nav = web.window.navigator;
    final stream = await nav.mediaDevices
        .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
        .toDart;
    _mediaStream = stream;
    _chunks.clear();

    final recorder = web.MediaRecorder(stream);
    recorder.ondataavailable = ((web.BlobEvent e) {
      if (e.data.size > 0) {
        _chunks.add(e.data);
      }
    }).toJS;

    _mediaRecorder = recorder;
    _recording = true;
    recorder.start();
  }

  @override
  Future<Uint8List?> stop() async {
    final recorder = _mediaRecorder;
    if (recorder == null || !_recording) {
      _recording = false;
      return null;
    }

    _recording = false;
    final stopCompleter = Completer<void>();
    recorder.onstop = ((web.Event _) {
      if (!stopCompleter.isCompleted) {
        stopCompleter.complete();
      }
    }).toJS;

    recorder.stop();
    await stopCompleter.future;

    _stopMediaStream();
    _mediaRecorder = null;

    if (_chunks.isEmpty) return null;

    final blob = web.Blob(_chunks.toJS);
    _chunks.clear();

    final arrayBuffer = await blob.arrayBuffer().toDart;
    final audioCtx = web.AudioContext();
    try {
      final audioBuffer = await audioCtx.decodeAudioData(arrayBuffer).toDart;
      final numChannels = audioBuffer.numberOfChannels;
      final sampleRate = audioBuffer.sampleRate.round();
      final channels = <Float32List>[];
      for (var ch = 0; ch < numChannels; ch++) {
        channels.add(audioBuffer.getChannelData(ch).toDart);
      }
      return WavEncoder.encodeFloat32(
        channels: channels,
        sampleRate: sampleRate,
      );
    } catch (_) {
      return null;
    } finally {
      unawaited(audioCtx.close().toDart);
    }
  }

  void _stopMediaStream() {
    final stream = _mediaStream;
    if (stream != null) {
      final tracks = stream.getTracks().toDart;
      for (final track in tracks) {
        track.stop();
      }
      _mediaStream = null;
    }
  }

  @override
  Future<void> cancel() async {
    _recording = false;
    final recorder = _mediaRecorder;
    if (recorder != null) {
      try {
        recorder.stop();
      } catch (_) {}
      _mediaRecorder = null;
    }
    _stopMediaStream();
    _chunks.clear();
  }

  @override
  void dispose() {
    unawaited(cancel());
  }
}
