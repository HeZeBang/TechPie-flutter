import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_scan_payment_repository.dart';
import 'package:techpie/features/campus_card/domain/models/bill_models.dart';
import 'package:techpie/features/campus_card/domain/models/card_models.dart';
import 'package:techpie/features/campus_card/domain/models/scan_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/bill_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/card_ports.dart';
import '../support/fake_ecard_transport.dart';
import '../support/scan_payment_receipt.dart';

void main() {
  for (final scenario in [(cached: true, fails: false), (cached: true, fails: true), (cached: false, fails: false)]) {
    final refreshFails = scenario.fails;
    test(
        'success survives slow refresh and scanner close (cached=${scenario.cached}, failure=$refreshFails)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final base = await buildDemoRuntime();
      addTearDown(base.dispose);
      final cards = _Cards(cached: scenario.cached);
      final history = _History();
      final transport = FakeEcardTransport()
        ..enqueue('POST', '/scan/scanningResult', scanPaymentReceipt);
      final runtime = AppRuntime(
          environment: base.environment,
          capabilities: base.capabilities,
          auth: base.auth,
          cards: cards,
          paymentCodes: base.paymentCodes,
          scanPayments: EcardScanPaymentRepository(transport),
          transactions: history,
          securitySettings: base.securitySettings,
          offlinePayments: base.offlinePayments,
          brightness: base.brightness,
          connectivity: base.connectivity,
          lifecycle: base.lifecycle,
          feedback: base.feedback,);
      final container = ProviderContainer(
          overrides: [appRuntimeProvider.overrideWithValue(runtime)],);
      addTearDown(container.dispose);
      const range = (begin: null, end: null);
      if (scenario.cached) {
        await container.read(cardControllerProvider.future);
      } else {
        container.read(cardControllerProvider);
        await Future<void>.delayed(Duration.zero);
      }
      await container.read(transactionFeedProvider(range).future);
      final scanSubscription =
          container.listen(scanPaymentControllerProvider, (_, __) {});
      await container
          .read(scanPaymentControllerProvider.notifier)
          .submitCode('TEST');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(scanPaymentControllerProvider).phase,
          ScanFlowPhase.succeeded,);
      expect(container.read(scanPaymentControllerProvider).success!.amount,
          const MoneyFen(617),);
      expect(cards.requests, hasLength(2));
      expect(history.calls, 2);
      // Simulate Done while balance and history are still loading.
      container.read(scanPaymentControllerProvider.notifier).reset();
      scanSubscription.close();
      if (refreshFails) {
        cards.requests[1].completeError(StateError('refresh unavailable'));
        history.pending.completeError(StateError('history unavailable'));
      } else {
        cards.requests[1].complete(_card(9383));
        history.pending.complete(TransactionPage(items: [
          TransactionRecord(
              id: 'new-payment',
              occurredAt: DateTime.utc(2026, 9, 13),
              title: 'payment',
              amount: const MoneyFen(617),
              kind: TransactionKind.consumption,),
        ], hasMore: false,),);
      }
      await Future<void>.delayed(Duration.zero);
      // The older startup balance arrives last and must not overwrite payment refresh.
      cards.requests[0].complete(_card(10000));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(cardControllerProvider).valueOrNull!.balance,
          MoneyFen(refreshFails ? 10000 : 9383),);
      if (!refreshFails) {
        expect(
            container
                .read(transactionFeedProvider(range))
                .valueOrNull!
                .items
                .single
                .id,
            'new-payment',);
      }
      expect(transport.requests, hasLength(1),
          reason: 'refresh must never replay the payment',);
    });
  }

  test('non-payment scan success does not refresh balance or transactions',
      () async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final cards = _Cards();
    final history = _History();
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/scan/scanningResult', {
        'success': true,
        'issuccess': '1',
        'resultData': {'type': 'scj'},
      });
    final runtime = AppRuntime(
        environment: base.environment,
        capabilities: base.capabilities,
        auth: base.auth,
        cards: cards,
        paymentCodes: base.paymentCodes,
        scanPayments: EcardScanPaymentRepository(transport),
        transactions: history,
        securitySettings: base.securitySettings,
        offlinePayments: base.offlinePayments,
        brightness: base.brightness,
        connectivity: base.connectivity,
        lifecycle: base.lifecycle,
        feedback: base.feedback,);
    final container = ProviderContainer(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],);
    addTearDown(container.dispose);
    final sub = container.listen(scanPaymentControllerProvider, (_, __) {});
    addTearDown(sub.close);
    await container
        .read(scanPaymentControllerProvider.notifier)
        .submitCode('ATTENDANCE');
    expect(cards.requests, isEmpty);
    expect(history.calls, 0);
  });
}

CampusCard _card(int balance) => CampusCard(
    id: 'test-card',
    maskedNumber: '0001',
    ownerName: 'Test',
    balance: MoneyFen(balance),
    status: CampusCardStatus.normal,
    positionName: '',
    offlineCodeAllowed: false,);

class _Cards implements CacheFirstCardRepository {
  _Cards({this.cached = true});
  final bool cached;
  final requests = <Completer<CampusCard?>>[];
  @override
  Future<CampusCard?> readCachedCard() async => cached ? _card(10000) : null;
  @override
  Future<CampusCard?> currentCard() => readCachedCard();
  @override
  Future<CampusCard?> refreshCard() {
    final request = Completer<CampusCard?>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History
    implements TransactionHistoryPort, DateRangeTransactionHistoryPort {
  int calls = 0;
  final pending = Completer<TransactionPage>();
  @override
  Future<TransactionPage> timelineRange(
      {DateTime? begin,
      DateTime? end,
      String? cursor,
      int pageSize = 20,}) async {
    if (++calls == 1) return const TransactionPage(items: [], hasMore: false);
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
