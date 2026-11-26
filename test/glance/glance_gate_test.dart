import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/glance/presentation/glance_shell.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/screen_form_factor.dart';
import 'package:techpie/pages/campus_card_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/glance_settings_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/screen_form_factor_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/app_shell/app_shell.dart';

const _flipInfo = ScreenFormFactorInfo(
  isFlipDevice: true,
  isRearDevice: false,
  displayId: 0,
  windowWidthPx: 809,
  windowHeightPx: 1392,
  density: 2.75,
  densityDpi: 440,
  isDefaultDisplay: true,
  isInMultiWindowMode: false,
  model: 'MIX Flip',
  manufacturer: 'Xiaomi',
  sdkInt: 36,
);

Future<void> _pumpApp(
  WidgetTester tester, {
  required Size size,
  AppRuntime? runtime,
  bool privacyAccepted = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({'privacy_accepted_v1': privacyAccepted});
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  final uniAuth = UniAuthService();
  final auth = AuthService(storage, http, uniAuth);
  final theme = ThemeService(storage);
  final tpAuth = ThirdPartyAuthService(storage, http);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
  final formFactor = ScreenFormFactorService(
    loader: () async => _flipInfo,
    androidOverride: true,
  );
  await formFactor.refresh();
  final glanceSettings = GlanceSettings(storage);

  await tester.pumpWidget(
    TechPieApp(
      authService: auth,
      debugLogger: logger,
      storageService: storage,
      themeService: theme,
      scheduleService: schedule,
      assignmentService: assignments,
      thirdPartyAuthService: tpAuth,
      oaGymService: OaGymService(auth, storage, tpAuth),
      egateAppService: EgateAppService(auth, storage, tpAuth),
      uniAuthService: uniAuth,
      syncService: SyncService(auth, tpAuth, storage),
      updateService: UpdateService(),
      ecardBindService: EcardBindService(),
      campusCardService: runtime == null
          ? CampusCardService.withStore(InMemorySecureCredentialStore())
          : CampusCardService.withStore(
              InMemorySecureCredentialStore(),
              runtimeFactory: () => runtime,
            ),
      screenFormFactorService: formFactor,
      glanceSettings: glanceSettings,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester, [AppRuntime? runtime]) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await runtime?.dispose();
}

void main() {
  testWidgets('cover waits for privacy consent before showing campus data', (tester) async {
    await _pumpApp(tester, size: const Size(506, 439), privacyAccepted: false);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.byType(GlanceShell), findsNothing);

    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('隐私政策'), findsNothing);
    expect(find.byType(GlanceShell), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a flip cover shows the glance and hides the full app', (
    tester,
  ) async {
    await _pumpApp(tester, size: const Size(506, 439));

    expect(find.byType(GlanceShell), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(find.text('请先在完整 App 登录'), findsOneWidget);

    await _close(tester);
  });

  testWidgets('the inner screen keeps the full app', (tester) async {
    await _pumpApp(tester, size: const Size(390, 844));

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(GlanceShell), findsNothing);

    await _close(tester);
  });

  testWidgets('fold and unfold preserve the selected settings tab', (
    tester,
  ) async {
    await _pumpApp(tester, size: const Size(390, 844));
    await tester.tap(find.text('我的').first);
    await tester.pumpAndSettle();
    expect(find.text('登录 TechPie'), findsOneWidget);

    tester.view.physicalSize = const Size(506, 439);
    await tester.pumpAndSettle();
    expect(find.byType(GlanceShell), findsOneWidget);
    expect(find.text('登录 TechPie'), findsNothing);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('登录 TechPie'), findsOneWidget);

    await _close(tester);
  });

  testWidgets('an eCard tap is consumed by the glance, not the hidden shell', (
    tester,
  ) async {
    final runtime = await buildDemoRuntime();
    await runtime.auth.signIn(const DemoAuthCredential());
    await _pumpApp(
      tester,
      size: const Size(506, 439),
      runtime: runtime,
    );

    appShellPendingEcardEntry.value = CampusCardEntry.paymentCode;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(appShellPendingEcardEntry.value, isNull);
    expect(
      find.byType(CampusCardPage, skipOffstage: false),
      findsNothing,
    );
    expect(find.byKey(const Key('glance-payment-qr')), findsOneWidget);
    expect(find.text('在线付款码'), findsOneWidget);

    await _close(tester, runtime);
  });
}
