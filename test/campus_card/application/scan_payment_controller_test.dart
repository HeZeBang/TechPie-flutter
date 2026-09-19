import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/application/scan_payment_controller.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/domain/models/payment_models.dart';
import 'package:techpie/features/campus_card/domain/models/scan_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/payment_ports.dart';

void main() {
  for (final notSent in [true, false]) {
    test('expired scan context only rebuilds when not sent: $notSent', () async {
      final repository = _ExpiredScanRepository(notSent);
      final controller = ScanPaymentController(repository: repository);
      addTearDown(controller.dispose);
      await controller.submitCode('RAW%2F+SCAN');
      await controller.submitPassword('123456');
      expect(repository.requests.length, notSent ? 3 : 2);
      expect(controller.state.phase, notSent
          ? ScanFlowPhase.passwordRequired : ScanFlowPhase.failed,);
      if (notSent) {
        expect(repository.requests.last, ('RAW%2F+SCAN', null));
        expect(controller.state.pendingServerQrCode, 'FRESH');
      }
    });
  }

  test(
      'reset discards an in-flight success instead of reviving a cancelled scan',
      () async {
    final pending = Completer<ScanPaymentResult>();
    final repository = _PendingScanRepository(pending);
    final controller = ScanPaymentController(repository: repository);
    final submitted = controller.submitCode('QR');
    controller.reset();
    pending.complete(const ScanSucceeded(kind: ScanSuccessKind.payment));
    await submitted;
    expect(controller.state.phase, ScanFlowPhase.idle);
    await controller.dispose();
  });

  test(
    'retries with the exact server-returned QR code and six-digit password',
    () async {
      final repository = _ScanRepository();
      final controller = ScanPaymentController(
        repository: repository,
        clock: Clock.fixed(DateTime.utc(2026, 8, 31, 12)),
      );

      await controller.submitCode('CLIENT-SCANNED-QR');
      expect(controller.state.phase, ScanFlowPhase.passwordRequired);
      expect(controller.state.pendingServerQrCode, 'SERVER-RETURNED-QR');

      await controller.submitPassword('123');
      expect(repository.requests, hasLength(1));
      expect(controller.state.phase, ScanFlowPhase.passwordRequired);

      await controller.submitPassword('246810');
      expect(repository.requests, hasLength(2));
      expect(repository.requests.last.$1, 'SERVER-RETURNED-QR');
      expect(repository.requests.last.$2, '246810');
      expect(controller.state.phase, ScanFlowPhase.succeeded);
    },
  );

  test('keeps server failure text and permits reset', () async {
    final repository = _ScanRepository(fail: true);
    final controller = ScanPaymentController(repository: repository);

    await controller.submitCode('QR');
    expect(controller.state.phase, ScanFlowPhase.failed);
    expect(controller.state.message, '演示服务拒绝');
    controller.reset();
    expect(controller.state.phase, ScanFlowPhase.idle);
  });

  test(
    'debug scan exercises password and success presentation states',
    () async {
      final paidAt = DateTime.utc(2026, 9, 13, 14, 40, 31);
      final repository = _ScanRepository();
      final controller = ScanPaymentController(repository: repository, clock: Clock.fixed(paidAt));
      addTearDown(controller.dispose);

      await controller.debugSubmitCode('ANY-QR-CODE');
      expect(controller.state.phase, ScanFlowPhase.passwordRequired);

      await controller.debugSubmitPassword('123456');
      expect(controller.state.phase, ScanFlowPhase.succeeded);
      final receipt = controller.state.success!;
      expect(receipt.paidAt, paidAt);
      expect(receipt.authorizationCode, 'DEMO-A1B2');
      expect(receipt.transactionId, 'DEBUG-SCAN-${paidAt.millisecondsSinceEpoch}');
      expect(receipt.terminalCode, 'DEMO-0305');
      expect(receipt.transactionCode, '1829');
      expect(receipt.balance, const MoneyFen(9119));
      expect(repository.requests, isEmpty);
      expect(controller.state.success!.amount, const MoneyFen(880));
    },
  );
}

final class _ScanRepository implements ScanPaymentRepository {
  _ScanRepository({this.fail = false});
  final bool fail;
  final List<(String, String?)> requests = [];

  @override
  Future<ScanPaymentResult> submit({
    required String qrCode,
    required DateTime payTime,
    String? password,
    PaymentRequestContext? context,
  }) async {
    requests.add((qrCode, password));
    if (fail) return const ScanFailed(message: '演示服务拒绝');
    if (password == null) {
      return const ScanPasswordRequired(serverQrCode: 'SERVER-RETURNED-QR');
    }
    return const ScanSucceeded(kind: ScanSuccessKind.payment);
  }
}

final class _PendingScanRepository implements ScanPaymentRepository {
  _PendingScanRepository(this.pending);
  final Completer<ScanPaymentResult> pending;
  @override
  Future<ScanPaymentResult> submit({
    required String qrCode,
    required DateTime payTime,
    String? password,
    PaymentRequestContext? context,
  }) =>
      pending.future;
}

final class _ExpiredScanRepository implements ScanPaymentRepository {
  _ExpiredScanRepository(this.notSent);
  final bool notSent;
  final List<(String, String?)> requests = [];
  @override
  Future<ScanPaymentResult> submit({required String qrCode,
    required DateTime payTime, String? password, PaymentRequestContext? context,}) async {
    requests.add((qrCode, password));
    if (password != null) {
      throw AppFailure(FailureKind.authenticationExpired, 'expired',
        code: 'AUTH_PAYMENT_CONTEXT_EXPIRED', requestNotSent: notSent,);
    }
    return ScanPasswordRequired(serverQrCode: requests.length == 1 ? 'OLD' : 'FRESH');
  }
}
