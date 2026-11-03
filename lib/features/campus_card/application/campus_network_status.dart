import 'dart:async';

import '../core/errors/app_failure.dart';
import '../data/api/ecard_api_client.dart' show apiRejected;
import '../domain/models/payment_models.dart';
import '../domain/ports/platform_ports.dart';

/// Observes real queries; cached data never clears an interface's failure.
final class CampusNetworkStatus {
  CampusNetworkStatus({required ConnectivityPort connectivity}) : _connectivity = connectivity;

  final ConnectivityPort _connectivity;
  final _updates = StreamController<PaymentConnectionState>.broadcast();
  final _failed = <String>{};
  final _latest = <String, int>{};
  StreamSubscription<bool>? _subscription;
  PaymentConnectionState _state = PaymentConnectionState.online;
  bool _disconnected = false;
  bool _slowCode = false;
  int _sequence = 0;
  int _generation = 0;
  int _evidence = 0;

  PaymentConnectionState get state => _state;

  void start() {
    if (_subscription != null || _updates.isClosed) return;
    _subscription = _connectivity.changes.listen((online) {
      ++_evidence;
      _disconnected = !online;
      _publish();
    });
    unawaited(checkConnection());
  }

  Stream<PaymentConnectionState> get states => Stream.multi((sink) {
        sink.add(state);
        final subscription = _updates.stream.listen(sink.add, onDone: sink.close);
        sink.onCancel = subscription.cancel;
      });

  Future<T> track<T>(String api, Future<T> Function() query) async {
    final generation = _generation;
    final sequence = ++_sequence;
    try {
      final result = await query();
      if (_accept(api, generation, sequence)) {
        ++_evidence;
        _disconnected = false;
        if (result is PaymentShouldUseOffline ||
            result is PaymentPending && !result.querySucceeded ||
            result is Map<String, Object?> && apiRejected(result)) {
          _failed.add(api);
        } else {
          _failed.remove(api);
        }
        _publish();
      }
      return result;
    } catch (error) {
      if (!(error is AppFailure && (error.kind == FailureKind.cancelled || error.requestNotSent)) &&
          _accept(api, generation, sequence)) {
        ++_evidence;
        _failed.add(api);
        final networkFailure = error is AppFailure &&
            (error.kind == FailureKind.network || error.kind == FailureKind.timeout);
        if (error is AppFailure && !networkFailure) _disconnected = false;
        _publish();
        if (networkFailure) unawaited(checkConnection());
      }
      rethrow;
    }
  }

  bool _accept(String api, int generation, int sequence) {
    if (generation != _generation || sequence < (_latest[api] ?? 0)) return false;
    _latest[api] = sequence;
    return true;
  }

  void setSlowCode(bool slow) {
    _slowCode = slow;
    _publish();
  }

  Future<void> checkConnection() async {
    final generation = _generation;
    final evidence = ++_evidence;
    bool online;
    try {
      online = await _connectivity.isOnline();
    } catch (_) {
      // A failed connectivity check cannot confirm disconnection.
      return;
    }
    if (generation != _generation || evidence != _evidence) return;
    _disconnected = !online;
    _publish();
  }

  void reset() {
    ++_generation;
    ++_evidence;
    _failed.clear();
    _latest.clear();
    _slowCode = false;
    _disconnected = false;
    _publish();
    if (_subscription != null) unawaited(checkConnection());
  }

  void _publish() {
    final next = _disconnected
        ? PaymentConnectionState.disconnected
        : _failed.isNotEmpty || _slowCode
            ? PaymentConnectionState.apiError
            : PaymentConnectionState.online;
    if (next == _state || _updates.isClosed) return;
    _state = next;
    _updates.add(next);
  }

  Future<void> dispose() async {
    ++_generation;
    await _subscription?.cancel();
    await _updates.close();
  }
}
