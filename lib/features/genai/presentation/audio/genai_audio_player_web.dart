import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'genai_audio_player.dart';

GenAiAudioPlayer createGenAiAudioPlayer() => GenAiAudioPlayerWeb();

final class GenAiAudioPlayerWeb implements GenAiAudioPlayer {
  web.HTMLAudioElement? _element;
  String? _objectUrl;
  bool _playing = false;
  int _generation = 0;
  void Function(bool completed)? _onFinished;

  @override
  bool get isSupported => true;

  @override
  bool get isPlaying => _playing;

  @override
  set onFinished(void Function(bool completed)? callback) {
    _onFinished = callback;
  }

  @override
  Future<void> playWav(List<int> bytes) async {
    await stop();
    // A concurrent playWav can win the microtask race in stop(); take
    // ownership of its element instead of leaving two players live.
    final previous = _element;
    if (previous != null) {
      previous.pause();
      _cleanup();
    }
    final generation = ++_generation;
    final uint8List = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final blob = web.Blob([uint8List.toJS].toJS, web.BlobPropertyBag(type: 'audio/wav'));
    final url = web.URL.createObjectURL(blob);
    _objectUrl = url;
    final element = web.HTMLAudioElement()..src = url;
    _element = element;
    _playing = true;

    element.onended = ((web.Event _) {
      if (!_isCurrent(generation, element)) return;
      _cleanup();
      _onFinished?.call(true);
    }).toJS;

    element.onerror = ((web.Event _) {
      if (!_isCurrent(generation, element)) return;
      _cleanup();
      _onFinished?.call(false);
    }).toJS;

    try {
      await element.play().toDart;
    } catch (_) {
      if (!_isCurrent(generation, element)) return;
      _cleanup();
      rethrow;
    }
  }

  bool _isCurrent(int generation, web.HTMLAudioElement element) =>
      generation == _generation && identical(_element, element);

  void _cleanup() {
    _playing = false;
    final url = _objectUrl;
    if (url != null) {
      web.URL.revokeObjectURL(url);
      _objectUrl = null;
    }
    _element = null;
  }

  @override
  Future<void> stop() async {
    // Invalidate callbacks bound to the element being torn down so a late
    // ended/error/play rejection cannot clean up a newer element.
    _generation++;
    final element = _element;
    if (element != null) {
      element.pause();
      _cleanup();
    }
  }

  @override
  void dispose() {
    unawaited(stop());
  }
}
