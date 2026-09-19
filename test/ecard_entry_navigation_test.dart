import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/main.dart';
import 'package:techpie/pages/campus_card_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/app_shell/app_shell.dart';
import 'package:techpie/widgets/blurred_app_bar.dart';

/// The eCard home widget asks TechPie for the payment code without a page to
/// push onto: on a cold start the shell does not exist yet, and while the app
/// runs it is the shell — not the feature — that knows where the page belongs.
/// These pin that hand-off: the intent is expressed once, the shell consumes it
/// exactly once, and the page it pushes behaves like any other page of the
/// destination the user is on.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    runtime = await buildDemoRuntime();
    await runtime.auth.signIn(const DemoAuthCredential());
    appShellPendingEcardEntry.value = null;
  });

  tearDown(() async {
    appShellPendingEcardEntry.value = null;
    await runtime.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
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
        campusCardService: CampusCardService.withStore(
          InMemorySecureCredentialStore(),
          runtimeFactory: () => runtime,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a tap that arrives before the shell exists still opens the code', (
    tester,
  ) async {
    // The widget was tapped while TechPie was still starting: main can only
    // record the intent, and the shell has to honour it once it mounts.
    appShellPendingEcardEntry.value = CampusCardEntry.paymentCode;

    await pumpApp(tester);

    expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
    expect(find.byType(CampusCardPage), findsOneWidget);
    expect(
      appShellPendingEcardEntry.value,
      isNull,
      reason: 'the intent is consumed once, not replayed on every rebuild',
    );
  });

  testWidgets('a tap opens the code over the destination the user is on', (
    tester,
  ) async {
    // The wide window is the case with a stack per destination, and the settings
    // destination is where the widget's page is reachable from.
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(find.byType(CampusCardPage), findsNothing);

    appShellPendingEcardEntry.value = CampusCardEntry.paymentCode;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
    expect(find.byType(CampusCardPage), findsOneWidget);
    expect(appShellPendingEcardEntry.value, isNull);

    // Inside the shell the page fills its content area, sidebar included: the bar
    // spans the page rather than sitting in the middle of it.
    expect(
      tester.getSize(find.byType(BlurredAppBar)).width,
      tester.getSize(find.byKey(const Key('payment-code-page'))).width,
    );

    // It went onto the destination the user was on, so one back leaves the
    // feature instead of the app, and lands back where they were.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CampusCardPage), findsNothing);
    expect(find.text('Settings'), findsWidgets);
  });
}
