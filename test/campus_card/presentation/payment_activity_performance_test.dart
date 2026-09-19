import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/application/payment_code_controller.dart';
import 'package:techpie/features/campus_card/core/config/payment_code_preferences.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_payment_code_repository.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/models/bill_models.dart';
import 'package:techpie/features/campus_card/domain/models/card_models.dart';
import 'package:techpie/features/campus_card/domain/models/payment_models.dart';
import 'package:techpie/features/campus_card/domain/models/profile_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/bill_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/card_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/payment_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart'
    as ports;
import 'package:techpie/features/campus_card/presentation/app/app.dart';
import 'package:techpie/features/campus_card/presentation/screens/card_manage_screen.dart';
import 'package:techpie/features/campus_card/presentation/widgets/apple_wallet_components.dart';

import '../support/fake_ecard_transport.dart';
import '../support/successful_payment_poll.dart';

/// The cadence the app ships with; a poll is reached by waiting this long.
const pollInterval = PaymentCodeController.defaultPollInterval;

void main() {
  testWidgets('a late account refresh failure cannot restore a balance superseded by code data', (tester) async {
    final cards = _PaymentRefreshCards();
    final rig = await _Rig.mount(tester, cards: cards);
    cards.pending = Completer<CampusCard?>();
    final request = rig.container.read(cardControllerProvider.notifier).refresh();
    final rejected = expectLater(request, throwsStateError);
    cards.snapshotsController.add(cards.card(1620));
    await tester.pump();
    cards.pending!.completeError(StateError('late account failure'));
    await rejected;
    await tester.pump();
    expect(rig.container.read(cardControllerProvider).valueOrNull!.balance.value, 1620);
    await rig.dispose(tester);
    await cards.snapshotsController.close();
  });

  testWidgets('code balance refreshes visible card and ledger without a success animation', (tester) async {
    final cards = _PaymentRefreshCards();
    final transactions = _PaymentRefreshTransactions();
    final rig = await _Rig.mount(tester, cards: cards, transactions: transactions);
    final initialCards = cards.refreshCalls;
    final initialHistory = transactions.calls;
    rig.repository.codeBalance = const MoneyFen(1620);
    rig.repository.codeBalanceChanged = true;
    rig.repository.onGenerate = () => cards.snapshotsController.add(cards.card(1620));
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(rig.container.read(cardControllerProvider).valueOrNull!.balance.value, 1620);
    expect(cards.refreshCalls, initialCards);
    expect(transactions.calls, initialHistory + 1);
    expect(find.byKey(const ValueKey('success')), findsNothing);
    rig.repository.codeBalanceChanged = false;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(transactions.calls, initialHistory + 2);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(transactions.calls, initialHistory + 2);
    await rig.dispose(tester);
    await cards.snapshotsController.close();
  });

  for (final hasBalance in [true, false]) {
    testWidgets('pull refresh combines code, ledger and balance (code balance=$hasBalance)', (tester) async {
      final cards = _PaymentRefreshCards();
      final transactions = _PaymentRefreshTransactions();
      final rig = await _Rig.mount(tester, cards: cards, transactions: transactions);
      final initialCards = cards.refreshCalls;
      final initialHistory = transactions.calls;
      final initialCodes = rig.repository.generations;
      if (hasBalance) {
        rig.repository.codeBalance = const MoneyFen(1620);
        rig.repository.codeBalanceChanged = true;
        rig.repository.onGenerate = () => cards.snapshotsController.add(cards.card(1620));
      }
      transactions.showUpdated = true;
      final refresh = tester.widget<EcardSliverRefreshControl>(find.byType(EcardSliverRefreshControl, skipOffstage: false)).onRefresh;
      final first = refresh();
      final duplicate = refresh();
      await tester.pumpAndSettle();
      await Future.wait([first, duplicate]);
      expect(rig.repository.generations, initialCodes + 1);
      expect(cards.refreshCalls, initialCards + (hasBalance ? 0 : 1));
      expect(transactions.calls, initialHistory + 1);
      if (hasBalance) expect(rig.container.read(cardControllerProvider).valueOrNull!.balance.value, 1620);
      expect(find.byKey(const ValueKey('success')), findsNothing);
      await rig.dispose(tester);
      await cards.snapshotsController.close();
    });
  }

  testWidgets(
      'captured payment success animates and refreshes balance and activity together',
      (tester) async {
    final cards = _PaymentRefreshCards();
    final transactions = _PaymentRefreshTransactions();
    final rig =
        await _Rig.mount(tester, cards: cards, transactions: transactions);
    final cardCalls = cards.refreshCalls;
    final transactionCalls = transactions.calls;
    cards.pending = Completer<CampusCard?>();
    transactions.pending = Completer<TransactionPage>();
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/queryOrderStatus', successfulPaymentPoll);
    rig.repository.pendingPoll =
        EcardPaymentCodeRepository(transport).pollTransaction('synthetic-code');
    await tester.pump(pollInterval);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('success')), findsOneWidget);
    expect(find.textContaining('8.80'), findsOneWidget);
    expect(cards.refreshCalls, cardCalls + 1);
    expect(transactions.calls, transactionCalls + 1);
    // A slow ledger/card endpoint must not delay or dismiss the confirmation.
    expect(rig.container.read(cardControllerProvider).valueOrNull!.balance,
        const MoneyFen(2500),);
    cards.pending!.complete(cards.card(1620));
    transactions.pending!.complete(transactions.updated);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(rig.container.read(cardControllerProvider).valueOrNull!.balance,
        const MoneyFen(1620),);
    expect(
        rig.container
            .read(transactionFeedProvider((begin: null, end: null)))
            .valueOrNull!
            .items
            .single
            .id,
        'SYNTHETIC-NEW-TRANSACTION',);
    expect(find.byKey(const ValueKey('success')), findsOneWidget);
    expect(rig.repository.generations, 1);
    await rig.dispose(tester);
  });

  testWidgets(
      'balance refresh failure does not suppress success or activity refresh',
      (tester) async {
    final cards = _PaymentRefreshCards();
    final transactions = _PaymentRefreshTransactions();
    final rig =
        await _Rig.mount(tester, cards: cards, transactions: transactions);
    cards.fail = true;
    transactions.showUpdated = true;
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/queryOrderStatus', successfulPaymentPoll);
    rig.repository.pendingPoll =
        EcardPaymentCodeRepository(transport).pollTransaction('synthetic-code');
    await tester.pump(pollInterval);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('success')), findsOneWidget);
    expect(rig.container.read(cardControllerProvider).valueOrNull!.balance,
        const MoneyFen(2500),);
    expect(
        rig.container
            .read(transactionFeedProvider((begin: null, end: null)))
            .valueOrNull!
            .items
            .single
            .id,
        'SYNTHETIC-NEW-TRANSACTION',);
    expect(tester.takeException(), isNull);
    await rig.dispose(tester);
  });
  testWidgets('a refreshed payload replaces the cached QR matrix',
      (tester) async {
    final rig = await _Rig.mount(tester);
    final before = rig.qrPainter(tester);
    await rig.container.read(paymentCodeControllerProvider.notifier).restart();
    await tester.pumpAndSettle();
    expect(identical(rig.qrPainter(tester), before), isFalse);
    expect(rig.repository.generations, 2);
    await rig.dispose(tester);
  });

  testWidgets('a non-opaque status sheet keeps the visible code active',
      (tester) async {
    final rig = await _Rig.mount(tester, maximizeBrightness: true);
    final context = tester.element(find.byKey(const Key('payment-code-page')));
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => const SizedBox(height: 160, child: Text('Code status')),
      ),
    );
    await tester.pumpAndSettle();
    final before = rig.repository.polls;
    await tester.pump(pollInterval);
    expect(rig.repository.polls, before + 1);
    expect(rig.brightness.value, 1);
    await rig.dispose(tester);
  });

  testWidgets(
      'resource pausing does not swallow the control-center disconnect cue',
      (tester) async {
    final rig = await _Rig.mount(tester);
    rig.lifecycle.setState(ports.AppLifecycleState.inactive);
    (rig.base.connectivity as InMemoryConnectivityPort).setOnline(false);
    await tester.pump(const Duration(seconds: 1));
    final feedback = rig.base.feedback as InMemoryFeedbackPort;
    expect(
      feedback.events
          .where((e) => e == ports.FeedbackEvent.networkDisconnected),
      isEmpty,
    );
    rig.lifecycle.setState(ports.AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      feedback.events
          .where((e) => e == ports.FeedbackEvent.networkDisconnected),
      hasLength(1),
    );
    await rig.dispose(tester);
  });

  testWidgets('countdown ticks reuse the unchanged QR rendering',
      (tester) async {
    final rig = await _Rig.mount(tester);
    final before = rig.qrPainter(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(
      identical(rig.qrPainter(tester), before),
      isTrue,
      reason: 'Changing a seconds label must not recalculate the QR matrix.',
    );
    await rig.dispose(tester);
  });

  testWidgets('a pending poll does not rebuild unchanged payment content',
      (tester) async {
    final rig = await _Rig.mount(tester);
    final poll = Completer<PaymentCodePollResult>();
    rig.repository.pendingPoll = poll.future;
    await tester.pump(pollInterval);
    final before = rig.qrPainter(tester);
    final art = tester.widget(find.byKey(const Key('payment-card-top-art')));
    poll.complete(const PaymentPending());
    await tester.pump();
    await tester.pump();
    expect(identical(rig.qrPainter(tester), before), isTrue);
    expect(
      identical(
        tester.widget(find.byKey(const Key('payment-card-top-art'))),
        art,
      ),
      isTrue,
    );
    await rig.dispose(tester);
  });

  testWidgets('covered payment routes stop polling and restore brightness',
      (tester) async {
    final rig = await _Rig.mount(tester, maximizeBrightness: true);
    // The feature pushes its pages through the host navigator now, so covering
    // the pay page is an ordinary push above it.
    unawaited(
      rig.navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const CardManageScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final before = rig.repository.polls;
    await tester.pump(const Duration(seconds: 6));
    expect(
      (polls: rig.repository.polls - before, brightness: rig.brightness.value),
      (polls: 0, brightness: 0.5),
    );
    final generations = rig.repository.generations;
    rig.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rig.repository.generations, generations + 1);
    expect(rig.brightness.value, 1);
    await rig.dispose(tester);
  });

  testWidgets('a covered host route stays paused when the app resumes',
      (tester) async {
    final rig = await _Rig.mount(tester, maximizeBrightness: true);
    unawaited(
      rig.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Host account settings')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = rig.repository.polls;
    rig.lifecycle.setState(ports.AppLifecycleState.paused);
    rig.lifecycle.setState(ports.AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 6));
    expect(
      (polls: rig.repository.polls - before, brightness: rig.brightness.value),
      (polls: 0, brightness: 0.5),
    );
    rig.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rig.brightness.value, 1);
    await rig.dispose(tester);
  });

  testWidgets('backgrounding stops payment work and resumes with a fresh code',
      (tester) async {
    final rig = await _Rig.mount(tester, maximizeBrightness: true);
    final before = rig.repository.polls;
    rig.lifecycle.setState(ports.AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 6));
    expect(
      (polls: rig.repository.polls - before, brightness: rig.brightness.value),
      (polls: 0, brightness: 0.5),
    );
    final generations = rig.repository.generations;
    rig.lifecycle.setState(ports.AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(rig.repository.generations, generations + 1);
    expect(rig.brightness.value, 1);
    await rig.dispose(tester);
  });

  testWidgets('brightness is unchanged by default and the setting applies live',
      (tester) async {
    final rig = await _Rig.mount(tester);
    expect(rig.brightness.value, 0.5);
    final generations = rig.repository.generations;

    await rig.container
        .read(maximizePaymentCodeBrightnessProvider.notifier)
        .setEnabled(true);
    await tester.pumpAndSettle();
    expect(rig.brightness.value, 1);

    await rig.container
        .read(maximizePaymentCodeBrightnessProvider.notifier)
        .setEnabled(false);
    await tester.pumpAndSettle();
    expect(rig.brightness.value, 0.5);
    expect(rig.repository.generations, generations);
    await rig.dispose(tester);
  });

  testWidgets('debug mode shows where the code spent its time', (tester) async {
    final rig = await _Rig.mount(tester, debugMode: true);

    // The request's own time comes from the controller, against which the local
    // code and the frame are read; together they say which part is slow.
    expect(find.textContaining(RegExp(r'request \d+ms')), findsOneWidget);

    await rig.dispose(tester);
  });

  testWidgets('password rejection silently refreshes without outcome messages',
      (tester) async {
    final rig = await _Rig.mount(tester);
    rig.repository.pendingPoll = Future.value(
      const PaymentNotCompleted(reason: '密码错误'),
    );
    await tester.pump(pollInterval);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('payment-not-completed')), findsNothing);
    expect(find.text('密码错误'), findsNothing);
    expect(find.text('支付结果未确认，请查看消费记录。'), findsNothing);
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    expect(rig.repository.generations, 2);
    expect(find.byKey(const ValueKey('success')), findsNothing);
    expect(
      rig.container.read(paymentCodeControllerProvider).connectionState,
      PaymentConnectionState.online,
    );
    expect(
      (rig.base.feedback as InMemoryFeedbackPort).events,
      isNot(contains(ports.FeedbackEvent.paymentSuccess)),
    );

    rig.repository.pendingPoll = null;
    await tester.pump(pollInterval);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    expect(
      rig.container.read(paymentCodeControllerProvider).connectionState,
      PaymentConnectionState.online,
    );
    await rig.dispose(tester);
  });
}

