import 'dart:async';

import '../core/errors/app_failure.dart';
import '../domain/models/payment_models.dart';
import '../domain/money_fen.dart';
import '../domain/ports/payment_ports.dart';
import '../domain/ports/platform_ports.dart';

final class PaymentCodeController {
  PaymentCodeController({
    required PaymentCodeRepository repository,
    this.refreshInterval = defaultRefreshInterval,
    this.pollInterval = defaultPollInterval,
    this.successDisplayDuration = const Duration(seconds: 3),
  }) : _repository = repository;

  /// How long a code is shown before it is replaced. The pass counts down from
  /// the same value, so a longer one would leave an expired code on screen.
  static const defaultRefreshInterval = Duration(seconds: 30);

  /// How often a displayed code asks whether it has been paid. This is the app's
  /// steady cost while the pass is open, so it is deliberately not the fastest
  /// answer the terminal would allow.
  static const defaultPollInterval = Duration(seconds: 5);

  final PaymentCodeRepository _repository;
  final Duration refreshInterval;
  final Duration pollInterval;
  final Duration successDisplayDuration;
  final StreamController<PaymentCodeViewState> _states =
      StreamController<PaymentCodeViewState>.broadcast(sync: true);

  PaymentCodeViewState _state = const PaymentCodeViewState.idle();
  Timer? _refreshTimer;
  Timer? _pollTimer;
  Timer? _successTimer;
  int? _refreshEpochInFlight;
  Future<bool>? _activeRefresh;
  bool _pollInFlight = false;
  int _epoch = 0;
  bool _retriedSession = false;
  bool _disposed = false;

  PaymentCodeViewState get state => _state;
  Stream<PaymentCodeViewState> get states => _states.stream;

