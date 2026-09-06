import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/elrc_course.dart';
import '../models/elrc_recording.dart';
import '../services/elrc_client.dart';
import '../services/elrc_error.dart';
import '../services/elrc_playback.dart';
import 'elrc_course_page.dart';

class ElrcPlayerPage extends StatefulWidget {
  const ElrcPlayerPage({
    super.key,
    required this.course,
    required this.lesson,
    required this.client,
    this.playback,
  });
  final ElrcCourse course;
  final ElrcRecordingLesson lesson;
  final ElrcClient client;

  /// An injected playback stays owned by its caller; the page pauses it on exit.
  final ElrcPlayback? playback;

  @override
  State<ElrcPlayerPage> createState() => _ElrcPlayerPageState();
}

class _ElrcPlayerPageState extends State<ElrcPlayerPage> with WidgetsBindingObserver {
  late ElrcPlayback _playback;
  bool _ownsPlayback = false;
  bool _fullScreen = false;
  double? _dragPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  void _initialize() {
    _ownsPlayback = widget.playback == null;
    _playback = widget.playback ??
        ElrcPlayback(
          course: widget.course,
          lesson: widget.lesson,
          client: widget.client,
        );
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _playback.setForeground(
      lifecycle == null ||
          lifecycle == AppLifecycleState.resumed ||
          lifecycle == AppLifecycleState.inactive,
    );
    if (_ownsPlayback || (!_playback.loading && _playback.sources == null)) {
      unawaited(_playback.load());
    }
  }

  void _releasePlayback() {
    if (_ownsPlayback) {
      _playback.dispose();
    } else {
      _playback.setForeground(false);
    }
  }

  @override
  void didUpdateWidget(ElrcPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.playback, widget.playback) ||
        !identical(oldWidget.client, widget.client) ||
        oldWidget.lesson.id != widget.lesson.id ||
        oldWidget.course.key != widget.course.key) {
      _releasePlayback();
      _dragPosition = null;
      _initialize();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Temporary focus loss (notification shade, interruption banner) is not
    // background playback. Actual background transitions still pause audio.
    if (state != AppLifecycleState.inactive) {
      _playback.setForeground(state == AppLifecycleState.resumed);
    }
  }

  Future<void> _reload() async {
    if (_playback.error?.kind == ElrcErrorKind.staleSession || !widget.client.session.isConnected) {
      Navigator.of(context).pop();
      return;
    }
    await _playback.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releasePlayback();
    super.dispose();
  }

  String _time(Duration value) {
    final seconds = value.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds ~/ 60) % 60;
    final clock =
        '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return hours > 0 ? '$hours:$clock' : clock;
  }

  Widget _controls() {
    final controller = _playback.video;
    if (controller == null) return _buildControls();
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) => _buildControls(),
    );
  }

  Widget _buildControls() {
    final value = _playback.video?.value;
    final duration = value?.duration ?? Duration.zero;
    final position = value?.position ?? Duration.zero;
    final ready = value?.isInitialized == true && !_playback.loading;
    final max = duration.inMilliseconds.toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: value?.isPlaying == true ? '暂停' : '播放',
              onPressed: ready ? () => unawaited(_playback.togglePlay()) : null,
              icon: Icon(
                value?.isPlaying == true ? Icons.pause : Icons.play_arrow,
              ),
            ),
            Expanded(
              child: Slider(
                label: _time(
                  Duration(
                    milliseconds: (_dragPosition ?? position.inMilliseconds.toDouble()).round(),
                  ),
                ),
                value: (_dragPosition ?? position.inMilliseconds.toDouble())
                    .clamp(0.0, max > 0 ? max : 1.0),
                max: max > 0 ? max : 1.0,
                onChanged:
                    ready && max > 0 ? (value) => setState(() => _dragPosition = value) : null,
                onChangeEnd: ready && max > 0
                    ? (value) {
                        setState(() => _dragPosition = null);
                        unawaited(
                          _playback.seek(Duration(milliseconds: value.round())),
                        );
                      }
                    : null,
                semanticFormatterCallback: (value) =>
                    '${_time(Duration(milliseconds: value.round()))}，总长 ${_time(duration)}',
              ),
            ),
            IconButton(
              tooltip: _fullScreen ? '退出全屏' : '全屏',
              onPressed: () => setState(() => _fullScreen = !_fullScreen),
              icon: Icon(_fullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(_time(position)), Text(_time(duration))],
          ),
        ),
      ],
    );
  }

  Widget _video() {
    final error = _playback.error;
    if (error != null) {
      return ElrcStateMessage(
        icon: error.kind == ElrcErrorKind.noRecording
            ? Icons.video_library_outlined
            : Icons.info_outline,
        title: error.message,
        actionLabel: error.kind == ElrcErrorKind.staleSession ? '返回课程' : '重新加载',
        onAction: () => unawaited(_reload()),
      );
    }
    final controller = _playback.video;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: controller?.value.isInitialized == true
            ? AspectRatio(
                aspectRatio:
                    controller!.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9,
                child: VideoPlayer(controller),
              )
            : AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(
                  child: _playback.loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(
                          Icons.videocam_off_outlined,
                          size: 44,
                          color: Colors.white70,
                        ),
                ),
              ),
      ),
    );
  }

  Widget _sourceChoices() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final source in _playback.sources?.sources ?? <ElrcRecordingSource>[])
            ChoiceChip(
              label: Text(source.label),
              selected: _playback.selected == source,
              onSelected: _playback.loading ? null : (_) => unawaited(_playback.select(source)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_fullScreen,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _fullScreen) setState(() => _fullScreen = false);
        },
        child: Scaffold(
          appBar: _fullScreen ? null : AppBar(title: Text(widget.course.name)),
          body: SafeArea(
            child: ListenableBuilder(
              listenable: _playback,
              builder: (context, _) {
                final error = _playback.error;
                if (_fullScreen) {
                  return Column(
                    children: [
                      Expanded(child: _video()),
                      _controls(),
                      if (error != null)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: SingleChildScrollView(child: _sourceChoices()),
                        ),
                      const SizedBox(height: 12),
                    ],
                  );
                }
                return ListView(
                  children: [
                    AspectRatio(aspectRatio: 16 / 9, child: _video()),
                    _controls(),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.lesson.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (widget.lesson.weekDate.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(widget.lesson.weekDate),
                          ],
                          const SizedBox(height: 24),
                          Text(
                            '观看机位',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          _sourceChoices(),
                          if ((_playback.sources?.unavailableCount ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                '${_playback.sources!.unavailableCount} 个机位暂不可用，已保留可观看的机位。',
                              ),
                            ),
                          const SizedBox(height: 24),
                          const Text('切换机位会尽量保留当前进度。'),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
}
