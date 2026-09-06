import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/elrc_course.dart';
import '../models/elrc_recording.dart';
import 'elrc_client.dart';
import 'elrc_error.dart';

typedef ElrcVideoFactory = VideoPlayerController Function(Uri uri, Map<String, String> headers);

class ElrcPlayback extends ChangeNotifier {
  ElrcPlayback({
    required this.course,
    required this.lesson,
    required this.client,
    ElrcVideoFactory? createVideo,
    this.cleanupTimeout = const Duration(seconds: 2),
  }) : _createVideo = createVideo ?? _networkVideo {
    _generation = client.session.generation;
    client.session.addListener(_sessionChanged);
  }
  final ElrcCourse course;
  final ElrcRecordingLesson lesson;
  final ElrcClient client;
  final ElrcVideoFactory _createVideo;
  final Duration cleanupTimeout;
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
  late int _generation;
  Future<void> _retired = Future.value();

  static VideoPlayerController _networkVideo(Uri uri, Map<String, String> headers) =>
      VideoPlayerController.networkUrl(
        uri,
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false, allowBackgroundPlayback: true),
      );

  bool _current(int request) =>
      !_disposed &&
      request == _request &&
      client.session.generation == _generation &&
      client.session.isConnected;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _stop() {
    final previous = _video;
    _video = null;
    _videoReady = false;
    previous?.removeListener(_videoChanged);
    if (previous != null) {
      _retired = _retired.then((_) async {
        try {
          // Failed platform creation can leave video_player waiting forever.
          // The disposal continues if native creation eventually completes.
          await previous.dispose().timeout(cleanupTimeout);
        } catch (_) {/* No native error logging. */}
      });
    }
    return _retired;
  }

  Future<void> load() async {
    _resumePosition = Duration.zero;
    _resumePlaying = true;
    final request = ++_request;
    _generation = client.session.generation;
    loading = true;
    error = null;
    sources = null;
    selected = null;
    _changed();
    await _stop();
    try {
      final result = await client.getSources(course, lesson);
      if (!_current(request)) return;
      sources = result;
      await _open(result.preferred, request, Duration.zero, true);
    } on ElrcException catch (failure) {
      if (_current(request)) error = failure;
    } catch (_) {
      if (_current(request)) error = const ElrcException(ElrcErrorKind.playback);
    } finally {
      if (_current(request)) {
        loading = false;
        _changed();
      }
    }
  }

  Future<void> select(ElrcRecordingSource source) async {
    if (sources?.sources.contains(source) != true || selected == source) return;
    _rememberVideo();
    final position = _resumePosition;
    final playing = _resumePlaying;
    final request = ++_request;
    loading = true;
    error = null;
    _changed();
    await _stop();
    await _open(source, request, position, playing);
    if (_current(request)) {
      loading = false;
      _changed();
    }
  }

  Future<void> _open(ElrcRecordingSource source, int request, Duration position, bool play) async {
    try {
      final headers = await client.playbackHeaders(course, source.uri);
      if (!_current(request)) return;
      final controller = _createVideo(source.uri, headers);
      _video = controller;
      selected = source;
      controller.addListener(_videoChanged);
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (!_owns(controller, request)) return;
      final duration = controller.value.duration;
      await controller.seekTo(position < duration ? position : duration);
      if (!_owns(controller, request)) return;
      // video_player.play() restarts at zero when positioned at the end.
      if (play && _resumePlaying && _foreground && position < duration) {
        await controller.play();
      }
      if (!_owns(controller, request)) return;
      // Initialization/seek notifications must not replace the saved progress
      // until this camera has actually recovered successfully.
      _videoReady = true;
      _rememberVideo();
    } on ElrcException catch (failure) {
      if (_current(request)) {
        error = failure;
        await _stop();
      }
    } catch (_) {
      if (_current(request)) {
        error = const ElrcException(ElrcErrorKind.playback);
        await _stop();
      }
    }
  }

  bool _owns(VideoPlayerController controller, int request) =>
      _current(request) && identical(_video, controller) && !controller.value.hasError;

  void _rememberVideo() {
    final value = _video?.value;
    if (!_videoReady || value == null || !value.isInitialized || value.hasError) return;
    _resumePosition = value.position;
    _resumePlaying = value.isPlaying;
  }

  void _videoChanged() {
    if (_video?.value.hasError == true) {
      error = const ElrcException(ElrcErrorKind.playback);
      unawaited(_stop());
      _changed();
    } else {
      _rememberVideo();
    }
  }

  Future<void> togglePlay() async {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized || !_foreground) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
      }
    } catch (_) {
      error = const ElrcException(ElrcErrorKind.playback);
      await _stop();
      _changed();
    }
  }

  Future<void> seek(Duration position) async {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    final bounded = position < Duration.zero
        ? Duration.zero
        : position > controller.value.duration
            ? controller.value.duration
            : position;
    try {
      await controller.seekTo(bounded);
    } catch (_) {
      error = const ElrcException(ElrcErrorKind.playback);
      _changed();
    }
  }

  void setForeground(bool active) {
    _foreground = active;
    if (!active) {
      _resumePlaying = false;
      final controller = _video;
      if (controller != null) unawaited(controller.pause().catchError((Object _) {}));
    }
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
