import 'dart:async';

/// Coalesces refresh triggers. A balance change gets at most one follow-up,
/// driven by the next successful code generation rather than another timer.
final class AccountHistoryRefresh {
  AccountHistoryRefresh({required this.loadHistory});
  final Future<bool> Function() loadHistory;
  Future<void>? _active;
  int _revision = 0;
  int _cycle = 0;
  int? _retryAfterCycle;
  bool _balancePending = false;
  bool _disposed = false;
  int _holds = 0;

  bool get isDisposed => _disposed;

  void hold() => _holds++;

  Future<void> releaseAndRefresh() {
    if (_holds > 0) _holds--;
    return refresh(fresh: true);
  }

  Future<void> codeGenerated({required bool balanceChanged}) {
    if (_disposed) return Future.value();
    _cycle++;
    if (balanceChanged) {
      _balancePending = true;
      _revision++;
      _retryAfterCycle = null;
      return refresh();
    }
    final retry = _retryAfterCycle;
    if (retry != null && _cycle > retry) {
      _retryAfterCycle = null;
      return refresh();
    }
    return Future.value();
  }

  Future<void> refresh({bool fresh = false}) {
    if (_disposed) return Future.value();
    if (fresh) _revision++;
    if (_holds > 0) return Future.value();
    final active = _active;
    if (active != null) return active;
    late final Future<void> operation;
    operation = Future<void>.microtask(_run).whenComplete(() {
      if (identical(_active, operation)) _active = null;
    });
    _active = operation;
    return operation;
  }

  Future<void> _run() async {
    // One initial load and at most one additional load for a newer trigger.
    for (var attempt = 0; attempt < 2 && !_disposed; attempt++) {
      if (_holds > 0) return;
      final revision = _revision;
      final cycle = _cycle;
      final balancePending = _balancePending;
      _balancePending = false;
      var hasNewRecords = false;
      try {
        hasNewRecords = await loadHistory();
      } catch (_) {
        // The feed owns its error state; refresh failure cannot undo payment.
      }
      if (_disposed) return;
      if (_revision != revision) {
        _balancePending = _balancePending || balancePending;
        if (attempt == 0) continue;
        _retryAfterCycle = _cycle;
        return;
      }
      if (hasNewRecords) {
        _retryAfterCycle = null;
      } else if (balancePending) {
        _retryAfterCycle = cycle;
      }
      return;
    }
  }

  void dispose() { _disposed = true; }
}
