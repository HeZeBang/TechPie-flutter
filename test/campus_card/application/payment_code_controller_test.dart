import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/application/payment_code_controller.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_payment_code_repository.dart';
import 'package:techpie/features/campus_card/domain/models/payment_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/payment_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart';

import '../support/fake_ecard_transport.dart';

/// The cadence the app ships with. The tests below advance time by this much to
/// reach a poll, so they follow the product decision instead of repeating it.
const pollInterval = PaymentCodeController.defaultPollInterval;

void main() {
  test('the shipped poll cadence stays deliberately slow', () {
    // While the pass is open the poll is the app's steady traffic. A change here
    // is a product decision, not a detail: it should be made on purpose.
    expect(PaymentCodeController.defaultPollInterval, const Duration(seconds: 5));
    expect(PaymentCodeController.defaultRefreshInterval,
        const Duration(seconds: 30),);
  });

  test('manual refresh joins an automatic generation already in flight', () {
    fakeAsync((async) {
      final repository = _RefreshAndPollRepository();
      final controller = PaymentCodeController(repository: repository);
      unawaited(controller.start());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(repository.generations, 2);
      var completed = 0;
      unawaited(controller.refresh().then((_) => completed++));
      unawaited(controller.refresh().then((_) => completed++));
      async.flushMicrotasks();
      expect(repository.generations, 2);
      repository.refresh.complete(_frame('fresh-code'));
      async.flushMicrotasks();
      expect(completed, 2);
      expect(controller.state.frame!.payCode, 'fresh-code');
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test('expired polling context regenerates once before surfacing failure', () {
    fakeAsync((async) {
      final repository = _PaymentRepository();
      repository.pollFailure = const AppFailure(FailureKind.authenticationExpired, 'expired',
          code: 'AUTH_PAYMENT_CONTEXT_EXPIRED',);
      final controller = PaymentCodeController(repository: repository);
      unawaited(controller.start());
      async.flushMicrotasks();
      async.elapse(pollInterval);
      async.flushMicrotasks();
      expect(repository.generateCalls, 2);
      expect(controller.state.phase, PaymentCodePhase.displaying);
      async.elapse(pollInterval);
      async.flushMicrotasks();
      expect(repository.generateCalls, 2);
      expect(controller.state.phase, PaymentCodePhase.switchingOffline);
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test('shows success for three seconds and then obtains a new code', () {
    fakeAsync((async) {
      final repository = _PaymentRepository();
      final controller = PaymentCodeController(repository: repository);
      unawaited(controller.start());
      async.flushMicrotasks();

      expect(repository.generateCalls, 1);
      expect(controller.state.phase, PaymentCodePhase.displaying);

      async.elapse(pollInterval);
      async.flushMicrotasks();
      expect(repository.pollCalls, 1);

      repository.nextPoll = PaymentCompleted(
        TransactionResult(
          amount: const MoneyFen(1200),
          confirmedLocallyAt: DateTime.utc(2026, 8, 31),
        ),
      );
      async.elapse(pollInterval);
      async.flushMicrotasks();

      expect(controller.state.phase, PaymentCodePhase.succeeded);
      expect(controller.state.result!.amount, const MoneyFen(1200));
      async.elapse(const Duration(milliseconds: 2999));
      async.flushMicrotasks();
      expect(repository.generateCalls, 1);
      expect(controller.state.phase, PaymentCodePhase.succeeded);

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(repository.generateCalls, 2);
      expect(controller.state.phase, PaymentCodePhase.displaying);
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test('manual refresh dismisses success and cancels its delayed refresh', () {
    fakeAsync((async) {
      final repository = _PaymentRepository(
        nextPoll: PaymentCompleted(
          TransactionResult(
            amount: const MoneyFen(100),
            confirmedLocallyAt: DateTime.utc(2026, 9, 2),
          ),
        ),
      );
      final controller = PaymentCodeController(
        repository: repository,
        refreshInterval: const Duration(minutes: 1),
        pollInterval: const Duration(seconds: 1),
      );
      unawaited(controller.start());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(controller.state.phase, PaymentCodePhase.succeeded);

      unawaited(controller.start());
      async.flushMicrotasks();
      expect(repository.generateCalls, 2);
      expect(controller.state.phase, PaymentCodePhase.displaying);

      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(repository.generateCalls, 2);
      controller.stop();
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test('the periodic refresh timer cannot interrupt success early', () {
    fakeAsync((async) {
      final repository = _PaymentRepository(
        nextPoll: PaymentCompleted(
          TransactionResult(
            amount: const MoneyFen(100),
            confirmedLocallyAt: DateTime.utc(2026, 9, 2),
          ),
        ),
      );
      final controller = PaymentCodeController(
        repository: repository,
        refreshInterval: const Duration(seconds: 2),
        pollInterval: const Duration(seconds: 1),
      );
      unawaited(controller.start());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(controller.state.phase, PaymentCodePhase.succeeded);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(controller.state.phase, PaymentCodePhase.succeeded);
      expect(repository.generateCalls, 1);
      controller.stop();
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test('ignores a late result for a code replaced at the refresh boundary', () {
    fakeAsync((async) {
      final late = Completer<PaymentCodePollResult>();
      final repository = _PaymentRepository(pollFuture: late.future);
      final controller = PaymentCodeController(repository: repository);
      unawaited(controller.start());
      async.flushMicrotasks();

      async.elapse(pollInterval);
      async.flushMicrotasks();
      expect(repository.pollCalls, 1);

      async.elapse(PaymentCodeController.defaultRefreshInterval - pollInterval);
      async.flushMicrotasks();
      expect(repository.generateCalls, 2);
      expect(controller.state.generation, 2);

      late.complete(
        PaymentCompleted(
          TransactionResult(
            amount: const MoneyFen(9999),
            confirmedLocallyAt: DateTime.utc(2026, 8, 31),
          ),
        ),
      );
      async.flushMicrotasks();

      expect(controller.state.generation, 2);
      expect(controller.state.phase, PaymentCodePhase.displaying);
      expect(controller.state.result, isNull);
      controller.stop();
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test('restart during an older refresh always starts the current epoch', () {
    fakeAsync((async) {
      final repository = _RestartDuringRefreshRepository();
      final controller = PaymentCodeController(repository: repository);

      unawaited(controller.start());
      async.flushMicrotasks();
      expect(repository.generateCalls, 1);
      expect(controller.state.phase, PaymentCodePhase.initializing);

      unawaited(controller.start());
      async.flushMicrotasks();
      expect(repository.generateCalls, 2);
      expect(controller.state.phase, PaymentCodePhase.displaying);
      expect(controller.state.frame!.payCode, 'current-code');

      repository.first.complete(_frame('stale-code'));
      async.flushMicrotasks();
      expect(controller.state.frame!.payCode, 'current-code');
      expect(controller.state.generation, 1);
      controller.stop();
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test(
    'exposes activation state and restarts only after explicit activation',
    () {
      fakeAsync((async) {
        final repository = _PaymentRepository(activationRequired: true);
        final controller = PaymentCodeController(repository: repository);
        unawaited(controller.start());
        async.flushMicrotasks();

        expect(controller.state.phase, PaymentCodePhase.activationRequired);
        expect(repository.activateCalls, 0);

        unawaited(controller.activateAndRestart());
        async.flushMicrotasks();
        expect(repository.activateCalls, 1);
        expect(controller.state.phase, PaymentCodePhase.displaying);
        controller.stop();
        unawaited(controller.dispose());
        async.flushMicrotasks();
      });
    },
  );

  test('restores brightness and stops work when the experience leaves', () {
    fakeAsync((async) {
      final brightness = InMemoryBrightnessPort(initial: 0.42);
      final repository = _PaymentRepository();
      final payment = PaymentCodeController(repository: repository);
      final experience = PaymentCodeExperienceController(
        payment: payment,
        brightness: brightness,
        maximizeBrightness: true,
      );
      unawaited(experience.enter());
      async.flushMicrotasks();
      expect(brightness.value, 1);

      unawaited(experience.leave());
      async.flushMicrotasks();
      expect(brightness.value, 0.42);
      expect(experience.state.phase, PaymentCodePhase.stopped);
      unawaited(experience.dispose());
      async.flushMicrotasks();
    });
  });

  test('starts payment networking even when brightness access hangs', () {
    fakeAsync((async) {
      final repository = _PaymentRepository();
      final experience = PaymentCodeExperienceController(
        payment: PaymentCodeController(repository: repository),
        brightness: _HangingBrightnessPort(),
        maximizeBrightness: true,
      );

      unawaited(experience.enter());
      async.flushMicrotasks();

      expect(repository.generateCalls, 1);
      expect(experience.state.phase, PaymentCodePhase.displaying);
      unawaited(experience.dispose());
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
    });
  });

  test('classifies connection failure separately from API content failure', () {
    fakeAsync((async) {
      final disconnected = PaymentCodeController(
        repository: _PaymentRepository(
          generationFailure: const AppFailure(FailureKind.network, 'offline'),
        ),
      );
      unawaited(disconnected.start());
      async.flushMicrotasks();
      expect(
        disconnected.state.connectionState,
        PaymentConnectionState.disconnected,
      );

      final apiError = PaymentCodeController(
        repository: _PaymentRepository(
          generationFailure: const AppFailure(
            FailureKind.protocol,
            'bad payload',
          ),
        ),
      );
      unawaited(apiError.start());
      async.flushMicrotasks();
      expect(apiError.state.connectionState, PaymentConnectionState.apiError);
    });
  });

  test('debug completion uses the normal success state', () {
    fakeAsync((async) {
      final controller = PaymentCodeController(
        repository: _PaymentRepository(),
      );

      controller.debugComplete();

      expect(controller.state.phase, PaymentCodePhase.succeeded);
      expect(controller.state.result!.amount, const MoneyFen(1280));
      expect(controller.state.result!.merchantName, '交易成功');
      controller.stop();
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test('connectivity loss stops polling and requests offline fallback', () {
    fakeAsync((async) {
      final repository = _PaymentRepository();
      final controller = PaymentCodeController(repository: repository);
      unawaited(controller.start());
      async.flushMicrotasks();

      controller.markDisconnected();
      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();

      expect(controller.state.phase, PaymentCodePhase.switchingOffline);
      expect(
        controller.state.connectionState,
        PaymentConnectionState.disconnected,
      );
      expect(repository.pollCalls, 0);
    });
  });

  test('refreshes the online code as soon as polling reports expiry', () {
    fakeAsync((async) {
      final repository = _PaymentRepository(
        nextPoll: const PaymentCodeExpired(),
      );
      final controller = PaymentCodeController(repository: repository);

      unawaited(controller.start());
      async.flushMicrotasks();
      async.elapse(pollInterval);
      async.flushMicrotasks();

      expect(repository.generateCalls, 2);
      expect(controller.state.phase, PaymentCodePhase.displaying);
      expect(controller.state.generation, 2);
    });
  });

  test('declined payment silently replaces the code and stays online', () {
    fakeAsync((async) {
      final repository = _PaymentRepository(
        nextPoll: const PaymentNotCompleted(reason: '密码错误'),
      );
      final controller = PaymentCodeController(repository: repository);
      final phases = <PaymentCodePhase>[];
      controller.states.listen((value) => phases.add(value.phase));
      unawaited(controller.start());
      async.flushMicrotasks();
      async.elapse(pollInterval);
      async.flushMicrotasks();

      expect(controller.state.phase, PaymentCodePhase.displaying);
      expect(repository.generateCalls, 2);
      expect(controller.state.message, isNull);
      expect(controller.state.result, isNull);
      expect(controller.state.connectionState, PaymentConnectionState.online);
      repository.nextPoll = const PaymentPending();
      async.elapse(pollInterval);
      async.flushMicrotasks();

      expect(repository.generateCalls, 2);
      expect(controller.state.phase, PaymentCodePhase.displaying);
      expect(controller.state.connectionState, PaymentConnectionState.online);
      expect(phases, isNot(contains(PaymentCodePhase.succeeded)));
      expect(phases, isNot(contains(PaymentCodePhase.failed)));
      expect(phases, isNot(contains(PaymentCodePhase.switchingOffline)));
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test('a late refresh cannot replace a silently renewed payment code', () {
    fakeAsync((async) {
      final repository = _RefreshAndPollRepository();
      final controller = PaymentCodeController(repository: repository);
      unawaited(controller.start());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(repository.generations, 2);

      repository.poll.complete(const PaymentNotCompleted(reason: '密码错误'));
      async.flushMicrotasks();
      repository.refresh.complete(_frame('superseded-refresh'));
      async.flushMicrotasks();

      expect(controller.state.phase, PaymentCodePhase.displaying);
      expect(controller.state.message, isNull);
      expect(controller.state.connectionState, PaymentConnectionState.online);
      expect(controller.state.frame!.payCode, 'code-3');
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test('repeated unused-code responses keep the same code until normal refresh',
      () {
    fakeAsync((async) {
      final transport = FakeEcardTransport()
        ..enqueue('POST', '/offlineCode/openVirtualcard', {
          'success': true,
          'data': {'code': '5638AABBCCDD', 'qrcode': ''},
        });
      for (var i = 0; i < 4; i++) {
        transport.enqueue('POST', '/virtualcard/queryOrderStatus', {
          'success': false,
          'data': {'status': 5, 'message': '支付失败，付款码未使用', 'txamt': 0},
        });
      }
      final controller = PaymentCodeController(
        repository: EcardPaymentCodeRepository(transport),
      );
      final states = <PaymentCodeViewState>[];
      controller.states.listen(states.add);
      unawaited(controller.start());
      async.flushMicrotasks();
      // Four polls: the same code must survive every one of them.
      async.elapse(pollInterval * 4);
      async.flushMicrotasks();

      expect(
        transport.requests
            .where((r) => r.path == '/offlineCode/openVirtualcard'),
        hasLength(1),
      );
      expect(
        transport.requests
            .where((r) => r.path == '/virtualcard/queryOrderStatus'),
        hasLength(4),
      );
      expect(controller.state.generation, 1);
      expect(controller.state.phase, PaymentCodePhase.displaying);
      expect(controller.state.connectionState, PaymentConnectionState.online);
      expect(states.every((s) => s.message == null), isTrue);
      expect(states.any((s) => s.phase == PaymentCodePhase.failed), isFalse);
      unawaited(controller.dispose());
      async.flushMicrotasks();
    });
  });

  test('default brightness preference never touches the platform setting', () {
    fakeAsync((async) {
      final brightness = _CountingBrightnessPort();
      final experience = PaymentCodeExperienceController(
        payment: PaymentCodeController(repository: _PaymentRepository()),
        brightness: brightness,
      );
      unawaited(experience.enter());
      async.flushMicrotasks();
      unawaited(experience.leave());
      async.flushMicrotasks();
      unawaited(experience.dispose());
      async.flushMicrotasks();

      expect(brightness.calls, isEmpty);
      expect(brightness.value, 0.42);
    });
  });

  test('brightness changes apply immediately without restarting payment', () {
    fakeAsync((async) {
      final brightness = _CountingBrightnessPort();
      final repository = _PaymentRepository();
      final experience = PaymentCodeExperienceController(
        payment: PaymentCodeController(repository: repository),
        brightness: brightness,
      );
      unawaited(experience.enter());
      async.flushMicrotasks();
      unawaited(experience.setMaximizeBrightness(true));
      async.flushMicrotasks();
      expect(brightness.value, 1);
      expect(repository.generateCalls, 1);

      unawaited(experience.setMaximizeBrightness(false));
      async.flushMicrotasks();
      expect(brightness.value, 0.42);
      expect(repository.generateCalls, 1);
      expect(brightness.calls, ['current', 'set', 'restore']);
      unawaited(experience.dispose());
      async.flushMicrotasks();
      expect(brightness.calls, ['current', 'set', 'restore']);
    });
  });

  test('offline code visibility honors the optional brightness setting', () {
    fakeAsync((async) {
      final brightness = _CountingBrightnessPort();
      final repository = _PaymentRepository();
      final experience = PaymentCodeExperienceController(
        payment: PaymentCodeController(repository: repository),
        brightness: brightness,
        maximizeBrightness: true,
      );
      unawaited(experience.enter(online: false));
      async.flushMicrotasks();
      expect(brightness.value, 1);
      expect(repository.generateCalls, 0);
      unawaited(experience.leave());
      async.flushMicrotasks();
      expect(brightness.value, 0.42);
      unawaited(experience.dispose());
      async.flushMicrotasks();
    });
  });

  test('a late platform brightness write is undone after leaving', () {
    fakeAsync((async) {
      final brightness = _DelayedBrightnessPort();
      final experience = PaymentCodeExperienceController(
        payment: PaymentCodeController(repository: _PaymentRepository()),
        brightness: brightness,
        maximizeBrightness: true,
      );
      unawaited(experience.enter());
      async.flushMicrotasks();
      unawaited(experience.leave());
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      brightness.pendingSet.complete();
      async.flushMicrotasks();

      expect(brightness.value, 0.42);
      unawaited(experience.dispose());
      async.flushMicrotasks();
    });
  });
}

class _CountingBrightnessPort implements BrightnessPort {
  final calls = <String>[];
  double value = 0.42;

  @override
  Future<double> current() async {
    calls.add('current');
    return value;
  }

  @override
  Future<void> set(double brightness) async {
    calls.add('set');
    value = brightness;
  }

  @override
  Future<void> restore() async {
    calls.add('restore');
    value = 0.42;
  }
}

final class _DelayedBrightnessPort extends _CountingBrightnessPort {
  final pendingSet = Completer<void>();

  @override
  Future<void> set(double brightness) async {
    await pendingSet.future;
    await super.set(brightness);
  }
}

final class _RefreshAndPollRepository implements PaymentCodeRepository {
  final refresh = Completer<PaymentCodeFrame>();
  final poll = Completer<PaymentCodePollResult>();
  int generations = 0;

  @override
  Future<void> activateOnlineCode() async {}

  @override
  Future<PaymentCodeFrame> generateOnlineCode() {
    generations++;
    return generations == 2
        ? refresh.future
        : Future.value(_frame('code-$generations'));
  }

  @override
  Future<PaymentCodePollResult> pollTransaction(String payCode, {PaymentRequestContext? context}) => poll.future;
}

final class _PaymentRepository implements PaymentCodeRepository {
  _PaymentRepository({
    this.activationRequired = false,
    this.pollFuture,
    this.generationFailure,
    PaymentCodePollResult? nextPoll,
  }) : nextPoll = nextPoll ?? const PaymentPending();

  bool activationRequired;
  final Future<PaymentCodePollResult>? pollFuture;
  AppFailure? pollFailure;
  final AppFailure? generationFailure;
  PaymentCodePollResult nextPoll;
  int generateCalls = 0;
  int pollCalls = 0;
  int activateCalls = 0;

  @override
  Future<void> activateOnlineCode() async {
    activateCalls += 1;
    activationRequired = false;
  }

  @override
  Future<PaymentCodeFrame> generateOnlineCode() async {
    if (generationFailure case final failure?) throw failure;
    if (activationRequired) {
      throw const AppFailure(
        FailureKind.unavailable,
        'not activated',
        code: 'PAYMENT_CODE_NOT_ACTIVATED',
      );
    }
    generateCalls += 1;
    return PaymentCodeFrame(
      payCode: 'pay-$generateCalls',
      rawQrCode: 'qr-$generateCalls',
      qrPayload: 'qr-$generateCalls',
      offlineAllowed: true,
      generatedAt: DateTime.utc(2026, 8, 31),
    );
  }

  @override
  Future<PaymentCodePollResult> pollTransaction(String payCode, {PaymentRequestContext? context}) {
    pollCalls += 1;
    if (pollFailure != null) return Future.error(pollFailure!);
    return pollFuture ?? Future.value(nextPoll);
  }
}

final class _HangingBrightnessPort implements BrightnessPort {
  final Completer<double> _current = Completer<double>();
  final Completer<void> _set = Completer<void>();
  final Completer<void> _restore = Completer<void>();

  @override
  Future<double> current() => _current.future;

  @override
  Future<void> set(double value) => _set.future;

  @override
  Future<void> restore() => _restore.future;
}

final class _RestartDuringRefreshRepository implements PaymentCodeRepository {
  final Completer<PaymentCodeFrame> first = Completer<PaymentCodeFrame>();
  int generateCalls = 0;

  @override
  Future<void> activateOnlineCode() async {}

  @override
  Future<PaymentCodeFrame> generateOnlineCode() async {
    generateCalls++;
    if (generateCalls == 1) return first.future;
    return _frame('current-code');
  }

  @override
  Future<PaymentCodePollResult> pollTransaction(String payCode, {PaymentRequestContext? context}) async =>
      const PaymentPending();
}

PaymentCodeFrame _frame(String value) => PaymentCodeFrame(
      payCode: value,
      rawQrCode: value,
      qrPayload: value,
      offlineAllowed: true,
      generatedAt: DateTime.utc(2026, 8, 31),
    );
