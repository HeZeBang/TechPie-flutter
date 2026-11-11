import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/http_client.dart';
import '../services/live_classroom_cache.dart';
import '../services/live_client.dart';
import '../services/live_playback_session.dart';
import '../services/service_provider.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/media_player_scaffold.dart';
import '../widgets/media_volume_menu.dart';

bool get supportsLivePlayback =>
    !kIsWeb &&
    {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }.contains(defaultTargetPlatform);

Future<void> enterCourseLive(
  BuildContext context,
  String title,
  String classroom, {
  required DateTime endsAt,
}) async {
  if (!supportsLivePlayback) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前平台暂不支持直播播放')),
    );
    return;
  }
  await Navigator.of(context, rootNavigator: true).push<void>(
    adaptivePageRoute<void>(
      builder: (_) => LivePlayerPage(
        title: title,
        classroom: classroom,
        expiresAt: endsAt.add(const Duration(minutes: 5)),
      ),
    ),
  );
}

class LivePlayerPage extends StatefulWidget {
  const LivePlayerPage({
    super.key,
    required this.title,
    this.classroom,
    this.roomId,
    this.expiresAt,
  }) : assert((classroom == null) != (roomId == null));

  final String title;
  final String? classroom;
  final int? roomId;
  final DateTime? expiresAt;

  @override
  State<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends State<LivePlayerPage> with WidgetsBindingObserver {
  Player? _player;
  VideoController? _video;
  LivePlaybackSession? _session;
  LoggingHttpClient? _http;
  ServiceProvider? _services;
  StreamSubscription<String>? _errors;
  String? _owner;
  String? _semesterId;
  String? _blockedMessage;
  Timer? _expiryTimer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    final deadline = widget.expiresAt;
    if (deadline == null) return;
    final remaining = deadline.difference(DateTime.now());
    _expiryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _checkExpiry,
    );
  }

  void _checkExpiry() {
    if (!mounted || _leaving || widget.expiresAt == null) return;
    if (DateTime.now().isBefore(widget.expiresAt!)) {
      _scheduleExpiry();
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null) return;
    _leaving = true;
    unawaited(_session?.shutdown());
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  String _identity(ServiceProvider services) {
    final primary = services.authService.session?.userId ?? '';
    final campus = services.thirdPartyAuthService.cpdailyNode.account?.account ?? '';
    return '$primary:$campus';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.expiresAt != null && !DateTime.now().isBefore(widget.expiresAt!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkExpiry());
      return;
    }
    if (_services != null || !supportsLivePlayback) return;
    final services = ServiceProvider.of(context);
    _services = services;
    _owner = _identity(services);
    _semesterId = services.scheduleService.selectedSemesterId;
    services.scheduleService.addListener(_checkAccount);
    services.authService.addListener(_checkAccount);
    services.thirdPartyAuthService.addListener(_checkAccount);
    WidgetsBinding.instance.addObserver(this);
    try {
      MediaKit.ensureInitialized();
      final player = Player(
        configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
      );
      _player = player;
      _video = VideoController(player);
      final http = LoggingHttpClient(services.debugLogger);
      _http = http;
      final client = LiveClient(
        services.thirdPartyAuthService,
        services.storageService,
        http,
      );
      final table = services.scheduleService.courseTable;
      final semesterId = _semesterId;
      if (widget.roomId == null && (table == null || semesterId == null)) {
        throw const LiveException('请先加载课表');
      }
      final fingerprint = table == null ? '' : liveScheduleFingerprint(table);
      final session = LivePlaybackSession(
        fetch: (camera) async => widget.roomId != null
            ? client.byId(widget.roomId!, camera)
            : client.byClassroom(
                widget.classroom!,
                camera,
                semesterId: semesterId!,
                fingerprint: fingerprint,
              ),
        open: (uri) async {
          await player.open(Media(uri.toString()));
        },
        stop: () async {
          await player.stop();
        },
        release: () async {
          await player.dispose();
        },
      );
      _session = session;
      session.addListener(_update);
      _errors = player.stream.error.listen((error) {
        if (kDebugMode) debugPrint('Live player error: $error');
        session.playbackFailed();
      });
      unawaited(session.select(LiveCamera.panorama));
    } catch (_) {
      _blockedMessage = '播放器初始化失败，请重新进入直播';
    }
  }

  void _update() {
    if (mounted) setState(() {});
  }

  void _checkAccount() {
    final services = _services;
    if (services == null ||
        _blockedMessage != null ||
        (_owner == _identity(services) &&
            _semesterId == services.scheduleService.selectedSemesterId)) {
      return;
    }
    _blockedMessage = '账号或学期已变化，请退出后重新进入直播';
    unawaited(_session?.shutdown());
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkExpiry();
    if (_leaving) return;
    if (_blockedMessage != null) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(_player?.pause());
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _services?.scheduleService.removeListener(_checkAccount);
    _services?.authService.removeListener(_checkAccount);
    _services?.thirdPartyAuthService.removeListener(_checkAccount);
    unawaited(_errors?.cancel());
    final session = _session;
    final http = _http;
    if (session != null) {
      session.removeListener(_update);
      unawaited(session.shutdown().whenComplete(() => http?.close()));
      session.dispose();
    } else {
      unawaited(_player?.dispose());
      http?.close();
    }
    super.dispose();
  }

  Widget _buildVideo() {
    final mobileTheme = MaterialVideoControlsThemeData(
      displaySeekBar: false,
      seekGesture: false,
      seekOnDoubleTap: false,
      visibleOnMount: true,
      buttonBarHeight: 52,
      bottomButtonBarMargin: EdgeInsets.zero,
      primaryButtonBar: const [
        Spacer(),
        MaterialPlayOrPauseButton(iconSize: 48),
        Spacer(),
      ],
      bottomButtonBar: [
        MediaVolumeMenu(player: _player!),
        const Spacer(),
        const MaterialFullscreenButton(),
      ],
    );
    const desktopTheme = MaterialDesktopVideoControlsThemeData(
      displaySeekBar: false,
      visibleOnMount: true,
      keyboardShortcuts: {},
      bottomButtonBar: [
        MaterialDesktopPlayOrPauseButton(),
        MaterialDesktopVolumeButton(),
        Spacer(),
        MaterialDesktopFullscreenButton(),
      ],
    );
    return MaterialVideoControlsTheme(
      normal: mobileTheme,
      fullscreen: mobileTheme,
      child: MaterialDesktopVideoControlsTheme(
        normal: desktopTheme,
        fullscreen: desktopTheme,
        child: Video(controller: _video!, controls: AdaptiveVideoControls),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = !supportsLivePlayback ? '当前平台暂不支持直播播放' : _blockedMessage ?? _session?.error;
    return MediaPlayerScaffold(
      title: widget.title,
      sourceLabels: [for (final camera in LiveCamera.values) camera.label],
      selectedSource: _session?.camera.index ?? 0,
      sourceEnabled: _blockedMessage == null && _session != null && _session?.loading != true,
      onSourceSelected: (index) => unawaited(_session!.select(LiveCamera.values[index])),
      player: _video != null && _blockedMessage == null ? _buildVideo() : null,
      loading: _session?.loading == true && _blockedMessage == null,
      error: message,
      onRetry: _blockedMessage == null && _session != null
          ? () => unawaited(_session!.select(_session!.camera))
          : null,
    );
  }
}
