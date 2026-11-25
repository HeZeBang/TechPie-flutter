import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/auth/ecard_bind_code_client.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/ports/auth_port.dart';
import 'package:techpie/features/campus_card/domain/ports/credential_store.dart';
import 'package:techpie/pages/campus_card_account_page.dart';
import 'package:techpie/pages/sync_settings_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_hijack.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_allowance_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';

void main() {
  const openId = 'SYNTHETIC_OPENID_0123456789ABCDEF';
  const bindOpenId = 'SYNTHETIC_OPENID_FROM_CODE';

  late InMemorySecureCredentialStore secureStore;
  late SecureSessionCredentialStore sessionStore;
  late _ScriptedAuthPort auth;
  late CampusCardService service;
  late _ScriptedTunnel tunnel;
  List<String>? resolvedAddresses;

  /// Mounts the editor on a phone-width, tall surface: the page is taller than
  /// the default 800x600 test window, and a ListView never builds what falls
  /// below the fold — which would silently hide the controls under test.
  Future<Widget> mount(WidgetTester tester, {bool fromCard = false}) async {
    resolvedAddresses = null;
    tester.view.physicalSize = const Size(780, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final logger = DebugLogger()..enabled = true;
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final hostAuth = AuthService(storage, http, uniAuth);
    final theme = ThemeService(storage);
    final tpAuth = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, hostAuth, tpAuth);
    final assignments = AssignmentService(storage, http, hostAuth, tpAuth, schedule);
    final oaGym = OaGymService(hostAuth, storage, tpAuth);
    final egateApp = EgateAppService(hostAuth, storage, tpAuth);
    final studentAllowance = StudentAllowanceService(hostAuth, tpAuth);
    addTearDown(studentAllowance.dispose);

    secureStore = InMemorySecureCredentialStore();
    sessionStore = SecureSessionCredentialStore(secureStore);
    auth = _ScriptedAuthPort(sessionStore);
    addTearDown(auth.dispose);
    final base = await buildDemoRuntime();
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
      scanner: base.scanner,
      disposeRuntime: base.dispose,
    );
    service = CampusCardService.withStore(
      secureStore,
      runtimeFactory: () => runtime,
    );
    addTearDown(service.dispose);
    // Sync is built after the card service it pushes to, exactly as main.dart
    // wires them.
    final sync = SyncService(hostAuth, tpAuth, storage, ecard: service);

    tunnel = _ScriptedTunnel();
    final bindService = EcardBindService(
      hijack: tunnel,
      client: EcardBindCodeClient(
        send: (method, url, headers, body) async => method == 'GET'
            ? (200, '{"ok": true, "codes": 0}')
            : (
                200,
                '{"ok":true,"openid":"$bindOpenId","usertype":"8","orgid":"2"}',
              ),
      ),
      // The platform resolver is a network call; the page cares what it answers.
      resolve: (host) async =>
          resolvedAddresses ??
          <String>[
            tunnel.current == EcardBindHijackStatus.active
                ? EcardBindHijackService.targetIp
                : '10.17.0.54',
          ],
    );

    return ServiceProvider(
      authService: hostAuth,
      debugLogger: logger,
      storageService: storage,
      themeService: theme,
      scheduleService: schedule,
      assignmentService: assignments,
      thirdPartyAuthService: tpAuth,
      oaGymService: oaGym,
      egateAppService: egateApp,
      studentAllowanceService: studentAllowance,
      uniAuthService: uniAuth,
      syncService: sync,
      updateService: UpdateService(),
      campusCardService: service,
      ecardBindService: bindService,
      child: MaterialApp(home: CampusCardAccountPage(fromCard: fromCard)),
    );
  }

  Future<void> showPermission(WidgetTester tester) async {
    await tester.tap(find.text('Connect my card'));
    await tester.pumpAndSettle();
  }

  Future<void> showCode(WidgetTester tester) async {
    await showPermission(tester);
    await tester.tap(find.text('Review permission'));
    await tester.pumpAndSettle();
  }

  Future<void> submitCode(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('ecard-bind-code-field')), '123456');
    await tester.tap(find.text('Connect eCard'));
    await tester.pump();
  }

  Future<void> enterOpenId(WidgetTester tester, String value) async {
    await tester.tap(find.byKey(const Key('openid-field')));
    tester.testTextInput.enterText(value);
    await tester.pump();
  }

  testWidgets('iOS setup actions use native button adapters', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(await mount(tester));
    await tester.pumpAndSettle();
    final connect =
        find.byWidgetPredicate((widget) => widget is CNButton && widget.label == 'Connect my card');
    expect(connect, findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    tester.widget<CNButton>(connect).onPressed!();
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CNButton && widget.label == 'Review permission',
      ),
      findsOneWidget,
    );
    final cancel =
        find.byWidgetPredicate((widget) => widget is CNButton && widget.label == 'Cancel setup');
    expect(cancel, findsOneWidget);
    tester.widget<CNButton>(cancel).onPressed!();
    await tester.pumpAndSettle();
    expect(connect, findsOneWidget);
    expect(tunnel.startCalls, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('setup asks for consent and shows one task at a time', (tester) async {
    await tester.pumpWidget(await mount(tester));
    await tester.pumpAndSettle();
    expect(find.textContaining('OPENID'), findsNothing);
    expect(find.textContaining('Step '), findsNothing);
    expect(find.byKey(const Key('ecard-bind-code-field')), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(CNButton), findsNothing);
    await showPermission(tester);
    expect(find.text('Allow a temporary VPN'), findsOneWidget);
    expect(tunnel.startCalls, 0);
    expect(find.textContaining('Step '), findsNothing);
    await tester.tap(find.text('Cancel setup'));
    await tester.pumpAndSettle();
    expect(find.text('Connect my card'), findsOneWidget);
  });

  testWidgets('connected accounts show only the masked identifier and may disconnect',
      (tester) async {
    final app = await mount(tester);
    await service.connect(openId, channel: EcardOpenIdChannel.alipay);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.text(service.maskedOpenId!), findsOneWidget);
    expect(find.text(openId), findsNothing);
    expect(find.text('Change account'), findsNothing);
    expect(find.text('Connect my card'), findsNothing);
    await tester.tap(find.text('Disconnect eCard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep connected'));
    await tester.pumpAndSettle();
    expect(await service.readOpenId(), openId);
    await tester.tap(find.text('Disconnect eCard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(await service.readOpenId(), isNull);
    expect(find.text('Connect my card'), findsOneWidget);
  });

  testWidgets('connection waits for the temporary VPN to stop', (tester) async {
    await tester.pumpWidget(await mount(tester));
    await tester.pumpAndSettle();
    await showCode(tester);
    final stopping = Completer<void>();
    tunnel.stopWait = stopping.future;
    auth.beforeSignIn = () => expect(tunnel.current, EcardBindHijackStatus.inactive);
    await submitCode(tester);
    expect(auth.signInCalls, 0);
    expect(find.text('Connecting your card…'), findsOneWidget);
    expect(find.text('Retry connection'), findsNothing);
    stopping.complete();
    await tester.pumpAndSettle();
    expect(auth.signInCalls, 1);
    expect(await service.readOpenId(), bindOpenId);
    expect(find.text('Your eCard is ready'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect eCard'), findsOneWidget);
    expect(tunnel.stopCalls, 1);
  });

  testWidgets('retry uses the existing credential after the VPN actually stops', (tester) async {
    await tester.pumpWidget(await mount(tester));
    await tester.pumpAndSettle();
    await showCode(tester);
    tunnel.stayActiveAfterStop = true;
    await submitCode(tester);
    await tester.pumpAndSettle();
    expect(find.text(bindOpenId), findsNothing);
    expect(await service.readOpenId(), isNull);
    expect(find.text('Retry connection'), findsOneWidget);
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(auth.signInCalls, 0);
    tunnel.stayActiveAfterStop = false;
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(await service.readOpenId(), bindOpenId);
  });

  testWidgets('network restoration gates login and retry keeps the code redemption',
      (tester) async {
    await tester.pumpWidget(await mount(tester));
    await tester.pumpAndSettle();
    await showCode(tester);
    resolvedAddresses = [EcardBindHijackService.targetIp];
    await submitCode(tester);
    await tester.pumpAndSettle();
    expect(auth.signInCalls, 0);
    expect(await service.readOpenId(), isNull);
    expect(
      find.text('Your normal connection has not returned yet. Try again shortly.'),
      findsOneWidget,
    );
    resolvedAddresses = ['10.17.0.54'];
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(auth.signInCalls, 1);
  });

  testWidgets('a failed sign-in leaves the account disconnected', (tester) async {
    await tester.pumpWidget(await mount(tester));
    await tester.pumpAndSettle();
    auth.signInFailure = const AppFailure(FailureKind.network, '网络不可用，请稍后重试');
    await showCode(tester);
    await submitCode(tester);
    await tester.pumpAndSettle();
    expect(await service.readOpenId(), isNull);
    expect(find.text('Check your network and try again.'), findsOneWidget);
    await tester.tap(find.text('Cancel setup'));
    await tester.pumpAndSettle();
    expect(find.text('Connect my card'), findsOneWidget);
  });

  testWidgets('system back cancels an active setup and restores the network', (tester) async {
    await tester.pumpWidget(await mount(tester));
    await tester.pumpAndSettle();
    await showCode(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tunnel.stopCalls, 1);
    expect(find.text('Connect my card'), findsOneWidget);
    expect(await service.readOpenId(), isNull);
  });

  testWidgets('invalid code restores networking and reports the error', (tester) async {
    await tester.pumpWidget(await mount(tester));
    await tester.pumpAndSettle();
    await showCode(tester);
    await tester.tap(find.text('Connect eCard'));
    await tester.pumpAndSettle();
    expect(find.text('Check your binding code and try again.'), findsOneWidget);
    expect(tunnel.stopCalls, 1);
    expect(auth.signInCalls, 0);
  });

  testWidgets('a refused or unsuccessful VPN start leaves the user at consent', (tester) async {
    await tester.pumpWidget(await mount(tester));
    await tester.pumpAndSettle();
    await showPermission(tester);
    for (final status in [EcardBindHijackStatus.denied, EcardBindHijackStatus.inactive]) {
      tunnel.startStatus = status;
      await tester.tap(find.text('Review permission'));
      await tester.pumpAndSettle();
      expect(find.text('Allow a temporary VPN'), findsOneWidget);
      expect(find.byKey(const Key('ecard-bind-code-field')), findsNothing);
    }
  });

  testWidgets('unknown VPN state offers cleanup', (tester) async {
    final app = await mount(tester);
    tunnel.current = EcardBindHijackStatus.unknown;
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop temporary VPN'));
    await tester.pumpAndSettle();
    expect(tunnel.startCalls, 0);
    expect(tunnel.stopCalls, 1);
    expect(find.text('Connect my card'), findsOneWidget);
  });

  testWidgets(
    'desktop users can connect from the campus card with a manual OPENID',
    (tester) async {
      final app = await mount(tester, fromCard: true);
      tunnel.current = EcardBindHijackStatus.unsupported;
      tester.view.physicalSize = const Size(2080, 1380);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Open Cloud sync'), findsOneWidget);
      expect(find.byKey(const Key('ecard-bind-hijack-button')), findsNothing);
      await tester.tap(find.text(EcardOpenIdChannel.wechat.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(EcardOpenIdChannel.alipay.label).last);
      await tester.pumpAndSettle();
      await enterOpenId(tester, '  $openId  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(await service.readOpenId(), openId);
      expect(await service.readOpenIdChannel(), EcardOpenIdChannel.alipay);
      expect(find.text('Your eCard is ready'), findsOneWidget);
      expect(find.byKey(const Key('openid-field')), findsNothing);
      expect(tunnel.startCalls, 0);
      expect(tunnel.stopCalls, 0);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'desktop manual binding validates input and keeps it after a connection failure',
    (tester) async {
      final app = await mount(tester);
      tunnel.current = EcardBindHijackStatus.unsupported;
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final connect = find.byKey(const Key('openid-save-button'));
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid OPENID.'), findsOneWidget);
      expect(auth.signInCalls, 0);

      resolvedAddresses = [EcardBindHijackService.targetIp];
      await enterOpenId(tester, openId);
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(
        find.text('Your normal connection has not returned yet. Try again shortly.'),
        findsOneWidget,
      );
      expect(await service.readOpenId(), isNull);
      expect(auth.signInCalls, 0);

      resolvedAddresses = ['10.17.0.54'];
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(await service.readOpenId(), openId);
      expect(await service.readOpenIdChannel(), EcardOpenIdChannel.wechat);
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets('unsupported device uses the existing Cloud sync screen', (tester) async {
    final app = await mount(tester);
    tunnel.current = EcardBindHijackStatus.unsupported;
    tester.view.physicalSize = const Size(2080, 1380);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.textContaining('OPENID'), findsNothing);
    await tester.tap(find.text('Open Cloud sync'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncSettingsPage), findsOneWidget);
    expect(tunnel.startCalls, 0);
  });

  testWidgets('Chinese setup has no step counter or manual entry', (tester) async {
    final app = await mount(tester);
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接我的校园卡'));
    await tester.pumpAndSettle();
    expect(find.text('允许临时使用 VPN'), findsOneWidget);
    expect(find.textContaining('第 2 步'), findsNothing);
    expect(find.textContaining('OPENID'), findsNothing);
  });
}

/// Scripted DNS tunnel: the page can ask it to come up, and the test can decide
/// what the platform answers — including a refused consent dialog, which no host
/// fake can produce otherwise.
final class _ScriptedTunnel implements EcardBindHijackPort {
  EcardBindHijackStatus startStatus = EcardBindHijackStatus.active;
  EcardBindHijackStatus current = EcardBindHijackStatus.inactive;
  int startCalls = 0;
  int stopCalls = 0;
  Future<void>? stopWait;
  bool stayActiveAfterStop = false;

  @override
  Future<EcardBindHijackStatus> start() async {
    startCalls += 1;
    current = startStatus;
    return current;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    await stopWait;
    if (!stayActiveAfterStop) current = EcardBindHijackStatus.inactive;
  }

  @override
  Future<EcardBindHijackStatus> status() async => current;
}

/// Identity port that records what the form asked for and can be told to refuse,
/// so the page's success and failure branches are both reachable without a network.
final class _ScriptedAuthPort implements AuthPort, OpenIdAuthVerifier {
  _ScriptedAuthPort(this._sessionStore);

  final SessionCredentialStore _sessionStore;
  final _changes = StreamController<AuthSnapshot>.broadcast(sync: true);

  Object? signInFailure;
  int signInCalls = 0;
  VoidCallback? beforeSignIn;

  @override
  Stream<AuthSnapshot> get changes => _changes.stream;

  @override
  Future<AuthSnapshot> restoreLocal() => restore();

  @override
  Future<AuthSnapshot> restore() async {
    final openId = await _sessionStore.readOpenId();
    return openId == null ? const AuthSnapshot(state: AuthState.signedOut) : _authenticated();
  }

  @override
  Future<void> verifyOpenId(
    String openId, {
    EcardOpenIdChannel channel = EcardOpenIdChannel.wechat,
  }) async {
    OpenIdAuthCredential(openId: openId).validate();
  }

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async {
    beforeSignIn?.call();
    final failure = signInFailure;
    if (failure != null) throw failure;
    final openIdCredential = credential as OpenIdAuthCredential;
    await verifyOpenId(
      openIdCredential.openId,
      channel: openIdCredential.channel,
    );
    signInCalls += 1;
    await _sessionStore.writeSession(
      sessionCookie: 'JSESSIONID=synthetic',
      openId: openIdCredential.openId,
      orgId: '2',
      verifiedIdSerial: 'SYNTHETIC-STUDENT',
      verifiedCardId: 'SYNTHETIC-CARD',
      channel: openIdCredential.channel,
    );
    final snapshot = _authenticated();
    _changes.add(snapshot);
    return snapshot;
  }

  @override
  Future<void> signOut() async {
    await _sessionStore.clear();
    _changes.add(const AuthSnapshot(state: AuthState.signedOut));
  }

  AuthSnapshot _authenticated() => const AuthSnapshot(
        state: AuthState.authenticated,
        session: AuthSession(
          subjectId: 'synthetic',
          orgId: '2',
          maskedIdentity: 'SYNT****CDEF',
        ),
      );

  Future<void> dispose() => _changes.close();
}
