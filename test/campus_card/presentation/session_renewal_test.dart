import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/models/payment_models.dart';
import 'package:techpie/features/campus_card/domain/models/scan_models.dart';
import 'package:techpie/features/campus_card/domain/ports/auth_port.dart';
import 'package:techpie/features/campus_card/domain/ports/payment_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart'
    as ports;
import 'package:techpie/features/campus_card/presentation/app/app.dart';
import 'package:techpie/features/campus_card/presentation/screens/login_screen.dart';

void main() {
  for (final initiallyLocked in [false, true]) {
    testWidgets('temporary secure storage failure recovers without connect guide (locked=$initiallyLocked)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final base = await buildDemoRuntime();
      addTearDown(base.dispose);
      final auth = _RestoredAuthPort()..localFailures = initiallyLocked ? 100 : 1;
      addTearDown(auth.dispose);
      final lifecycle = base.lifecycle as InMemoryLifecyclePort;
      if (initiallyLocked) lifecycle.setState(ports.AppLifecycleState.paused);
      await tester.pumpWidget(MaterialApp(home: ProviderScope(overrides: [appRuntimeProvider.overrideWithValue(_runtimeWithAuth(base, auth))], child: const CampusCardFeature())));
      for (var i = 0; i < 40; i++) { await tester.pump(const Duration(milliseconds: 30)); }
      expect(find.byType(LoginScreen), findsNothing);
      if (initiallyLocked) {
        expect(find.byKey(const Key('ecard-session-restore-page')), findsOneWidget);
        expect(auth.localReads, 1);
        auth.localFailures = 0;
        lifecycle.setState(ports.AppLifecycleState.resumed);
        for (var i = 0; i < 40; i++) { await tester.pump(const Duration(milliseconds: 30)); }
      }
      expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
      expect(auth.localReads, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('persistent local storage failure retries only twice and offers recovery', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort()..localFailures = 100;
    addTearDown(auth.dispose);
    await tester.pumpWidget(MaterialApp(home: ProviderScope(overrides: [appRuntimeProvider.overrideWithValue(_runtimeWithAuth(base, auth))], child: const CampusCardFeature())));
    for (var i = 0; i < 50; i++) { await tester.pump(const Duration(milliseconds: 30)); }
    expect(auth.localReads, 3);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(const Key('ecard-session-restore-page')), findsOneWidget);
    await tester.pump(const Duration(seconds: 20));
    expect(auth.localReads, 3);
    auth.localFailures = 0;
    await tester.tap(find.text('重试'));
    for (var i = 0; i < 40; i++) { await tester.pump(const Duration(milliseconds: 30)); }
    expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('explicit disconnection remains on the guide after resume', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort();
    addTearDown(auth.dispose);
    await tester.pumpWidget(MaterialApp(home: ProviderScope(overrides: [appRuntimeProvider.overrideWithValue(_runtimeWithAuth(base, auth))], child: const CampusCardFeature())));
    for (var i = 0; i < 30; i++) { await tester.pump(const Duration(milliseconds: 30)); }
    auth.accountPresent = false;
    auth._changes.add(const AuthSnapshot(state: AuthState.signedOut, reason: AuthChangeReason.userSignedOut));
    final lifecycle = base.lifecycle as InMemoryLifecyclePort;
    lifecycle.setState(ports.AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 31));
    lifecycle.setState(ports.AppLifecycleState.resumed);
    for (var i = 0; i < 40; i++) { await tester.pump(const Duration(milliseconds: 30)); }
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const Key('payment-code-page')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('foreground recovery leaves the guide without reopening even when restore emits no event', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort();
    addTearDown(auth.dispose);
    final lifecycle = base.lifecycle as InMemoryLifecyclePort;
    final runtime = AppRuntime(environment: base.environment, capabilities: base.capabilities,
      auth: auth, cards: base.cards, paymentCodes: base.paymentCodes, scanPayments: base.scanPayments,
      transactions: base.transactions, securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments, brightness: base.brightness,
      connectivity: base.connectivity, lifecycle: lifecycle, feedback: base.feedback,);
    await tester.pumpWidget(MaterialApp(home: ProviderScope(overrides: [appRuntimeProvider.overrideWithValue(runtime)], child: const CampusCardFeature())));
    for (var i = 0; i < 30; i++) { await tester.pump(const Duration(milliseconds: 30)); }
    expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
    lifecycle.setState(ports.AppLifecycleState.paused);
    auth._changes.add(const AuthSnapshot(state: AuthState.expired));
    await tester.pump(const Duration(minutes: 31));
    for (var i = 0; i < 20; i++) { await tester.pump(const Duration(milliseconds: 30)); }
    lifecycle.setState(ports.AppLifecycleState.resumed);
    for (var i = 0; i < 40; i++) { await tester.pump(const Duration(milliseconds: 30)); }
    expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('same-account recovery keeps a submitting scan pending instead of restarting it', () async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort();
    addTearDown(auth.dispose);
    final scan = _PendingScan();
    final runtime = AppRuntime(environment: base.environment, capabilities: base.capabilities,
      auth: auth, cards: base.cards, paymentCodes: base.paymentCodes, scanPayments: scan,
      transactions: base.transactions, securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments, brightness: base.brightness,
      connectivity: base.connectivity, lifecycle: base.lifecycle, feedback: base.feedback,);
    final container = ProviderContainer(overrides: [appRuntimeProvider.overrideWithValue(runtime)]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await pumpEventQueue();
    final sub = container.listen(scanPaymentControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final pending = container.read(scanPaymentControllerProvider.notifier).submitCode('SYNTHETIC');
    auth._changes.add(const AuthSnapshot(state: AuthState.authenticated,
      session: AuthSession(subjectId: 'restored-test-subject', orgId: '2', generation: 1),),);
    await pumpEventQueue();
    expect(container.read(scanPaymentControllerProvider).phase, ScanFlowPhase.submitting);
    scan.pending.complete(const ScanFailed(message: 'Verify transaction history before retrying'));
    await pending;
    expect(container.read(scanPaymentControllerProvider).phase, ScanFlowPhase.failed);
    expect(scan.calls, 1);
  });

  testWidgets(
      'leaving during local restoration creates no late auth subscriptions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final pending = Completer<AuthSnapshot>();
    final auth = _RestoredAuthPort(localRestore: pending.future);
    addTearDown(auth.dispose);
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: base.cards,
      paymentCodes: base.paymentCodes,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
    );
    final container = ProviderContainer(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],);
    container.read(authControllerProvider);
    container.dispose();
    pending.complete(_RestoredAuthPort._snapshot);
    await tester.pump();
    expect(auth._changes.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-account renewal restarts an already displayed QR',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort();
    addTearDown(auth.dispose);
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: base.cards,
      paymentCodes: base.paymentCodes,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
    );
    Widget app() => MaterialApp(
          home: ProviderScope(
            overrides: [appRuntimeProvider.overrideWithValue(runtime)],
            child: const CampusCardFeature(),
          ),
        );
    await tester.pumpWidget(app());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    final page = find.byKey(const Key('payment-code-page'));
    final originalElement = tester.element(page);
    final container = ProviderScope.containerOf(originalElement);
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    auth._changes.add(
      const AuthSnapshot(
        state: AuthState.authenticated,
        session: AuthSession(
          subjectId: 'restored-test-subject',
          orgId: '2',
          generation: 1,
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(identical(tester.element(page), originalElement), isTrue);
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.displaying,
    );
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment-code-pending-spinner')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.displaying,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('same-account renewal restarts a pending first QR',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort();
    final pendingCode = Completer<PaymentCodeFrame>();
    final payment = _FirstPendingPayment(base.paymentCodes, pendingCode.future);
    addTearDown(auth.dispose);
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: base.cards,
      paymentCodes: payment,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
    );
    Widget app() => MaterialApp(
          home: ProviderScope(
            overrides: [appRuntimeProvider.overrideWithValue(runtime)],
            child: const CampusCardFeature(),
          ),
        );
    await tester.pumpWidget(app());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    final page = find.byKey(const Key('payment-code-page'));
    final originalElement = tester.element(page);
    final container = ProviderScope.containerOf(originalElement);
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.initializing,
    );
    auth._changes.add(
      const AuthSnapshot(
        state: AuthState.authenticated,
        session: AuthSession(
          subjectId: 'restored-test-subject',
          orgId: '2',
          generation: 1,
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(identical(tester.element(page), originalElement), isTrue);
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.displaying,
    );
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment-code-pending-spinner')),
      findsNothing,
    );
    pendingCode.complete(await base.paymentCodes.generateOnlineCode());
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.displaying,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('late error from replaced controller cannot hide the new QR',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort();
    final pendingCode = Completer<PaymentCodeFrame>();
    final payment = _FirstPendingPayment(base.paymentCodes, pendingCode.future);
    addTearDown(auth.dispose);
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: base.cards,
      paymentCodes: payment,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
    );
    Widget app() => MaterialApp(
          home: ProviderScope(
            overrides: [appRuntimeProvider.overrideWithValue(runtime)],
            child: const CampusCardFeature(),
          ),
        );
    await tester.pumpWidget(app());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    final page = find.byKey(const Key('payment-code-page'));
    final originalElement = tester.element(page);
    final container = ProviderScope.containerOf(originalElement);
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.initializing,
    );
    auth._changes.add(
      const AuthSnapshot(
        state: AuthState.authenticated,
        session: AuthSession(
          subjectId: 'restored-test-subject',
          orgId: '2',
          generation: 1,
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(identical(tester.element(page), originalElement), isTrue);
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.displaying,
    );
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment-code-pending-spinner')),
      findsNothing,
    );
    pendingCode.completeError(StateError('late old request failure'));
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.displaying,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('renewal in background waits for resume', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort();
    final lifecycle = base.lifecycle as InMemoryLifecyclePort;
    final payment = _FirstPendingPayment(
      base.paymentCodes,
      base.paymentCodes.generateOnlineCode(),
    );
    addTearDown(auth.dispose);
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: base.cards,
      paymentCodes: payment,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
    );
    Widget app() => MaterialApp(
          home: ProviderScope(
            overrides: [appRuntimeProvider.overrideWithValue(runtime)],
            child: const CampusCardFeature(),
          ),
        );
    await tester.pumpWidget(app());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    final page = find.byKey(const Key('payment-code-page'));
    final originalElement = tester.element(page);
    final container = ProviderScope.containerOf(originalElement);
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    lifecycle.setState(ports.AppLifecycleState.paused);
    await tester.pump();
    final callsBefore = payment.calls;
    auth._changes.add(
      const AuthSnapshot(
        state: AuthState.authenticated,
        session: AuthSession(
          subjectId: 'restored-test-subject',
          orgId: '2',
          generation: 1,
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(payment.calls, callsBefore);
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.idle,
    );
    lifecycle.setState(ports.AppLifecycleState.resumed);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(payment.calls, callsBefore + 1);
    expect(identical(tester.element(page), originalElement), isTrue);
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.displaying,
    );
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment-code-pending-spinner')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.displaying,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('same-account renewal preserves manual offline mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final auth = _RestoredAuthPort();
    final payment = _FirstPendingPayment(
      base.paymentCodes,
      base.paymentCodes.generateOnlineCode(),
    );
    addTearDown(auth.dispose);
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: base.cards,
      paymentCodes: payment,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
    );
    Widget app() => MaterialApp(
          home: ProviderScope(
            overrides: [appRuntimeProvider.overrideWithValue(runtime)],
            child: const CampusCardFeature(),
          ),
        );
    await tester.pumpWidget(app());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    final page = find.byKey(const Key('payment-code-page'));
    final originalElement = tester.element(page);
    final container = ProviderScope.containerOf(originalElement);
    expect(find.byKey(const Key('payment-code-qr')), findsOneWidget);
    container.read(manualOfflineModeProvider.notifier).setEnabled(true);
    await container
        .read(paymentCodeControllerProvider.notifier)
        .enter(online: false);
    await tester.pump();
    final callsBefore = payment.calls;
    auth._changes.add(
      const AuthSnapshot(
        state: AuthState.authenticated,
        session: AuthSession(
          subjectId: 'restored-test-subject',
          orgId: '2',
          generation: 1,
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(payment.calls, callsBefore);
    expect(container.read(manualOfflineModeProvider), isTrue);
    expect(
      container.read(paymentCodeControllerProvider).phase,
      PaymentCodePhase.stopped,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

final class _RestoredAuthPort implements AuthPort {
  _RestoredAuthPort({this.localRestore});

  final Future<AuthSnapshot>? localRestore;
  int localFailures = 0;
  int localReads = 0;
  bool accountPresent = true;
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
  Future<AuthSnapshot> restoreLocal() async {
    localReads++;
    if (localFailures-- > 0) {
      throw const AppFailure(FailureKind.unavailable, 'Protected data unavailable', code: 'SECURE_STORAGE_UNAVAILABLE', retryable: true);
    }
    return localRestore ?? (accountPresent ? _snapshot : const AuthSnapshot(state: AuthState.signedOut));
  }

  @override
  Future<AuthSnapshot> restore() async => accountPresent ? _snapshot : const AuthSnapshot(state: AuthState.signedOut);

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async => _snapshot;

  @override
  Future<void> signOut() async {}

  void expire() {
    _changes.add(const AuthSnapshot(state: AuthState.signedOut));
  }

  Future<void> dispose() => _changes.close();
}

final class _FirstPendingPayment implements PaymentCodeRepository {
  _FirstPendingPayment(this.delegate, this.pending);
  final PaymentCodeRepository delegate;
  final Future<PaymentCodeFrame> pending;
  int calls = 0;
  @override
  Future<PaymentCodeFrame> generateOnlineCode() =>
      ++calls == 1 ? pending : delegate.generateOnlineCode();
  @override
  Future<void> activateOnlineCode() => delegate.activateOnlineCode();
  @override
  Future<PaymentCodePollResult> pollTransaction(
    String code, {
    PaymentRequestContext? context,
  }) =>
      delegate.pollTransaction(code, context: context);
}

class _PendingScan implements ScanPaymentRepository {
  final pending = Completer<ScanPaymentResult>();
  int calls = 0;
  @override
  Future<ScanPaymentResult> submit({required String qrCode, required DateTime payTime, String? password, PaymentRequestContext? context}) {
    calls++;
    return pending.future;
  }
}

AppRuntime _runtimeWithAuth(AppRuntime base, AuthPort auth) => AppRuntime(
  environment: base.environment, capabilities: base.capabilities,
  auth: auth, cards: base.cards, paymentCodes: base.paymentCodes, scanPayments: base.scanPayments,
  transactions: base.transactions, securitySettings: base.securitySettings,
  offlinePayments: base.offlinePayments, brightness: base.brightness,
  connectivity: base.connectivity, lifecycle: base.lifecycle, feedback: base.feedback,
);