  Future<void> start({bool resetSessionRetry = true}) async {
    _ensureActive();
    if (resetSessionRetry) _retriedSession = false;
    final epoch = ++_epoch;
    _cancelTimers();
    _emit(
      PaymentCodeViewState(
        phase: PaymentCodePhase.initializing,
        generation: _state.generation,
        connectionState: _state.connectionState,
        requestLatency: _state.requestLatency,
      ),
    );
    final ready = await _refresh(epoch, initial: true);
    if (!ready || !_isCurrent(epoch)) return;
    _refreshTimer = Timer.periodic(refreshInterval, (_) => _refresh(epoch));
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll(epoch));
  }

  Future<void> activateAndRestart() async {
    _ensureActive();
    final epoch = ++_epoch;
    _cancelTimers();
    _emit(
      PaymentCodeViewState(
        phase: PaymentCodePhase.initializing,
        generation: _state.generation,
        message: '正在开通付款码…',
      ),
    );
    try {
      await _repository.activateOnlineCode();
    } on AppFailure catch (failure) {
      if (_isCurrent(epoch)) _emitFailure(failure);
      return;
    }
    if (_isCurrent(epoch)) await start();
  }

  Future<void> refresh() async {
    _ensureActive();
    final active = _activeRefresh;
    if (active != null && _refreshEpochInFlight == _epoch) {
      await active;
    } else {
      await start();
    }
  }

  Future<bool> _refresh(int epoch, {bool initial = false}) {
    if (_refreshEpochInFlight == epoch && _activeRefresh != null) return _activeRefresh!;
    late final Future<bool> operation;
    operation = _performRefresh(epoch, initial: initial).whenComplete(() {
      if (identical(_activeRefresh, operation)) _activeRefresh = null;
    });
    _activeRefresh = operation;
    return operation;
  }

  Future<bool> _performRefresh(int epoch, {bool initial = false}) async {
    if (!_isCurrent(epoch) || _refreshEpochInFlight == epoch) return false;
    _refreshEpochInFlight = epoch;
    if (!initial) {
      _emit(
        _state.copyWith(phase: PaymentCodePhase.refreshing, clearMessage: true),
      );
    }
    final stopwatch = Stopwatch()..start();
    try {
      final frame = await _repository.generateOnlineCode();
      stopwatch.stop();
      if (!_isCurrent(epoch)) return false;
      _emit(
        PaymentCodeViewState(
          phase: PaymentCodePhase.displaying,
          generation: _state.generation + 1,
          frame: frame,
          connectionState: PaymentConnectionState.online,
          requestLatency: stopwatch.elapsed,
        ),
      );
      return true;
    } on AppFailure catch (failure) {
      stopwatch.stop();
      if (!_isCurrent(epoch)) return false;
      _cancelTimers();
      if (failure.code == 'PAYMENT_CODE_NOT_ACTIVATED') {
        _emit(
          PaymentCodeViewState(
            phase: PaymentCodePhase.activationRequired,
            generation: _state.generation,
            message: failure.safeMessage,
            connectionState: _connectionStateFor(failure),
            requestLatency: stopwatch.elapsed,
          ),
        );
      } else {
        _emitFailure(failure, latency: stopwatch.elapsed);
      }
      return false;
    } finally {
      if (_refreshEpochInFlight == epoch) _refreshEpochInFlight = null;
    }
  }

  Future<void> _poll(int epoch) async {
    final frame = _state.frame;
    final generation = _state.generation;
    if (!_isCurrent(epoch) || _pollInFlight || frame == null) return;
    _pollInFlight = true;
    _emit(_state.copyWith(phase: PaymentCodePhase.polling));
    try {
      final result = await _repository.pollTransaction(frame.payCode,
          context: frame.requestContext,);
      if (!_isCurrent(epoch) || _state.generation != generation) return;
      _retriedSession = false;
      switch (result) {
        case PaymentPending():
          _emit(_state.copyWith(phase: PaymentCodePhase.displaying));
        case PaymentCodeExpired():
          await _refresh(epoch);
        case PaymentCompleted(:final result):
          _completePayment(result);
        case PaymentNotCompleted():
          // Retire the consumed/rejected code without a user-facing error.
          await start();
        case PaymentShouldUseOffline(:final reason):
          _cancelTimers();
          _emit(
            _state.copyWith(
              phase: PaymentCodePhase.switchingOffline,
              message: reason,
              connectionState: PaymentConnectionState.apiError,
            ),
          );
      }
    } on AppFailure catch (failure) {
      if (_isCurrent(epoch) && _state.generation == generation) {
        if (failure.isRecoverableSessionFailure && !_retriedSession) {
          _retriedSession = true;
          await start(resetSessionRetry: false);
          return;
        }
        _cancelTimers();
        _emit(
          _state.copyWith(
            phase: PaymentCodePhase.switchingOffline,
            message: failure.safeMessage,
            connectionState: _connectionStateFor(failure),
          ),
        );
      }
    } finally {
      _pollInFlight = false;
    }
  }

  void stop() {
    if (_disposed) return;
    ++_epoch;
    _cancelTimers();
    _emit(_state.copyWith(phase: PaymentCodePhase.stopped));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _cancelTimers();
    await _states.close();
  }

  bool _isCurrent(int epoch) => !_disposed && epoch == _epoch;

  void _cancelTimers() {
    _refreshTimer?.cancel();
    _pollTimer?.cancel();
    _refreshTimer = null;
    _pollTimer = null;
    _successTimer?.cancel();
    _successTimer = null;
  }

  void debugComplete() {
    if (_disposed) return;
    _completePayment(
      TransactionResult(
        amount: const MoneyFen(1280),
        confirmedLocallyAt: DateTime.now().toUtc(),
        merchantName: '交易成功',
        tradeAt: DateTime.now().toUtc(),
        orderId: 'DEBUG-PAYMENT-SUCCESS',
      ),
    );
  }

  void _completePayment(TransactionResult result) {
    final epoch = ++_epoch;
    final generation = _state.generation;
    _cancelTimers();
    _emit(
      PaymentCodeViewState(
        phase: PaymentCodePhase.succeeded,
        generation: generation,
        frame: _state.frame,
        result: result,
        connectionState: PaymentConnectionState.online,
        requestLatency: _state.requestLatency,
      ),
    );
    _successTimer = Timer(successDisplayDuration, () {
      if (!_isCurrent(epoch) ||
          _state.phase != PaymentCodePhase.succeeded ||
          _state.generation != generation) {
        return;
      }
      unawaited(start());
    });
  }

  void markDisconnected() {
    if (_disposed) return;
    _cancelTimers();
    _emit(
      _state.copyWith(
        phase: PaymentCodePhase.switchingOffline,
        message: '当前网络连接已断开。',
        connectionState: PaymentConnectionState.disconnected,
      ),
    );
  }

  void _emitFailure(AppFailure failure, {Duration? latency}) {
    _emit(
      _state.copyWith(
        phase: PaymentCodePhase.failed,
        message: failure.safeMessage,
        connectionState: _connectionStateFor(failure),
        requestLatency: latency,
      ),
    );
  }

  PaymentConnectionState _connectionStateFor(AppFailure failure) =>
      failure.kind == FailureKind.network || failure.kind == FailureKind.timeout
          ? PaymentConnectionState.disconnected
          : PaymentConnectionState.apiError;

  void _emit(PaymentCodeViewState value) {
    if (_disposed) return;
    _state = value;
    _states.add(value);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('PaymentCodeController is disposed');
  }
}

