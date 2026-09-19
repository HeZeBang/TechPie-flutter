import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/config/app_environment.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/ports/auth_port.dart';
import 'package:techpie/features/campus_card/presentation/app/app.dart';
import 'package:techpie/features/campus_card/presentation/screens/login_screen.dart';
import 'package:techpie/pages/campus_card_page.dart';

void main() {
  Future<void> pumpFrames(WidgetTester tester, [int frames = 32]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<AppRuntime> stagingRuntime(_ScriptedAuthPort auth) async {
    final ports = await buildDemoRuntime();
    return AppRuntime(
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
  }

  Future<void> pumpLogin(
    WidgetTester tester,
    AppRuntime runtime, {
    VoidCallback? onAccount,
  }) async {
    const primary = Color(0xFF4A67D6);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.dark(
            primary: primary,
            onPrimary: Colors.white,
          ),
        ),
        home: ProviderScope(
          overrides: [
            appRuntimeProvider.overrideWithValue(runtime),
            campusCardAccountProvider.overrideWithValue(onAccount),
          ],
          child: const CampusCardFeature(),
        ),
      ),
    );
    await pumpFrames(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
  }

  testWidgets('uses TechPie theme and sends account setup to Account settings',
      (
    tester,
  ) async {
    final auth = _ScriptedAuthPort();
    final runtime = await stagingRuntime(auth);
    addTearDown(runtime.dispose);
    var accountOpened = false;
    await pumpLogin(
      tester,
      runtime,
      onAccount: () => accountOpened = true,
    );

    expect(find.byKey(const Key('openid-input')), findsNothing);
    expect(find.text('打开 Account 设置'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(LoginScreen))).brightness,
      Brightness.dark,
    );
    expect(
      Theme.of(tester.element(find.byType(LoginScreen))).colorScheme.primary,
      const Color(0xFF4A67D6),
    );

    await tester.tap(find.text('打开 Account 设置'));
    await tester.pump();
    expect(accountOpened, isTrue);
  });

  testWidgets('the back action leaves the feature through the host navigator', (
    tester,
  ) async {
    final auth = _ScriptedAuthPort();
    final runtime = await stagingRuntime(auth);
    addTearDown(runtime.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Center(child: Text('host page'))),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => CampusCardPage(runtime: runtime)),
      ),
    );
    await pumpFrames(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('host page'), findsOneWidget);
  });

  testWidgets('an authenticated Account session enters the payment code', (
    tester,
  ) async {
    final auth = _ScriptedAuthPort();
    final runtime = await stagingRuntime(auth);
    addTearDown(runtime.dispose);
    await pumpLogin(tester, runtime);

    auth.authenticate();
    await pumpFrames(tester, 40);

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
  });
}

const _signedOut = AuthSnapshot(state: AuthState.signedOut);

final class _ScriptedAuthPort implements AuthPort {
  final StreamController<AuthSnapshot> _changes =
      StreamController<AuthSnapshot>.broadcast(sync: true);
  AuthSnapshot _snapshot = _signedOut;

  @override
  Stream<AuthSnapshot> get changes => _changes.stream;

  @override
  Future<AuthSnapshot> restoreLocal() async => _snapshot;

  @override
  Future<AuthSnapshot> restore() async => _snapshot;

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async => _snapshot;

  @override
  Future<void> signOut() async {
    _snapshot = _signedOut;
    _changes.add(_snapshot);
  }

  void authenticate() {
    _snapshot = const AuthSnapshot(
      state: AuthState.authenticated,
      session: AuthSession(
        subjectId: 'synthetic-subject',
        orgId: '2',
        maskedIdentity: 'SYNT****0042',
      ),
    );
    _changes.add(_snapshot);
  }
}
