import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/elrc_course.dart';
import '../models/elrc_recording.dart';
import 'elrc_client.dart';
import 'elrc_error.dart';
import 'elrc_screen_awake.dart';

typedef ElrcVideoFactory = VideoPlayerController Function(Uri uri, Map<String, String> headers);

class ElrcPlayback extends ChangeNotifier {
  ElrcPlayback({
    required this.course,
    required this.lesson,
    required this.client,
    ElrcVideoFactory? createVideo,
    ElrcScreenAwake? screenAwake,
    this.cleanupTimeout = const Duration(seconds: 2),
    this.operationTimeout = const Duration(seconds: 20),
  })  : _createVideo = createVideo ?? _networkVideo,
        _screenAwake = screenAwake ?? ElrcScreenAwake.shared {
    _generation = client.session.generation;
    client.session.addListener(_sessionChanged);
  }
  final ElrcCourse course;
  final ElrcRecordingLesson lesson;
  final ElrcClient client;
  final ElrcVideoFactory _createVideo;
  final ElrcScreenAwake _screenAwake;
  final Duration cleanupTimeout;
  final Duration operationTimeout;
  VideoPlayerController? _video;
  VideoPlayerController? get video => _video;
  ElrcRecordingSources? sources;
  ElrcRecordingSource? selected;
  ElrcException? error;
  bool loading = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _videoReady = false;
  // Native errors replace the whole VideoPlayerValue, including its position.
  // Keep the last usable state independently of a failed/retired decoder.
  Duration _resumePosition = Duration.zero;
  bool _resumePlaying = true;
  int _request = 0;
  int _control = 0;
  int _foregroundEpoch = 0;
  late int _generation;
  Future<void> _retired = Future.value();

  static VideoPlayerController _networkVideo(Uri uri, Map<String, String> headers) =>
      VideoPlayerController.networkUrl(
        uri,
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );

  bool _ownsRequest(int request) =>
      !_disposed && request == _request && client.session.generation == _generation;

  bool _current(int request) => _ownsRequest(request) && client.session.isConnected;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _stop() {
    final previous = _video;
    _video = null;
    _videoReady = false;
    _syncScreenAwake();
    previous?.removeListener(_videoChanged);
    if (previous != null) {
      unawaited(
        Future<void>.sync(previous.pause).timeout(cleanupTimeout).catchError((Object _) {}),
      );
      _retired = _retired.then((_) async {
        try {
          // Failed platform creation can leave video_player waiting forever.
          // The disposal continues if native creation eventually completes.
          await previous.dispose().timeout(cleanupTimeout);
        } catch (_) {
          /* Continue even if the retired decoder fails to dispose. */
        }
      });
    }
    return _retired;
  }

  bool get canControl =>
      !_disposed &&
      !loading &&
      error == null &&
      _videoReady &&
      _video?.value.isInitialized == true &&
      _video?.value.hasError == false;

  Future<void> load() => _load(preserveState: false);

  Future<void> retry() => _load(preserveState: true);

  Future<void> _load({required bool preserveState}) async {
    if (_disposed) return;
    if (preserveState) {
      _rememberVideo();
    } else {
      _resumePosition = Duration.zero;
      _resumePlaying = true;
      sources = null;
      selected = null;
    }
    final position = _resumePosition;
    final playing = _resumePlaying;
    final contentId = selected?.contentId;
    final request = ++_request;
    _generation = client.session.generation;
    loading = true;
    error = null;
    _changed();
    try {
      await _stop();
      if (!_current(request)) {
        await _fail(request, const ElrcException(ElrcErrorKind.staleSession));
        return;
      }
      final result = await client.getSources(course, lesson).timeout(operationTimeout);
      if (!_current(request)) return;
      sources = result;
      final source = result.sources.firstWhere(
        (source) => source.contentId == contentId,
        orElse: () => result.preferred,
      );
      await _open(source, request, position, playing);
    } on ElrcException catch (failure) {
      await _fail(request, failure);
    } catch (_) {
      await _fail(request, const ElrcException(ElrcErrorKind.playback));
    } finally {
      if (_ownsRequest(request)) {
        loading = false;
        _changed();
      }
    }
  }

  Future<void> select(ElrcRecordingSource source) async {
    if (sources?.sources.contains(source) != true || (selected == source && error == null)) return;
    _rememberVideo();
    final position = _resumePosition;
    final playing = _resumePlaying;
    final request = ++_request;
    loading = true;
    error = null;
    _changed();
    try {
      await _stop();
      if (_current(request)) await _open(source, request, position, playing);
    } finally {
      if (_ownsRequest(request)) {
        loading = false;
        _changed();
      }
    }
  }