class _Rig {
  _Rig(
    this.container,
    this.repository,
    this.brightness,
    this.lifecycle,
    this.navigator,
    this.base,
  );
  final ProviderContainer container;
  final _Repository repository;
  final InMemoryBrightnessPort brightness;
  final InMemoryLifecyclePort lifecycle;
  final GlobalKey<NavigatorState> navigator;
  final AppRuntime base;
  bool _disposed = false;

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
    await base.dispose();
  }

  static Future<_Rig> mount(
    WidgetTester tester, {
    bool maximizeBrightness = false,
    CardRepository? cards,
    TransactionHistoryPort? transactions,
    bool debugMode = false,
  }) async {
    SharedPreferences.setMockInitialValues(
      {
        if (maximizeBrightness)
          'geekpay.maximize_payment_code_brightness': true,
        if (debugMode) 'geekpay.debug_mode': true,
      },
    );
    final base = await buildDemoRuntime();
    await base.auth.signIn(const DemoAuthCredential());
    final repository = _Repository();
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: base.auth,
      cards: cards ?? base.cards,
      paymentCodes: repository,
      scanPayments: base.scanPayments,
      transactions: transactions ?? base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
      scanner: base.scanner,
    );
    final container = ProviderContainer(
      overrides: [appRuntimeProvider.overrideWithValue(runtime)],
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          home: const CampusCardFeature(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    final rig = _Rig(
      container,
      repository,
      base.brightness as InMemoryBrightnessPort,
      base.lifecycle as InMemoryLifecyclePort,
      navigator,
      base,
    );
    addTearDown(() => rig.dispose(tester));
    return rig;
  }

  QrPainter qrPainter(WidgetTester tester) => tester
      .widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const Key('payment-code-qr')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is QrPainter,
          ),
        ),
      )
      .painter! as QrPainter;
}

