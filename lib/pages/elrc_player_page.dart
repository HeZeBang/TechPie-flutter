import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/elrc_client.dart';

class ElrcPlayerPage extends StatefulWidget {
  const ElrcPlayerPage({
    super.key,
    required this.courseName,
    required this.lessonTitle,
    required this.referer,
    required this.sources,
  });

  final String courseName;
  final String lessonTitle;
  final Uri referer;
  final List<ElrcSource> sources;

  @override
  State<ElrcPlayerPage> createState() => _ElrcPlayerPageState();
}

class _ElrcPlayerPageState extends State<ElrcPlayerPage> {
  late final WebViewController _controller;
  var _selected = 0;
  var _loading = true;
  var _closing = false;
  var _loadGeneration = 0;
  var _readyGeneration = 0;
  var _hasPlaybackState = false;
  Timer? _loadTimeout;
  double _resumeSeconds = 0;
  bool _resumePlaying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.addJavaScriptChannel(
      'TechPiePlayer',
      onMessageReceived: _playerMessage,
    );
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (request.url == 'about:blank' ||
              (uri?.scheme == 'https' && uri?.host == 'elrc.shanghaitech.edu.cn')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onPageFinished: _mediaDocumentReady,
        onWebResourceError: _webResourceFailed,
      ),
    );
    await _load(0, preservePlayback: false);
  }

  Future<void> _load(int index, {bool preservePlayback = true}) async {
    if (!mounted || _closing || index < 0 || index >= widget.sources.length) return;
    if (preservePlayback) await _rememberPlayback();
    if (!mounted || _closing) return;
    final generation = ++_loadGeneration;
    _loadTimeout?.cancel();
    _loadTimeout = Timer(
      const Duration(seconds: 30),
      () => _loadTimedOut(generation),
    );
    setState(() {
      _selected = index;
      _loading = true;
      _error = null;
    });
    try {
      await _controller.loadRequest(
        widget.sources[index].uri,
        headers: {'Referer': widget.referer.toString()},
      );
    } catch (_) {
      if (_isCurrent(generation)) {
        _loadTimeout?.cancel();
        _trace('request failed before WebKit accepted it');
        setState(() {
          _loading = false;
          _error = '视频加载失败';
        });
      }
    }
  }

  Future<void> _rememberPlayback() async {
    try {
      final result = await _controller.runJavaScriptReturningResult('''
JSON.stringify((() => {
  const video = document.querySelector('video');
  if (!video) return {};
  return {
    seconds: Number.isFinite(video.currentTime) ? video.currentTime : 0,
    playing: !video.paused && !video.ended,
  };
})())
''');
      final decoded = jsonDecode(result.toString());
      if (decoded is! Map<String, dynamic>) return;
      final seconds = decoded['seconds'];
      final playing = decoded['playing'];
      if (seconds is num && seconds.isFinite && seconds >= 0) {
        _resumeSeconds = seconds.toDouble();
        _hasPlaybackState = true;
      }
      if (playing is bool) {
        _resumePlaying = playing;
        _hasPlaybackState = true;
      }
      _trace(
        'remembered position=${_resumeSeconds.toStringAsFixed(1)}s '
        'playing=$_resumePlaying',
      );
    } catch (_) {
      _trace('playback state was not readable');
    }
  }

  void _mediaDocumentReady(String url) {
    if (!_matchesCurrentMedia(url)) {
      _trace('ignored retired media document');
      return;
    }
    _mediaReady(_loadGeneration, 'media document ready');
  }

  void _mediaReady(int generation, String reason) {
    if (!_isCurrent(generation) || _readyGeneration == generation) return;
    _readyGeneration = generation;
    _trace(reason);
    _showPlayer(generation);
    unawaited(_restorePlayback(generation));
  }

  void _webResourceFailed(WebResourceError failure) {
    _trace(
      'resource callback main=${failure.isForMainFrame} '
      'code=${failure.errorCode} type=${failure.errorType?.name}',
    );
    if (failure.isForMainFrame != true || _closing || !mounted) return;
    if (!_matchesCurrentMedia(failure.url)) {
      _trace('ignored callback from retired media');
      return;
    }

    final isWebKit = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    // WKWebView reports direct video documents as WebKit error 204 when AVKit
    // takes over playback. The video is usable; this callback is its success path.
    if (isWebKit && failure.errorCode == 204) {
      _mediaReady(_loadGeneration, 'native player accepted the media document');
      return;
    }

    // Replacing a media document can cancel the retired navigation.
    if (failure.errorCode == -999 ||
        (isWebKit && failure.errorCode == 102)) {
      _trace('ignored retired media navigation');
      return;
    }

    _loadTimeout?.cancel();
    setState(() {
      _loading = false;
      _error = '视频加载失败';
    });
  }

  bool _matchesCurrentMedia(String? url) =>
      url == null || url == widget.sources[_selected].uri.toString();

  void _loadTimedOut(int generation) {
    if (!_isCurrent(generation) || _readyGeneration == generation) return;
    _trace('load timed out after 30 seconds');
    setState(() {
      _loading = false;
      _error = '视频加载超时';
    });
  }

  void _showPlayer(int generation) {
    if (!_isCurrent(generation)) return;
    _loadTimeout?.cancel();
    setState(() {
      _loading = false;
      _error = null;
    });
  }

  Future<void> _restorePlayback(int generation) async {
    if (!_isCurrent(generation) || !_hasPlaybackState) return;
    final seconds = _resumeSeconds;
    final resumePlaying = _resumePlaying;
    try {
      await _controller.runJavaScript('''
(() => {
  let attempts = 0;
  const restore = () => {
    const video = document.querySelector('video');
    if (!video || video.readyState < 1) return false;
    const duration = Number.isFinite(video.duration) ? video.duration : $seconds;
    video.currentTime = Math.min($seconds, Math.max(0, duration - 0.25));
    if ($resumePlaying) {
      const play = video.play();
      if (play) play.catch(() => {});
    } else {
      video.pause();
    }
    if (window.TechPiePlayer) {
      window.TechPiePlayer.postMessage(JSON.stringify({
        generation: $generation,
        type: 'restored',
        seconds: video.currentTime,
      }));
    }
    return true;
  };
  if (restore()) return;
  const timer = setInterval(() => {
    attempts += 1;
    if (restore() || attempts >= 40) clearInterval(timer);
  }, 100);
})();
''');
    } catch (_) {
      _trace('playback restore was not available');
    }
  }

  void _playerMessage(JavaScriptMessage message) {
    if (_closing || message.message.length > 1024) return;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic> || decoded['generation'] != _loadGeneration) return;
      if (decoded['type'] == 'restored' && decoded['seconds'] is num) {
        _trace('restored position=${(decoded['seconds'] as num).toStringAsFixed(1)}s');
      }
    } on FormatException {
      return;
    }
  }

  bool _isCurrent(int generation) => mounted && !_closing && generation == _loadGeneration;

  void _trace(String message) {
    if (kDebugMode) debugPrint('[ELRC player] $message');
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _loadGeneration++;
    _loadTimeout?.cancel();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _closing = true;
    _loadGeneration++;
    _loadTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _close),
          title: Text(widget.courseName),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  widget.lessonTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (widget.sources.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      for (var index = 0; index < widget.sources.length; index++) ...[
                        if (index > 0) const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(widget.sources[index].label),
                          selected: index == _selected,
                          onSelected: _loading ? null : (_) => unawaited(_load(index)),
                        ),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: WebViewWidget(controller: _controller),
                    ),
                    if (_loading)
                      ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('正在加载视频'),
                            ],
                          ),
                        ),
                      ),
                    if (_error != null)
                      ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 40),
                              const SizedBox(height: 12),
                              Text(_error!),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () => unawaited(_load(_selected)),
                                child: const Text('重新加载'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
