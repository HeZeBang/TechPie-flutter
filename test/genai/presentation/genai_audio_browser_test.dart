@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_player_web.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_recorder_web.dart';
import 'package:techpie/features/genai/presentation/audio/wav_encoder.dart';
import 'package:web/web.dart' as web;

/// These tests need a DOM to drive real `HTMLAudioElement`, `MediaRecorder`,
/// and media tracks. Run them with:
/// `flutter test --no-pub --platform chrome test/genai/presentation/genai_audio_browser_test.dart`.
/// Under the VM they are skipped by `@TestOn`, so behavior that only exists in
/// the browser implementations is not covered by a plain `flutter test`.
void main() {
  group('GenAiAudioPlayerWeb', () {
    late _AudioHarness harness;
    late GenAiAudioPlayerWeb player;

    setUp(() {
      harness = _AudioHarness();
      player = GenAiAudioPlayerWeb();
    });

    tearDown(() {
      player.dispose();
      harness.dispose();
    });

    test('a replaced element cannot finish or stop the current playback', () async {
      var finished = 0;
      player.onFinished = () => finished++;

      await player.playWav(_wav());
      expect(harness.elements, hasLength(1));
      await player.playWav(_wav());
      expect(harness.elements, hasLength(2));
      expect(player.isPlaying, isTrue);

      // Stale ended/error events from the first element must not clean up the
      // second one.
      harness.elements[0].dispatchEvent(web.Event('ended'));
      harness.elements[0].dispatchEvent(web.Event('error'));
      expect(player.isPlaying, isTrue);
      expect(finished, 0);

      harness.elements[1].dispatchEvent(web.Event('ended'));
      expect(player.isPlaying, isFalse);
      expect(finished, 1);
    });

    test('a late play rejection from the replaced element is ignored', () async {
      harness.pendingPlays = 1;
      var finished = 0;
      player.onFinished = () => finished++;

      final replaced = player.playWav(_wav());
      await harness.waitForElements(1);

      await player.playWav(_wav());
      expect(harness.elements, hasLength(2));
      expect(player.isPlaying, isTrue);

      harness.rejectPlay(0);
      await replaced;
      expect(player.isPlaying, isTrue);
      expect(finished, 0);

      harness.elements[1].dispatchEvent(web.Event('ended'));
      expect(player.isPlaying, isFalse);
      expect(finished, 1);
    });
  });

  group('GenAiAudioRecorderWeb', () {
    late _RecorderHarness harness;
    late GenAiAudioRecorderWeb recorder;

    setUp(() {
      harness = _RecorderHarness();
      recorder = GenAiAudioRecorderWeb();
    });

    tearDown(() {
      recorder.dispose();
      harness.dispose();
    });

    test('releases the microphone when MediaRecorder construction fails', () async {
      harness.hideMediaRecorder();

      await expectLater(recorder.start(), throwsA(isA<Object>()));
      expect(recorder.isRecording, isFalse);
      expect(harness.streams, hasLength(1));
      _expectTracksEnded(harness.streams.single);
      expect(await recorder.stop(), isNull);

      await recorder.cancel();
    });

    test('releases the microphone when MediaRecorder.start fails', () async {
      harness.failStart();

      await expectLater(recorder.start(), throwsA(isA<Object>()));
      expect(recorder.isRecording, isFalse);
      expect(harness.streams, hasLength(1));
      _expectTracksEnded(harness.streams.single);
      expect(await recorder.stop(), isNull);

      await recorder.cancel();
    });
  });
}

Uint8List _wav() => WavEncoder.encodeFloat32(
      channels: [Float32List(80)],
      sampleRate: 8000,
    );

void _expectTracksEnded(web.MediaStream stream) {
  final tracks = stream.getTracks().toDart;
  expect(tracks, isNotEmpty);
  for (final track in tracks) {
    expect(track.readyState, 'ended');
  }
}

/// Replaces `document.createElement` so every audio element gets a controlled
/// `play()` promise, and lets stale-element events/rejections be simulated.
final class _AudioHarness {
  _AudioHarness() {
    _originalCreateElement = web.document.getProperty<JSFunction>('createElement'.toJS);
    web.document.setProperty('createElement'.toJS, _createElement.toJS);
  }