class _Repository implements PaymentCodeRepository {
  MoneyFen? codeBalance;
  bool codeBalanceChanged = false;
  void Function()? onGenerate;
  int polls = 0;
  int generations = 0;
  Future<PaymentCodePollResult>? pendingPoll;
  @override
  Future<void> activateOnlineCode() async {}
  @override
  Future<PaymentCodeFrame> generateOnlineCode() async {
    generations++;
    onGenerate?.call();
    return PaymentCodeFrame(
      balance: codeBalance, balanceChanged: codeBalanceChanged,
      payCode: 'test-$generations',
      rawQrCode: '5638-test',
      qrPayload: String.fromCharCodes(
        List.generate(160, (i) => (i * 31 + generations) % 256),
      ),
      offlineAllowed: true,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<PaymentCodePollResult> pollTransaction(String payCode, {PaymentRequestContext? context}) async {
    polls++;
    return pendingPoll ?? const PaymentPending();
  }
}

final class _PaymentRefreshCards implements CacheFirstCardRepository, CardSnapshotSource {
  final snapshotsController = StreamController<CampusCard?>.broadcast();
  @override
  Stream<CampusCard?> get snapshots => snapshotsController.stream;
  int refreshCalls = 0;
  bool fail = false;
  Completer<CampusCard?>? pending;
  CampusCard card(int balance) => CampusCard(
        id: 'DEMO-CARD-0001',
        maskedNumber: '****0001',
        ownerName: '示例用户',
        balance: MoneyFen(balance),
        status: CampusCardStatus.normal,
        positionName: '学生',
        offlineCodeAllowed: true,
      );
  @override
  Future<CampusCard?> currentCard() async => card(2500);
  @override
  Future<CampusCard?> readCachedCard() async => card(2500);
  @override
  Future<CampusCard?> refreshCard() async {
    refreshCalls++;
    if (fail) throw StateError('Synthetic card refresh failure');
    return pending == null ? card(2500) : await pending!.future;
  }

  @override
  Future<UserProfile> profile() async => const UserProfile(
      displayName: '示例用户', maskedCardNumber: '****0001', positionName: '学生',);
  @override
  Future<BindCardResult> bind(BindCardCommand command) =>
      throw UnimplementedError();
  @override
  Future<void> unbind({required String cardPassword}) =>
      throw UnimplementedError();
}

final class _PaymentRefreshTransactions
    implements TransactionHistoryPort, DateRangeTransactionHistoryPort {
  int calls = 0;
  bool showUpdated = false;
  Completer<TransactionPage>? pending;
  TransactionPage get updated => TransactionPage(items: [
        TransactionRecord(
          id: 'SYNTHETIC-NEW-TRANSACTION',
          occurredAt: DateTime(2026, 9, 9, 14, 39, 44),
          title: '新消费记录',
          amount: const MoneyFen(-880),
          kind: TransactionKind.consumption,
        ),
      ], hasMore: false,);
  @override
  Future<TransactionPage> timelineRange(
      {DateTime? begin,
      DateTime? end,
      String? cursor,
      int pageSize = 20,}) async {
    calls++;
    if (pending != null) return pending!.future;
    return showUpdated
        ? updated
        : const TransactionPage(items: [], hasMore: false);
  }

  @override
  Future<TransactionPage> timeline(
          {required String month, String? cursor, int pageSize = 20,}) =>
      timelineRange(cursor: cursor, pageSize: pageSize);
  @override
  Future<TransactionRecord> detail(String id) async => updated.items.single;
}
