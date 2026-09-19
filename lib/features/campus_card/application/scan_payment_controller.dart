import 'dart:async';

import 'package:clock/clock.dart';

import '../core/errors/app_failure.dart';
import '../domain/models/scan_models.dart';
import '../domain/money_fen.dart';
import '../domain/ports/payment_ports.dart';

final class ScanPaymentController {
  ScanPaymentController({
    required ScanPaymentRepository repository,
    Clock? clock,
  })  : _repository = repository,
        _clock = clock ?? const Clock();

  final ScanPaymentRepository _repository;
  final Clock _clock;
  final StreamController<ScanFlowState> _states =
      StreamController<ScanFlowState>.broadcast(sync: true);
  ScanFlowState _state = const ScanFlowState.idle();
  bool _submitting = false;
  bool _disposed = false;
  int _epoch = 0;
  String? _originalQrCode;

  ScanFlowState get state => _state;
  Stream<ScanFlowState> get states => _states.stream;

  Future<void> submitCode(String rawQrCode) async {
    if (rawQrCode.trim().isEmpty || _disposed || _submitting) return;
    _originalQrCode = rawQrCode;
    await _submit(rawQrCode, password: null);
  }

  Future<void> submitPassword(String password) async {
    if (!RegExp(r'^\d{6}$').hasMatch(password)) {
      _emit(
        ScanFlowState(
          phase: ScanFlowPhase.passwordRequired,
          pendingServerQrCode: _state.pendingServerQrCode,
          pendingContext: _state.pendingContext,
          message: '请输入 6 位数字消费密码。',
        ),
      );
      return;
    }
    final serverQrCode = _state.pendingServerQrCode;
    if (serverQrCode == null) {
      _emit(
        const ScanFlowState(
          phase: ScanFlowPhase.failed,
          message: '当前没有等待密码确认的交易。',
        ),
      );
      return;
    }
    await _submit(serverQrCode, password: password);
  }

  Future<void> debugSubmitCode(String rawQrCode) async {
    if (rawQrCode.trim().isEmpty || _disposed) return;
    _emit(
      ScanFlowState(
        phase: ScanFlowPhase.passwordRequired,
        pendingServerQrCode: rawQrCode,
        message: '调试支付请求',
      ),
    );
  }

  Future<void> debugSubmitPassword(String password) async {
    if (!RegExp(r'^\d{6}$').hasMatch(password)) {
      _emit(
        ScanFlowState(
          phase: ScanFlowPhase.passwordRequired,
          pendingServerQrCode: _state.pendingServerQrCode,
          pendingContext: _state.pendingContext,
          message: '请输入 6 位数字消费密码。',
        ),
      );
      return;
    }
    final paidAt = _clock.now().toUtc();
    _emit(
      ScanFlowState(
        phase: ScanFlowPhase.succeeded,
        success: ScanSucceeded(
          kind: ScanSuccessKind.payment,
          amount: const MoneyFen(880),
          fee: MoneyFen.zero,
          balance: const MoneyFen(9119),
          message: '调试模式：模拟扫码支付成功',
          paidAt: paidAt,
          authorizationCode: 'DEMO-A1B2',
          transactionId: 'DEBUG-SCAN-${paidAt.millisecondsSinceEpoch}',
          terminalCode: 'DEMO-0305',
          transactionCode: '1829',
        ),
      ),
    );
  }

  Future<void> _submit(String qrCode, {required String? password}) async {
    if (_disposed || _submitting) return;
    _submitting = true;
    final epoch = ++_epoch;
    final context = password == null ? null : _state.pendingContext;
    _emit(const ScanFlowState(phase: ScanFlowPhase.submitting));
    try {
      ScanPaymentResult result;
      try {
        result = await _repository.submit(
          qrCode: qrCode,
          payTime: _clock.now(),
          password: password,
          context: context,
        );
      } on AppFailure catch (failure) {
        if (_disposed || epoch != _epoch) return;
        if (password == null ||
            !failure.requestNotSent ||
            failure.code != 'AUTH_PAYMENT_CONTEXT_EXPIRED' ||
            _originalQrCode == null) {
          rethrow;
        }
        // The password request never left this device. Rebuild the challenge
        // from the original scan once; never reuse the stale server challenge
        // or replay a payment whose result is unknown.
        result = await _repository.submit(
            qrCode: _originalQrCode!, payTime: _clock.now(),);
      }
      if (_disposed || epoch != _epoch) return;
      switch (result) {
        case ScanPasswordRequired(:final serverQrCode, :final context):
          _emit(
            ScanFlowState(
              phase: ScanFlowPhase.passwordRequired,
              pendingServerQrCode: serverQrCode,
              pendingContext: context,
            ),
          );
        case ScanSucceeded():
          _emit(ScanFlowState(phase: ScanFlowPhase.succeeded, success: result));
        case ScanFailed(:final message):
          _emit(ScanFlowState(phase: ScanFlowPhase.failed, message: message));
      }
    } on AppFailure catch (failure) {
      if (_disposed || epoch != _epoch) return;
      _emit(
        ScanFlowState(
          phase: ScanFlowPhase.failed,
          message: failure.safeMessage,
        ),
      );
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      _emit(
        const ScanFlowState(
          phase: ScanFlowPhase.failed,
          message: '扫码请求失败，请重试。',
        ),
      );
    } finally {
      _submitting = false;
    }
  }

  void reset() {
    _originalQrCode = null;
    _epoch++;
    _emit(const ScanFlowState.idle());
  }

  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    await _states.close();
  }

  void _emit(ScanFlowState state) {
    if (_disposed) return;
    _state = state;
    _states.add(state);
  }
}
