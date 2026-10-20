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
  void Function()? _onFinished;

  @override
  bool get isPlaying => _playing;

  @override
  set onFinished(void Function()? callback) {
    _onFinished = callback;
  }

  @override
  Future<void> playWav(List<int> bytes) async {
    await stop();
    final uint8List = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final blob = web.Blob(
      [uint8List.toJS].toJS,
      web.BlobPropertyBag(type: 'audio/wav'),
    );
    final url = web.URL.createObjectURL(blob);
    _objectUrl = url;
    final element = web.HTMLAudioElement()..src = url;
    _element = element;
    _playing = true;

    element.onended = ((web.Event _) {
      _cleanup();
      _onFinished?.call();
    }).toJS;

    element.onerror = ((web.Event _) {
      _cleanup();
      _onFinished?.call();
    }).toJS;

    try {
      await element.play().toDart;
    } catch (_) {
      _cleanup();
      _onFinished?.call();
    }
  }

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
