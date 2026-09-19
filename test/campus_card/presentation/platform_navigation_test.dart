import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/ports/auth_port.dart';
import 'package:techpie/features/campus_card/presentation/app/navigation.dart';

/// The feature has no router of its own: its pages are pushed through the host's
/// adaptive page helper, so it inherits TechPie's transition policy, its back
/// gesture, and the account scoping the feature's router used to apply. These
/// tests pin exactly that.
void main() {
  // Belt and braces: each test resets the override before it ends, because the
  // binding verifies that no foundation debug variable is left set.
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('an account change clears page-local state on the pushed page', (
    tester,
  ) async {
    final base = await buildDemoRuntime();
    final auth = _PageTestAuthPort();
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
      overrides: [appRuntimeProvider.overrideWithValue(runtime)],
    );
    addTearDown(() async {
      container.dispose();
      await auth.dispose();
      await base.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                pushCampusCardPage<void>(
                  context,
                  builder: (_) => const _AccountLocalState(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local state: 0'));
    await tester.pump();
    expect(find.text('Local state: 1'), findsOneWidget);

    auth.switchSubject('account-b');
    await tester.pumpAndSettle();
    expect(find.text('Local state: 1'), findsNothing);
    expect(find.text('Local state: 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a feature page is an iOS Cupertino page on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final routes = <Route<dynamic>>[];
    await _pumpPusher(tester, routes);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(routes.last, isA<CupertinoPageRoute<void>>());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a feature page is a Material page everywhere else', (
    tester,
  ) async {
    final routes = <Route<dynamic>>[];
    await _pumpPusher(tester, routes);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(routes.last, isA<MaterialPageRoute<void>>());
  });

  testWidgets('the iOS edge swipe moves the pushed page with the finger', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => Scaffold(
            key: const Key('first-page'),
            body: Center(
              child: TextButton(
                onPressed: () => unawaited(
                  pushCampusCardPage<void>(
                    context,
                    builder: (_) => const Scaffold(
                      key: Key('second-page'),
                      body: Center(child: Text('second')),
                    ),
                  ),
                ),
                child: const Text('next'),
              ),
            ),
          ),
        ),
      ),
      ),
    );
    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();

    final second = find.byKey(const Key('second-page'));
    expect(tester.getTopLeft(second).dx, closeTo(0, 0.1));
    final gesture = await tester.startGesture(const Offset(1, 400));
    await gesture.moveBy(const Offset(140, 0));
    await tester.pump();
    expect(tester.getTopLeft(second).dx, greaterThan(0));

    await gesture.moveBy(const Offset(260, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('first-page')), findsOneWidget);
    expect(second, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _pumpPusher(WidgetTester tester, List<Route<dynamic>> routes) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        navigatorObservers: [_RouteRecorder(routes)],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              pushCampusCardPage<void>(
                context,
                builder: (_) => const SizedBox.shrink(),
              ),
            ),
            child: const Text('push'),
          ),
        ),
      ),
    ),
  );
}

final class _RouteRecorder extends NavigatorObserver {
  _RouteRecorder(this.routes);

  final List<Route<dynamic>> routes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}

final class _PageTestAuthPort implements AuthPort {
  final _changes = StreamController<AuthSnapshot>.broadcast(sync: true);
  AuthSnapshot _snapshot = const AuthSnapshot(
    state: AuthState.authenticated,
    session: AuthSession(subjectId: 'account-a', orgId: '2'),
  );

  @override
  Stream<AuthSnapshot> get changes => _changes.stream;
  @override
  Future<AuthSnapshot> restoreLocal() async => _snapshot;
  @override
  Future<AuthSnapshot> restore() async => _snapshot;
  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async => _snapshot;
  @override
  Future<void> signOut() async {}

  void switchSubject(String subject) {
    _snapshot = AuthSnapshot(
      state: AuthState.authenticated,
      session: AuthSession(subjectId: subject, orgId: '2'),
    );
    _changes.add(_snapshot);
  }

  Future<void> dispose() => _changes.close();
}

final class _AccountLocalState extends StatefulWidget {
  const _AccountLocalState();

  @override
  State<_AccountLocalState> createState() => _AccountLocalStateState();
}

final class _AccountLocalStateState extends State<_AccountLocalState> {
  int value = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => setState(() => value++),
            child: Text('Local state: $value'),
          ),
        ),
      );
}
