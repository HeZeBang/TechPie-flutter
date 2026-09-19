import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/application/payment_code_controller.dart';
import 'package:techpie/features/campus_card/core/config/app_environment.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/models/card_models.dart';
import 'package:techpie/features/campus_card/domain/models/offline_models.dart';
import 'package:techpie/features/campus_card/domain/models/payment_models.dart';
import 'package:techpie/features/campus_card/domain/models/profile_models.dart';
import 'package:techpie/features/campus_card/domain/models/scan_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/auth_port.dart';
import 'package:techpie/features/campus_card/domain/ports/card_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/payment_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart';
import 'package:techpie/features/campus_card/presentation/app/app.dart';
import 'package:techpie/features/campus_card/presentation/scanner/scan_result_content.dart';
import 'package:techpie/features/campus_card/presentation/scanner/scanner_modal.dart';
import 'package:techpie/features/campus_card/presentation/theme/tokens.dart';
import 'package:techpie/features/campus_card/presentation/widgets/apple_wallet_components.dart';
import 'package:techpie/pages/campus_card_page.dart';

void main() {
  testWidgets('local session opens the target without a splash or network gate',
      (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
    });
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final pendingSession = Completer<AuthSnapshot>();
    final auth = _RestoredAuthPort(localRestore: pendingSession.future);
    addTearDown(auth.dispose);
    final pendingCard = Completer<CampusCard?>();
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: _DelayedCardRepository(base.cards, pendingCard.future),
      paymentCodes: base.paymentCodes,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
      scanner: base.scanner,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderScope(
          overrides: [appRuntimeProvider.overrideWithValue(runtime)],
          child: const CampusCardFeature(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byKey(const Key('payment-code-page')), findsNothing);
    expect(find.text('eCard'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    pendingSession.complete(_RestoredAuthPort._snapshot);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
    expect(find.byKey(const Key('payment-card-loading')), findsOneWidget);

    pendingCard.complete(null);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('network failure falls back to the installed offline code', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
    });
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort();
    addTearDown(auth.dispose);
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: _OfflineCacheMissCardRepository(base.cards),
      paymentCodes: const _OfflinePaymentCodeRepository(),
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
      scanner: base.scanner,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderScope(
          overrides: [appRuntimeProvider.overrideWithValue(runtime)],
          child: const CampusCardFeature(),
        ),
      ),
    );
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
    expect(find.text('离线付款码'), findsOneWidget);
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    expect(find.text('--'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('payment-code-page'))),
    );
    container.read(manualOfflineModeProvider.notifier).setEnabled(true);
    await tester.pump(const Duration(seconds: 1));
    expect(
      (base.feedback as InMemoryFeedbackPort)
          .events
          .where((event) => event == FeedbackEvent.networkDisconnected),
      isEmpty,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('passive and active payment success use campus red', (
    tester,
  ) async {
    const primary = GpTokens.appleBlue;
    SharedPreferences.setMockInitialValues({
    });
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort();
    addTearDown(auth.dispose);
    final paymentCodes = _RefreshHoldingPaymentCodeRepository();
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: base.cards,
      paymentCodes: paymentCodes,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
      scanner: base.scanner,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.light(primary: primary),
          ),
          home: const CampusCardFeature(),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    await tester.tap(find.byKey(const Key('payment-code-qr')));
    await tester.pump();
    final spinner = find.descendant(
      of: find.byKey(const ValueKey('payment-code-refresh-spinner')),
      matching: find.byType(CupertinoActivityIndicator),
    );
    expect(spinner, findsOneWidget);
    expect(
      tester.widget<CupertinoActivityIndicator>(spinner).color,
      GpTokens.campusRed,
    );

    paymentCodes.refresh.complete(paymentCodes.frame('refreshed-code'));
    await tester.pump();
    paymentCodes.pollResult = PaymentCompleted(
      TransactionResult(
        amount: const MoneyFen(1280),
        confirmedLocallyAt: DateTime.utc(2026, 9, 6),
      ),
    );
    await tester.pump(PaymentCodeController.defaultPollInterval);
    await tester.pump();
    expect(
      tester
          .widget<AnimatedSuccessCheck>(find.byType(AnimatedSuccessCheck))
          .color,
      GpTokens.campusRed,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.light(primary: primary),
        ),
        home: Scaffold(
          body: ScanResultContent(
            success: const ScanSucceeded(kind: ScanSuccessKind.payment),
            onDone: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paintedCheck = find.descendant(
      of: find.byType(AnimatedSuccessCheck),
      matching: find.byType(CustomPaint),
    );
    expect(
      tester.renderObject(paintedCheck),
      paints..arc(color: GpTokens.campusRed),
    );
  });

  testWidgets(
    'card management root exits through the TechPie host navigator',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      });
      final ports = await buildDemoRuntime();
      final auth = _RestoredAuthPort();
      addTearDown(auth.dispose);
      final runtime = AppRuntime(
        environment: AppEnvironment.staging,
        capabilities: AppCapabilities.forEnvironment(AppEnvironment.staging),
        auth: auth,
        cards: ports.cards,
        paymentCodes: ports.paymentCodes,
        scanPayments: ports.scanPayments,
        transactions: ports.transactions,
        securitySettings: ports.securitySettings,
        offlinePayments: ports.offlinePayments,
        brightness: ports.brightness,
        connectivity: ports.connectivity,
        lifecycle: ports.lifecycle,
        feedback: ports.feedback,
        scanner: ports.scanner,
        disposeRuntime: ports.dispose,
      );
      addTearDown(runtime.dispose);
      // The feature is a page like any other now: the host pushes it, and its
      // first page's back action leaves it through the host navigator.
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Center(child: Text('host page'))),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => CampusCardPage(
              entry: CampusCardEntry.cardManagement,
              runtime: runtime,
            ),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.byKey(const Key('card-manage-page')), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card-manage-page')), findsNothing);
      expect(find.text('host page'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'restored session opens the payment code root without a close button',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      });
      final ports = await buildDemoRuntime();
      final auth = _RestoredAuthPort();
      addTearDown(auth.dispose);
      final runtime = AppRuntime(
        environment: AppEnvironment.staging,
        capabilities: AppCapabilities.forEnvironment(AppEnvironment.staging),
        auth: auth,
        cards: ports.cards,
        paymentCodes: ports.paymentCodes,
        scanPayments: ports.scanPayments,
        transactions: ports.transactions,
        securitySettings: ports.securitySettings,
        offlinePayments: ports.offlinePayments,
        brightness: ports.brightness,
        connectivity: ports.connectivity,
        lifecycle: ports.lifecycle,
        feedback: ports.feedback,
        scanner: ports.scanner,
        disposeRuntime: ports.dispose,
      );
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        MaterialApp(
            home: ProviderScope(
            overrides: [appRuntimeProvider.overrideWithValue(runtime)],
            child: const CampusCardFeature(),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
      expect(find.bySemanticsLabel('关闭'), findsNothing);
      expect(find.text('在线付款码'), findsOneWidget);

      // The pass prints the card's number, not the card: the label used to
      // interpolate the object and read "No. Instance of 'CampusCard'.id".
      final card = await runtime.cards.currentCard();
      expect(find.text('No. ${card!.id}'), findsOneWidget);
      expect(find.textContaining('Instance of'), findsNothing);
      final passSize = tester.getSize(
        find.byKey(const Key('expanded-payment-pass')),
      );
      final qrSize = tester.getSize(find.byKey(const Key('payment-code-qr')));
      final topArtSize = tester.getSize(
        find.byKey(const Key('payment-card-top-art')),
      );
      final bottomArtSize = tester.getSize(
        find.byKey(const Key('payment-card-bottom-art')),
      );
      expect(passSize.width / passSize.height, closeTo(746 / 984, 0.002));
      expect(qrSize.width / passSize.width, closeTo(0.668, 0.002));
      expect(topArtSize.width / topArtSize.height, closeTo(746 / 126, 0.002));
      expect(
        bottomArtSize.width / bottomArtSize.height,
        closeTo(744 / 337, 0.002),
      );

      await tester.tap(find.bySemanticsLabel('在线状态'));
      await tester.pumpAndSettle();
      expect(find.text('当前延迟'), findsOneWidget);
      expect(find.text('离线付款码'), findsWidgets);
      expect(find.byType(Switch), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('扫一扫'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ScannerModal), findsOneWidget);
      expect(find.byKey(const Key('scanner-close-button')), findsOneWidget);
      expect(find.byKey(const Key('payment-header-info')), findsNothing);
      await tester.tap(find.bySemanticsLabel('关闭'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(
        tester.widget<TransactionList>(find.byType(TransactionList)).items,
        hasLength(25),
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payment-header-info')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.byKey(const Key('card-manage-page')), findsOneWidget);
      expect(find.text('OPENID'), findsNothing);
      expect(find.text('上海科技大学 eCard'), findsOneWidget);
      expect(find.text('退出登录'), findsNothing);

      auth.expire();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.text('打开 Account 设置'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'offline banner dismisses, stays hidden after activation, and resets on removal',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      });
      final ports = await buildDemoRuntime();
      await ports.offlinePayments.removeAllFromThisDevice();
      final auth = _RestoredAuthPort();
      addTearDown(auth.dispose);
      final runtime = AppRuntime(
        environment: AppEnvironment.staging,
        capabilities: AppCapabilities.forEnvironment(AppEnvironment.staging),
        auth: auth,
        cards: ports.cards,
        paymentCodes: ports.paymentCodes,
        scanPayments: ports.scanPayments,
        transactions: ports.transactions,
        securitySettings: ports.securitySettings,
        offlinePayments: ports.offlinePayments,
        brightness: ports.brightness,
        connectivity: ports.connectivity,
        lifecycle: ports.lifecycle,
        feedback: ports.feedback,
        scanner: ports.scanner,
        disposeRuntime: ports.dispose,
      );
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        MaterialApp(
            home: ProviderScope(
            overrides: [appRuntimeProvider.overrideWithValue(runtime)],
            child: const CampusCardFeature(),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('payment-code-page'))),
      );
      final card = await container.read(cardControllerProvider.future);
      expect(
        (await container.read(
          offlineAuthorizationProvider(card!.id).future,
        ))
            .state,
        OfflineAuthorizationState.missingCredential,
      );
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -640),
      );
      await tester.pumpAndSettle();
      final banner = find.byKey(const Key('offline-authorization-banner'));
      expect(banner, findsOneWidget);
      await tester.tap(
        find.byKey(const Key('offline-authorization-banner-close')),
      );
      await tester.pumpAndSettle();
      expect(banner, findsNothing);

      await container
          .read(offlineAuthorizationProvider(card.id).notifier)
          .activate();
      await tester.pumpAndSettle();
      expect(banner, findsNothing);

      await container
          .read(offlineAuthorizationProvider(card.id).notifier)
          .removeFromDevice();
      await tester.pumpAndSettle();
      expect(banner, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

final class _DelayedCardRepository implements CardRepository {
  const _DelayedCardRepository(this._delegate, this._currentCard);

  final CardRepository _delegate;
  final Future<CampusCard?> _currentCard;

  @override
  Future<CampusCard?> currentCard() => _currentCard;

  @override
  Future<UserProfile> profile() => _delegate.profile();

  @override
  Future<BindCardResult> bind(BindCardCommand command) =>
      _delegate.bind(command);

  @override
  Future<void> unbind({required String cardPassword}) =>
      _delegate.unbind(cardPassword: cardPassword);
}

final class _OfflinePaymentCodeRepository implements PaymentCodeRepository {
  const _OfflinePaymentCodeRepository();

  @override
  Future<void> activateOnlineCode() async {}

  @override
  Future<PaymentCodeFrame> generateOnlineCode() => Future.error(
        const AppFailure(
          FailureKind.network,
          '网络不可用',
          code: 'TEST_OFFLINE',
          retryable: true,
        ),
      );

  @override
  Future<PaymentCodePollResult> pollTransaction(String payCode, {PaymentRequestContext? context}) async =>
      const PaymentPending();
}

final class _OfflineCacheMissCardRepository
    implements CacheFirstCardRepository {
  const _OfflineCacheMissCardRepository(this._delegate);

  final CardRepository _delegate;

  @override
  Future<CampusCard?> readCachedCard() async => null;

  @override
  Future<CampusCard?> refreshCard() => Future.error(
        const AppFailure(
          FailureKind.network,
          '网络不可用',
          code: 'TEST_CARD_OFFLINE',
          retryable: true,
        ),
      );

  @override
  Future<CampusCard?> currentCard() => refreshCard();

  @override
  Future<UserProfile> profile() => _delegate.profile();

  @override
  Future<BindCardResult> bind(BindCardCommand command) =>
      _delegate.bind(command);

  @override
  Future<void> unbind({required String cardPassword}) =>
      _delegate.unbind(cardPassword: cardPassword);
}

final class _RefreshHoldingPaymentCodeRepository
    implements PaymentCodeRepository {
  final refresh = Completer<PaymentCodeFrame>();
  PaymentCodePollResult pollResult = const PaymentPending();
  int _generation = 0;

  PaymentCodeFrame frame(String code) => PaymentCodeFrame(
        payCode: code,
        rawQrCode: code,
        qrPayload: code,
        offlineAllowed: true,
        generatedAt: DateTime.utc(2026, 9, 4),
      );

  @override
  Future<void> activateOnlineCode() async {}

  @override
  Future<PaymentCodeFrame> generateOnlineCode() {
    _generation += 1;
    if (_generation == 1) return Future.value(frame('initial-code'));
    return refresh.future;
  }

  @override
  Future<PaymentCodePollResult> pollTransaction(String payCode, {PaymentRequestContext? context}) async =>
      pollResult;
}

final class _RestoredAuthPort implements AuthPort {
  _RestoredAuthPort({this.localRestore});

  final Future<AuthSnapshot>? localRestore;
  final StreamController<AuthSnapshot> _changes =
      StreamController<AuthSnapshot>.broadcast(sync: true);

  static const _snapshot = AuthSnapshot(
    state: AuthState.authenticated,
    session: AuthSession(
      subjectId: 'restored-test-subject',
      orgId: '2',
      maskedIdentity: 'TEST****0001',
    ),
  );

  @override
  Stream<AuthSnapshot> get changes => _changes.stream;

  @override
  Future<AuthSnapshot> restoreLocal() =>
      localRestore ?? Future.value(_snapshot);

  @override
  Future<AuthSnapshot> restore() async => _snapshot;

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async => _snapshot;

  @override
  Future<void> signOut() async {}

  void expire() {
    _changes.add(const AuthSnapshot(state: AuthState.signedOut));
  }

  Future<void> dispose() => _changes.close();
}
