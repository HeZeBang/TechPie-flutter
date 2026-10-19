import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/elrc_client.dart';
import '../widgets/media_player_scaffold.dart';
import '../widgets/media_volume_menu.dart';

class ElrcPlayerPage extends StatefulWidget {
  const ElrcPlayerPage({
    super.key,
    required this.courseName,
    required this.lessonTitle,
    required this.referer,
    required this.sources,
    this.cookie,
  });

  final String courseName;
  final String lessonTitle;
  final Uri referer;
  final List<ElrcSource> sources;
  final String? cookie;

  @override
  State<ElrcPlayerPage> createState() => _ElrcPlayerPageState();
}

class _ElrcPlayerPageState extends State<ElrcPlayerPage> with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _video;
  StreamSubscription<String>? _errors;
  int _selected = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaKit.ensureInitialized();
    _player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error));
    _video = VideoController(_player);
    _errors = _player.stream.error.listen((_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '视频播放失败';
        });
      }
    });
    unawaited(_load(_selected, preservePlayback: false));
  }

  Future<void> _load(int index, {bool preservePlayback = true}) async {
    if (!mounted || index < 0 || index >= widget.sources.length) return;
    final position = preservePlayback ? _player.state.position : Duration.zero;
    final playing = !preservePlayback || _player.state.playing;
    setState(() {
      _selected = index;
      _loading = true;
      _error = null;
    });
    try {
      await _player.open(
        Media(
          widget.sources[index].uri.toString(),
          httpHeaders: {
            'Referer': widget.referer.toString(),
            if (widget.cookie != null && widget.cookie!.isNotEmpty) 'Cookie': widget.cookie!,
          },
        ),
        play: playing,
      );
      if (position > Duration.zero) await _player.seek(position);
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '视频加载失败';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(_player.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_errors?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MediaPlayerScaffold(
        title: widget.courseName,
        subtitle: widget.lessonTitle,
        sourceLabels: [for (final source in widget.sources) source.label],
        selectedSource: _selected,
        sourceEnabled: !_loading,
        onSourceSelected: (index) => unawaited(_load(index)),
        player: MaterialVideoControlsTheme(
          normal: _mobileControls,
          fullscreen: _mobileControls,
          child: MaterialDesktopVideoControlsTheme(
            normal: const MaterialDesktopVideoControlsThemeData(playAndPauseOnTap: true),
            fullscreen: const MaterialDesktopVideoControlsThemeData(playAndPauseOnTap: true),
            child: Video(controller: _video, controls: AdaptiveVideoControls),
          ),
        ),
        loading: _loading,
        error: _error,
        onRetry: _error == null ? null : () => unawaited(_load(_selected)),
      );

  MaterialVideoControlsThemeData get _mobileControls => MaterialVideoControlsThemeData(
        visibleOnMount: true,
        displaySeekBar: true,
        seekGesture: true,
        seekOnDoubleTap: true,
        buttonBarHeight: 52,
        topButtonBarMargin: EdgeInsets.zero,
        bottomButtonBarMargin: EdgeInsets.zero,
        primaryButtonBar: [
          const Spacer(flex: 2),
          Tooltip(
            message: '后退 10 秒',
            child: MaterialCustomButton(
              icon: const Icon(Icons.replay_10),
              iconSize: 30,
              onPressed: () => _seekBy(-10),
            ),
          ),
          const Spacer(),
          const MaterialPlayOrPauseButton(iconSize: 48),
          const Spacer(),
          Tooltip(
            message: '快进 10 秒',
            child: MaterialCustomButton(
              icon: const Icon(Icons.forward_10),
              iconSize: 30,
              onPressed: () => _seekBy(10),
            ),
          ),
          const Spacer(flex: 2),
        ],
        topButtonBar: const [Spacer(), MaterialPositionIndicator()],
        bottomButtonBar: [
          _SpeedButton(player: _player),
          MediaVolumeMenu(player: _player),
          const Spacer(),
          const MaterialFullscreenButton(),
        ],
      );

  void _seekBy(int seconds) {
    final target = _player.state.position + Duration(seconds: seconds);
    final duration = _player.state.duration;
    final position = target < Duration.zero
        ? Duration.zero
        : target > duration
            ? duration
            : target;
    unawaited(_player.seek(position));
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
        stream: player.stream.rate,
        initialData: player.state.rate,
        builder: (context, snapshot) {
          final current = snapshot.data ?? 1;
          return PopupMenuButton<double>(
            tooltip: '倍速',
            icon: const Icon(Icons.speed, color: Colors.white),
            onSelected: (rate) => unawaited(player.setRate(rate)),
            itemBuilder: (_) => [
              for (final rate in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0])
                CheckedPopupMenuItem<double>(
                  value: rate,
                  checked: (current - rate).abs() < 0.01,
                  child: Text('${rate}x'),
                ),
            ],
          );
        },
      );
}
