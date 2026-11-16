import 'dart:async';

import '../domain/ports/platform_ports.dart';

/// Confirms online-to-offline transitions when the payment page is active.
/// System panels preserve the baseline; a new page opened offline stays silent.
final class ConfirmedDisconnectFeedback {
  ConfirmedDisconnectFeedback({
    required this.connectivity,
    required this.lifecycle,
    required this.feedback,
    this.confirmationDelay = const Duration(milliseconds: 600),
  });

  final ConnectivityPort connectivity;
  final AppLifecyclePort lifecycle;
  final FeedbackPort feedback;
  final Duration confirmationDelay;
  StreamSubscription<bool>? _networkSubscription;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;
  Timer? _confirmation;
  bool? _online;
  bool? _latestNetwork;
  bool _active = false;
  bool _disposed = false;
  int _generation = 0;
  int _networkRevision = 0;

  Future<void> start() async {
    if (_disposed || _networkSubscription != null) return;
    _networkSubscription = connectivity.changes.listen(_onNetwork);
    _lifecycleSubscription = lifecycle.changes.listen((state) {
      if (state == AppLifecycleState.resumed) {
        unawaited(_seed());
      } else {
        _active = false;
        if (state == AppLifecycleState.detached) _online = null;
        _generation++;
        _confirmation?.cancel();
        _confirmation = null;
      }
    });
    await _seed();
  }

  Future<void> _seed() async {
    _active = false;
    _confirmation?.cancel();
    _confirmation = null;
    final generation = ++_generation;
    final revision = _networkRevision;
    if (lifecycle.current != AppLifecycleState.resumed) return;
    bool? online;
    try {
      online = await connectivity.isOnline();
    } catch (_) {
      // Unknown connectivity cannot establish a confirmed transition.
    }
    if (_disposed ||
        generation != _generation ||
        lifecycle.current != AppLifecycleState.resumed) {
      return;
    }
    _active = true;
    final currentNetwork =
        revision == _networkRevision ? online : _latestNetwork;
    if (currentNetwork != null) _onNetwork(currentNetwork);
  }

  void _onNetwork(bool online) {
    if (_disposed) return;
    _networkRevision++;
    _latestNetwork = online;
    if (!_active) return;
    if (_online == null) {
      _online = online;
      return;
    }
    if (online) {
      _online = true;
      _generation++;
      _confirmation?.cancel();
      _confirmation = null;
      return;
    }
    if (_online != true || _confirmation != null) return;
    final generation = _generation;
    _confirmation =
        Timer(confirmationDelay, () => unawaited(_confirm(generation)));
  }

  Future<void> _confirm(int generation) async {
    _confirmation = null;
    bool online;
    try {
      online = await connectivity.isOnline();
    } catch (_) {
      return;
    }
    if (_disposed ||
        !_active ||
        lifecycle.current != AppLifecycleState.resumed ||
        generation != _generation ||
        _online != true) {
      return;
    }
    if (!online) {
      _online = false;
      try {
        await feedback.play(FeedbackEvent.networkDisconnected);
      } catch (_) {
        // Feedback cannot prevent the payment page from entering offline state.
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _confirmation?.cancel();
    await _networkSubscription?.cancel();
    await _lifecycleSubscription?.cancel();
  }
}
