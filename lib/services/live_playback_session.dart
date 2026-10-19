import 'dart:async';

import 'package:flutter/foundation.dart';

import 'live_client.dart';

/// Serializes native media mutations while requests may finish out of order.
class LivePlaybackSession extends ChangeNotifier {
  LivePlaybackSession({
    required this.fetch,
    required this.open,
    required this.stop,
    required this.release,
  });
  final Future<Uri> Function(LiveCamera) fetch;
  final Future<void> Function(Uri) open;
  final Future<void> Function() stop;
  final Future<void> Function() release;
  LiveCamera camera = LiveCamera.panorama;
  bool loading = false;
  String? error;
  int _generation = 0;
  bool _closed = false;
  bool _receivingMedia = false;
  Future<void> _operations = Future.value();
  Future<void>? _shutdown;

  Future<void> _enqueue(Future<void> Function() action) {
    final task = _operations.then((_) => action());
    _operations = task.catchError((Object _) {});
    return task;
  }

  Future<void> select(LiveCamera selected) async {
    if (_closed) return;
    final generation = ++_generation;
    camera = selected;
    loading = true;
    _receivingMedia = false;
    error = null;
    notifyListeners();
    try {
      await _enqueue(stop);
      if (!_current(generation)) return;
      final uri = await fetch(selected);
      if (!_current(generation)) return;
      await _enqueue(() async {
        if (!_current(generation)) return;
        _receivingMedia = true;
        await open(uri);
      });
      if (!_current(generation)) return;
      loading = false;
      notifyListeners();
    } catch (failure) {
      if (!_current(generation)) return;
      loading = false;
      error = failure is LiveException ? failure.message : '直播连接失败，请重试';
      notifyListeners();
    }
  }

  bool _current(int generation) => !_closed && generation == _generation;
  void playbackFailed() {
    if (_closed || !_receivingMedia) return;
    _generation++;
    _receivingMedia = false;
    loading = false;
    error = '直播暂无信号或连接已中断';
    notifyListeners();
    unawaited(_enqueue(stop));
  }

  Future<void> shutdown() => _shutdown ??= _close().catchError((Object _) {});
  Future<void> _close() async {
    _closed = true;
    _generation++;
    await _enqueue(() async {
      try {
        await stop();
      } finally {
        await release();
      }
    });
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