  Future<void> _open(ElrcRecordingSource source, int request, Duration position, bool play) async {
    try {
      if (!_current(request)) return;
      selected = source;
      final headers = await client.playbackHeaders(course, source.uri).timeout(operationTimeout);
      if (!_current(request)) return;
      final controller = _createVideo(source.uri, headers);
      _video = controller;
      controller.addListener(_videoChanged);
      await controller.initialize().timeout(operationTimeout);
      if (!_owns(controller, request)) return;
      final duration = controller.value.duration;
      await controller.seekTo(position < duration ? position : duration).timeout(operationTimeout);
      if (!_owns(controller, request)) return;
      // video_player.play() restarts at zero when positioned at the end.
      if (play && _resumePlaying && _foreground && position < duration) {
        final foregroundEpoch = _foregroundEpoch;
        await controller.play().timeout(operationTimeout);
        if (_owns(controller, request) && foregroundEpoch != _foregroundEpoch) {
          await controller.pause().timeout(operationTimeout);
        }
      }
      if (!_owns(controller, request)) return;
      // Initialization/seek notifications must not replace the saved progress
      // until this camera has actually recovered successfully.
      _videoReady = true;
      _rememberVideo();
      _syncScreenAwake();
    } on ElrcException catch (failure) {
      await _fail(request, failure);
    } catch (_) {
      await _fail(request, const ElrcException(ElrcErrorKind.playback));
    }
  }

  Future<void> _fail(int request, ElrcException failure) async {
    if (!_ownsRequest(request)) return;
    _rememberVideo();
    error = failure;
    loading = false;
    final stopping = _stop();
    _changed();
    await stopping;
  }

  bool _owns(VideoPlayerController controller, int request) =>
      _current(request) && identical(_video, controller) && !controller.value.hasError;

  void _rememberVideo() {
    final value = _video?.value;
    if (!_videoReady || value == null || !value.isInitialized || value.hasError) return;
    _resumePosition = value.position;
    _resumePlaying = _foreground && value.isPlaying;
  }

  void _videoChanged() {
    if (_video?.value.hasError == true) {
      unawaited(_fail(_request, const ElrcException(ElrcErrorKind.playback)));
    } else {
      _rememberVideo();
      _syncScreenAwake();
    }
  }

  void _syncScreenAwake() {
    final value = _video?.value;
    _screenAwake.setActive(
      this,
      !_disposed &&
          _foreground &&
          _videoReady &&
          error == null &&
          value != null &&
          value.isPlaying &&
          !value.hasError &&
          !value.isCompleted &&
          value.position < value.duration,
    );
  }

  Future<void> togglePlay() async {
    final controller = _video;
    if (controller == null || !canControl || !_foreground) return;
    final request = _request;
    final control = ++_control;
    final foregroundEpoch = _foregroundEpoch;
    try {
      if (controller.value.isPlaying) {
        await controller.pause().timeout(operationTimeout);
      } else {
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero).timeout(operationTimeout);
        }
        if (!_owns(controller, request) ||
            control != _control ||
            foregroundEpoch != _foregroundEpoch ||
            !_foreground) {
          return;
        }
        await controller.play().timeout(operationTimeout);
        // A platform play request can itself finish after backgrounding.
        if (_owns(controller, request) &&
            control == _control &&
            foregroundEpoch != _foregroundEpoch) {
          await controller.pause().timeout(operationTimeout);
        }
      }
    } catch (_) {
      if (!_owns(controller, request) || control != _control) return;
      await _fail(request, const ElrcException(ElrcErrorKind.playback));
    }
  }

  Future<void> seek(Duration position) async {
    final controller = _video;
    if (controller == null || !canControl || !_foreground) return;
    final request = _request;
    final bounded = position < Duration.zero
        ? Duration.zero
        : position > controller.value.duration
            ? controller.value.duration
            : position;
    try {
      await controller.seekTo(bounded).timeout(operationTimeout);
    } catch (_) {
      if (!_owns(controller, request)) return;
      await _fail(request, const ElrcException(ElrcErrorKind.playback));
    }
  }

  void setForeground(bool active) {
    _foreground = active;
    if (!active) {
      _foregroundEpoch++;
      _resumePlaying = false;
      final controller = _video;
      if (controller != null) unawaited(controller.pause().catchError((Object _) {}));
    }
    _syncScreenAwake();
  }

  void _sessionChanged() {
    if (client.session.generation == _generation) return;
    _request++;
    sources = null;
    selected = null;
    loading = false;
    error = const ElrcException(ElrcErrorKind.staleSession);
    unawaited(_stop());
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    client.session.removeListener(_sessionChanged);
    sources = null;
    selected = null;
    unawaited(_stop());
    super.dispose();
  }
}