final class PaymentCodeExperienceController {
  PaymentCodeExperienceController({
    required PaymentCodeController payment,
    required BrightnessPort brightness,
    bool maximizeBrightness = false,
  })  : _payment = payment,
        _brightness = brightness,
        _maximizeBrightness = maximizeBrightness;

  final PaymentCodeController _payment;
  final BrightnessPort _brightness;
  bool _entered = false;
  bool _online = false;
  bool _maximizeBrightness;
  bool _brightnessTouched = false;
  int _brightnessEpoch = 0;
  Future<void> _brightnessUpdates = Future<void>.value();

  PaymentCodeViewState get state => _payment.state;
  Stream<PaymentCodeViewState> get states => _payment.states;

  Future<void> enter({bool online = true}) async {
    if (_entered && _online == online) return;
    if (!_entered) {
      _entered = true;
      unawaited(_updateBrightness());
    }
    _online = online;
    try {
      if (online) {
        await _payment.start();
      } else {
        _payment.stop();
      }
    } catch (_) {
      await leave();
      rethrow;
    }
  }

  Future<void> restart() async {
    if (!_entered) return enter();
    _online = true;
    await _payment.start();
  }

  Future<void> setMaximizeBrightness(bool enabled) async {
    if (_maximizeBrightness == enabled) return;
    _maximizeBrightness = enabled;
    await _updateBrightness();
  }

  Future<void> refresh() => _payment.refresh();

  Future<void> activateAndRestart() => _payment.activateAndRestart();

  void debugComplete() => _payment.debugComplete();

  void markDisconnected() => _payment.markDisconnected();

  Future<void> leave() async {
    if (!_entered) return;
    _entered = false;
    _online = false;
    _payment.stop();
    await _updateBrightness();
  }

  Future<void> _updateBrightness() {
    final epoch = ++_brightnessEpoch;
    return _brightnessUpdates = _brightnessUpdates.then((_) async {
      if (epoch != _brightnessEpoch) return;
      try {
        if (_entered && _maximizeBrightness) {
          await _brightness.current().timeout(const Duration(seconds: 2));
          if (epoch != _brightnessEpoch) return;
          _brightnessTouched = true;
          final pending = _brightness.set(1);
          unawaited(
            pending.then<void>(
              (_) {
                // Platform calls may finish after a timeout or after leaving.
                if (!_entered || !_maximizeBrightness) {
                  _brightnessTouched = true;
                  unawaited(_updateBrightness());
                }
              },
              onError: (Object _) {},
            ),
          );
          await pending.timeout(const Duration(seconds: 2));
        } else if (_brightnessTouched) {
          await _brightness.restore().timeout(const Duration(seconds: 2));
          _brightnessTouched = false;
        }
      } catch (_) {
        // Optional brightness changes never interrupt payment or navigation.
      }
    });
  }

  Future<void> dispose() async {
    await leave();
    await _payment.dispose();
  }
}