  late final JSFunction _originalCreateElement;
  final List<web.HTMLAudioElement> elements = [];
  final List<Completer<JSAny?>> _plays = [];
  final List<Completer<void>> _waiters = [];
  final List<int> _waitsFor = [];

  /// How many upcoming audio elements receive a pending `play()` promise.
  int pendingPlays = 0;

  JSAny? _createElement(JSAny? localName, [JSAny? options]) {
    final created = _originalCreateElement.callAsFunction(web.document, localName, options);
    if (localName.dartify() != 'audio') return created;

    final element = created as web.HTMLAudioElement;
    elements.add(element);
    final play = Completer<JSAny?>();
    if (pendingPlays > 0) {
      pendingPlays--;
    } else {
      play.complete();
    }
    _plays.add(play);
    element.setProperty('play'.toJS, (() => play.future.toJS).toJS);
    _completeWaiters();
    return created;
  }

  Future<void> waitForElements(int count) {
    if (elements.length >= count) return Future<void>.value();
    final waiter = Completer<void>();
    _waiters.add(waiter);
    _waitsFor.add(count);
    return waiter.future;
  }

  void _completeWaiters() {
    for (var i = _waiters.length - 1; i >= 0; i--) {
      if (elements.length < _waitsFor[i]) continue;
      final waiter = _waiters.removeAt(i);
      _waitsFor.removeAt(i);
      waiter.complete();
    }
  }

  void rejectPlay(int index) {
    final play = _plays[index];
    if (!play.isCompleted) {
      play.completeError(StateError('synthetic stale play rejection'));
    }
  }

  void dispose() {
    web.document.setProperty('createElement'.toJS, _originalCreateElement);
    for (final play in _plays) {
      if (!play.isCompleted) {
        play.completeError(StateError('synthetic test teardown'));
      }
    }
  }
}

/// Serves a live-audio `MediaStream` to `getUserMedia` and can make recorder
/// construction or `start()` throw, so microphone release can be observed.
final class _RecorderHarness {
  _RecorderHarness() {
    _devices = web.window.navigator.mediaDevices;
    _originalGetUserMedia = _devices.getProperty<JSAny?>('getUserMedia'.toJS);
    _devices.setProperty('getUserMedia'.toJS, _getUserMedia.toJS);
    _originalMediaRecorder = web.window.getProperty<JSAny?>('MediaRecorder'.toJS);
  }

  late final web.MediaDevices _devices;
  late final JSAny? _originalGetUserMedia;
  late final JSAny? _originalMediaRecorder;
  JSAny? _originalStart;
  final List<web.MediaStream> streams = [];
  final List<web.AudioContext> contexts = [];

  JSAny? _getUserMedia(JSAny? constraints) {
    final context = web.AudioContext();
    contexts.add(context);
    final destination = context.createMediaStreamDestination();
    final oscillator = context.createOscillator();
    oscillator.connect(destination);
    oscillator.start();
    final stream = destination.stream;
    streams.add(stream);
    return Future<web.MediaStream>.value(stream).toJS;
  }

  void hideMediaRecorder() {
    web.window.setProperty('MediaRecorder'.toJS, null);
  }

  void failStart() {
    final prototype = web.window
        .getProperty<JSObject>('MediaRecorder'.toJS)
        .getProperty<JSObject>('prototype'.toJS);
    _originalStart ??= prototype.getProperty<JSAny?>('start'.toJS);
    prototype.setProperty(
      'start'.toJS,
      ((JSAny? _) {
        throw StateError('synthetic start failure');
      } as void Function(JSAny?)).toJS,
    );
  }

  void dispose() {
    _devices.setProperty('getUserMedia'.toJS, _originalGetUserMedia);
    web.window.setProperty('MediaRecorder'.toJS, _originalMediaRecorder);
    final start = _originalStart;
    if (start != null) {
      web.window
          .getProperty<JSObject>('MediaRecorder'.toJS)
          .getProperty<JSObject>('prototype'.toJS)
          .setProperty('start'.toJS, start);
    }
    for (final context in contexts) {
      unawaited(context.close().toDart);
    }
  }
}
