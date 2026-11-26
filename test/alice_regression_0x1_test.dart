import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/config/app_environment.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/ports/auth_port.dart';
import 'package:techpie/features/campus_card/presentation/app/app.dart';
import 'package:techpie/features/campus_card/presentation/screens/card_manage_screen.dart';
import 'package:techpie/features/campus_card/presentation/screens/login_screen.dart';
import 'package:techpie/features/campus_card/presentation/screens/payment_code_page.dart';
import 'package:techpie/features/campus_card/presentation/screens/session_restore_screen.dart';
import 'package:techpie/pages/campus_card_page.dart';
import 'package:techpie/widgets/adaptive_page_navigation.dart';

void main() {
  testWidgets(
    'CampusCardFeature hides loading indicators during first 30ms of local session restore before opening payment code',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pendingSession = Completer<AuthSnapshot>();
      final auth = _ControllableAuthPort(localRestore: pendingSession.future);
      addTearDown(auth.dispose);
      final runtime = await _buildRuntime(auth);
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            overrides: [appRuntimeProvider.overrideWithValue(runtime)],
            child: const CampusCardFeature(),
          ),
        ),
      );

      final featureFinder = find.byType(CampusCardFeature);
      expect(featureFinder, findsOneWidget);
      expect(_findLoadingIndicator(featureFinder), findsNothing);

      await tester.pump(const Duration(milliseconds: 30));

      expect(_findLoadingIndicator(featureFinder), findsNothing);
      expect(find.byType(PaymentCodePage), findsNothing);
      expect(find.byKey(const Key('payment-code-page')), findsNothing);

      pendingSession.complete(_ControllableAuthPort.authenticatedSnapshot);
      await _pumpFrames(tester, 20);

      expect(find.byType(PaymentCodePage), findsOneWidget);
      expect(find.byKey(const Key('payment-code-page')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'home pay-code entry shows light host-themed waiting page and loading indicator before authenticated route',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pendingSession = Completer<AuthSnapshot>();
      final auth = _ControllableAuthPort(localRestore: pendingSession.future);
      addTearDown(auth.dispose);
      final runtime = await _buildRuntime(auth);
      addTearDown(runtime.dispose);

      await _pumpHostAndOpenCampusCard(
        tester,
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF2F2F7),
          colorScheme: const ColorScheme.light(
            surface: Color(0xFFF2F2F7),
          ),
        ),
        entry: CampusCardEntry.paymentCode,
        runtime: runtime,
      );

      final pageFinder = find.byType(CampusCardPage);
      expect(pageFinder, findsOneWidget);

      final surfaceColor = _findFullSizeOpaqueSurfaceColor(tester, pageFinder);
      expect(surfaceColor, isNotNull);
      expect(surfaceColor!.computeLuminance(), greaterThan(0.5));
      expect(_findLoadingIndicator(pageFinder), findsAtLeastNWidgets(1));

      expect(find.byType(PaymentCodePage), findsNothing);
      expect(find.byKey(const Key('payment-code-page')), findsNothing);
      expect(find.byKey(const Key('payment-code-qr')), findsNothing);
      expect(find.byType(CardManageScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(SessionRestoreScreen), findsNothing);

      pendingSession.complete(_ControllableAuthPort.authenticatedSnapshot);
      await _pumpFrames(tester, 20);

      expect(find.byType(PaymentCodePage), findsOneWidget);
      expect(find.byKey(const Key('payment-code-page')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'home pay-code entry waiting page follows dark host theme while restoring local session',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pendingSession = Completer<AuthSnapshot>();
      final auth = _ControllableAuthPort(localRestore: pendingSession.future);
      addTearDown(auth.dispose);
      final runtime = await _buildRuntime(auth);
      addTearDown(runtime.dispose);

      await _pumpHostAndOpenCampusCard(
        tester,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0A0A),
          colorScheme: const ColorScheme.dark(
            surface: Color(0xFF0A0A0A),
          ),
        ),
        entry: CampusCardEntry.paymentCode,
        runtime: runtime,
      );

      final pageFinder = find.byType(CampusCardPage);
      expect(pageFinder, findsOneWidget);

      final surfaceColor = _findFullSizeOpaqueSurfaceColor(tester, pageFinder);
      expect(surfaceColor, isNotNull);
      expect(surfaceColor!.computeLuminance(), lessThan(0.2));
      expect(_findLoadingIndicator(pageFinder), findsAtLeastNWidgets(1));
      expect(find.byType(PaymentCodePage), findsNothing);
      expect(find.byKey(const Key('payment-code-page')), findsNothing);

      pendingSession.complete(_ControllableAuthPort.authenticatedSnapshot);
      await _pumpFrames(tester, 20);

      expect(find.byType(PaymentCodePage), findsOneWidget);
      expect(find.byKey(const Key('payment-code-page')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'card management entry still routes to CardManageScreen after local session restore',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pendingSession = Completer<AuthSnapshot>();
      final auth = _ControllableAuthPort(localRestore: pendingSession.future);
      addTearDown(auth.dispose);
      final runtime = await _buildRuntime(auth);
      addTearDown(runtime.dispose);

      await _pumpHostAndOpenCampusCard(
        tester,
        theme: ThemeData.light(),
        entry: CampusCardEntry.cardManagement,
        runtime: runtime,
      );

      expect(find.byType(CardManageScreen), findsNothing);
      expect(find.byType(PaymentCodePage), findsNothing);

      pendingSession.complete(_ControllableAuthPort.authenticatedSnapshot);
      await _pumpFrames(tester, 20);

      expect(find.byType(CardManageScreen), findsOneWidget);
      expect(find.byKey(const Key('card-manage-page')), findsOneWidget);
      expect(find.byType(PaymentCodePage), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'signed-out local snapshot still routes to LoginScreen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pendingSession = Completer<AuthSnapshot>();
      final auth = _ControllableAuthPort(localRestore: pendingSession.future);
      addTearDown(auth.dispose);
      final runtime = await _buildRuntime(auth);
      addTearDown(runtime.dispose);

      await _pumpHostAndOpenCampusCard(
        tester,
        theme: ThemeData.light(),
        entry: CampusCardEntry.paymentCode,
        runtime: runtime,
      );

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(PaymentCodePage), findsNothing);

      pendingSession.complete(const AuthSnapshot(state: AuthState.signedOut));
      await _pumpFrames(tester, 20);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(PaymentCodePage), findsNothing);
      expect(find.byType(SessionRestoreScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'local session restore error still routes to SessionRestoreScreen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pendingSession = Completer<AuthSnapshot>();
      final auth = _ControllableAuthPort(localRestore: pendingSession.future);
      addTearDown(auth.dispose);
      final runtime = await _buildRuntime(auth);
      addTearDown(runtime.dispose);

      await _pumpHostAndOpenCampusCard(
        tester,
        theme: ThemeData.light(),
        entry: CampusCardEntry.paymentCode,
        runtime: runtime,
      );

      expect(find.byType(SessionRestoreScreen), findsNothing);
      expect(find.byType(PaymentCodePage), findsNothing);

      pendingSession.completeError(StateError('local session unreadable'));
      await _pumpFrames(tester, 20);

      expect(find.byType(SessionRestoreScreen), findsOneWidget);
      expect(find.byType(PaymentCodePage), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

Future<void> _pumpHostAndOpenCampusCard(
  WidgetTester tester, {
  required ThemeData theme,
  required CampusCardEntry entry,
  required AppRuntime runtime,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                unawaited(
                  pushAdaptivePage<void>(
                    context,
                    builder: (_) => CampusCardPage(
                      entry: entry,
                      runtime: runtime,
                    ),
                  ),
                );
              },
              child: const Text('亮码'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('亮码'));
  await _pumpFrames(tester, 15);
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Finder _findLoadingIndicator(Finder scope) {
  return find.descendant(
    of: scope,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is ProgressIndicator || widget is CupertinoActivityIndicator,
    ),
  );
}

Color? _findFullSizeOpaqueSurfaceColor(WidgetTester tester, Finder scope) {
  final scopeSize = tester.getSize(scope);
  bool coversViewport(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final size = renderObject.size;
    return size.width >= scopeSize.width - 1 &&
        size.height >= scopeSize.height - 1;
  }

  final scaffolds = find.descendant(
    of: scope,
    matching: find.byType(Scaffold),
  );
  for (final element in scaffolds.evaluate()) {
    if (!coversViewport(element)) continue;
    final scaffold = element.widget as Scaffold;
    final color =
        scaffold.backgroundColor ?? Theme.of(element).scaffoldBackgroundColor;
    if (color.a > 0.9) return color;
  }

  final coloredBoxes = find.descendant(
    of: scope,
    matching: find.byType(ColoredBox),
  );
  for (final element in coloredBoxes.evaluate()) {
    if (!coversViewport(element)) continue;
    final box = element.widget as ColoredBox;
    if (box.color.a > 0.9) return box.color;
  }

  final materials = find.descendant(
    of: scope,
    matching: find.byType(Material),
  );
  for (final element in materials.evaluate()) {
    if (!coversViewport(element)) continue;
    final material = element.widget as Material;
    if (material.type == MaterialType.transparency) continue;
    final color = material.color ?? Theme.of(element).canvasColor;
    if (color.a > 0.9) return color;
  }

  final decoratedBoxes = find.descendant(
    of: scope,
    matching: find.byType(DecoratedBox),
  );
  for (final element in decoratedBoxes.evaluate()) {
    if (!coversViewport(element)) continue;
    final box = element.widget as DecoratedBox;
    final decoration = box.decoration;
    if (decoration is BoxDecoration &&
        decoration.color != null &&
        decoration.color!.a > 0.9) {
      return decoration.color;
    }
  }

  return null;
}

Future<AppRuntime> _buildRuntime(AuthPort auth) async {
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

final class _ControllableAuthPort implements AuthPort {
  _ControllableAuthPort({required this.localRestore});

  final Future<AuthSnapshot> localRestore;
  final StreamController<AuthSnapshot> _changes =
      StreamController<AuthSnapshot>.broadcast(sync: true);

  static const authenticatedSnapshot = AuthSnapshot(
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
  Future<AuthSnapshot> restoreLocal() => localRestore;

  @override
  Future<AuthSnapshot> restore() async => authenticatedSnapshot;

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async =>
      authenticatedSnapshot;

  @override
  Future<void> signOut() async {}

  Future<void> dispose() => _changes.close();
}
