import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/application/campus_network_status.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/domain/models/payment_models.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart';

const _serverError = AppFailure(FailureKind.server, 'synthetic service error');
const _timeout = AppFailure(FailureKind.timeout, 'synthetic timeout');

void main() {
  late _Connectivity connectivity;
  late CampusNetworkStatus status;
  setUp(() async {
    connectivity = _Connectivity();
    status = CampusNetworkStatus(connectivity: connectivity);
    status.start();
    await pumpEventQueue();
  });
  tearDown(() => status.dispose());

  test('success only clears the corresponding interface failure', () async {
    await expectLater(
        status.track('orders', () async => throw _serverError), throwsA(_serverError),);
    await status.track('account', () async => 1);
    expect(status.state, PaymentConnectionState.apiError);
    await status.track('account', () async => {'success': false});
    await status.track('orders', () async => 1);
    expect(status.state, PaymentConnectionState.apiError);
    await status.track('account', () async => 1);
    expect(status.state, PaymentConnectionState.online);
  });

  test('timeouts only become grey after a connectivity check confirms no connection', () async {
    await expectLater(status.track('orders', () async => throw _timeout), throwsA(_timeout));
    await pumpEventQueue();
    expect(status.state, PaymentConnectionState.apiError);
    connectivity.query = () async => false;
    await expectLater(status.track('orders', () async => throw _timeout), throwsA(_timeout));
    await pumpEventQueue();
    expect(status.state, PaymentConnectionState.disconnected);
    await status.track('orders', () async => 1);
    expect(status.state, PaymentConnectionState.online);
  });

  test('the latest connectivity check wins when checks complete out of order', () async {
    final old = Completer<bool>();
    connectivity.query = () => old.future;
    final pending = status.checkConnection();
    connectivity.query = () async => true;
    await status.checkConnection();
    old.complete(false);
    await pending;
    expect(status.state, PaymentConnectionState.online);
  });

  test('previous-account results cannot change the new account network status', () async {
    final oldAccount = Completer<void>();
    final rejected =
        expectLater(status.track('account', () => oldAccount.future), throwsA(_timeout));
    status.reset();
    oldAccount.completeError(_timeout);
    await rejected;
    await pumpEventQueue();
    expect(status.state, PaymentConnectionState.online);
  });
}

final class _Connectivity implements ConnectivityPort {
  Future<bool> Function() query = () async => true;
  @override
  Future<bool> isOnline() => query();
  @override
  Stream<bool> get changes => const Stream.empty();
}
