import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/application/account_history_refresh.dart';

void main() {
  test('unchanged balances issue no requests; one change gets only one follow-up', () async {
    var calls = 0;
    final service = AccountHistoryRefresh(loadHistory: () async { calls++; return false; });
    addTearDown(service.dispose);
    for (var i = 0; i < 5; i++) { await service.codeGenerated(balanceChanged: false); }
    expect(calls, 0);
    await service.codeGenerated(balanceChanged: true);
    expect(calls, 1);
    await service.codeGenerated(balanceChanged: false);
    expect(calls, 2);
    for (var i = 0; i < 5; i++) { await service.codeGenerated(balanceChanged: false); }
    expect(calls, 2);
  });
  test('new history avoids the follow-up', () async {
    var calls = 0;
    final service = AccountHistoryRefresh(loadHistory: () async { calls++; return true; });
    await service.codeGenerated(balanceChanged: true);
    await service.codeGenerated(balanceChanged: false);
    expect(calls, 1);
    service.dispose();
  });
  test('failed follow-up does not retry indefinitely', () async {
    var calls = 0;
    final service = AccountHistoryRefresh(loadHistory: () async { calls++; throw StateError('offline'); });
    await service.codeGenerated(balanceChanged: true);
    for (var i = 0; i < 10; i++) { await service.codeGenerated(balanceChanged: false); }
    expect(calls, 2);
    service.dispose();
  });
  test('manual refresh combines code change and payment-triggered refresh', () async {
    var calls = 0;
    final service = AccountHistoryRefresh(loadHistory: () async { calls++; return true; });
    service.hold();
    await service.codeGenerated(balanceChanged: true);
    await service.refresh(fresh: true);
    expect(calls, 0);
    await service.releaseAndRefresh();
    expect(calls, 1);
    service.dispose();
  });
  test('a new change during an old request gets one newer snapshot', () async {
    final first = Completer<bool>();
    var calls = 0;
    final service = AccountHistoryRefresh(loadHistory: () { calls++; return calls == 1 ? first.future : Future.value(true); });
    final pending = service.refresh();
    await Future<void>.delayed(Duration.zero);
    final changed = service.codeGenerated(balanceChanged: true);
    final duplicate = service.refresh();
    first.complete(false);
    await Future.wait([pending, changed, duplicate]);
    expect(calls, 2);
    service.dispose();
  });
  test('disposing during a load prevents further requests', () async {
    final first = Completer<bool>();
    var calls = 0;
    final service = AccountHistoryRefresh(loadHistory: () { calls++; return first.future; });
    final pending = service.codeGenerated(balanceChanged: true);
    await Future<void>.delayed(Duration.zero);
    service.dispose();
    first.complete(false);
    await pending;
    await service.codeGenerated(balanceChanged: false);
    expect(calls, 1);
  });
}
