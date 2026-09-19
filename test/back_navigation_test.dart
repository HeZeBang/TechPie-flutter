import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/main.dart';
import 'package:techpie/pages/debug_log_page.dart';
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

void main() {
  // A wide window is the whole point: below the sidebar breakpoint the settings
  // page pushes subpages onto the root navigator, and the back gesture works by
  // accident. Above it, they get a stack of their own.
  testWidgets('the system back leaves a settings subpage rather than the app', (
    WidgetTester tester,
  ) async {
    // Wide enough for the non-compact layout, and tall enough that the debug
    // tiles at the bottom of the settings list are not under the navigation bar —
    // a tap on an obscured tile does nothing, silently.
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    // The settings page hides its debug tiles unless debug mode is on, and those
    // are the only subpages reachable without an account.
    final logger = DebugLogger()..enabled = true;
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    final theme = ThemeService(storage);
    final tpAuth = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, tpAuth);
    final assignments =
        AssignmentService(storage, http, auth, tpAuth, schedule);
    final oaGym = OaGymService(auth, storage, tpAuth);
    final egateApp = EgateAppService(auth, storage, tpAuth);
    final sync = SyncService(auth, tpAuth, storage);

    // What the framework asks the platform to do is how "the app closed" is
    // observable here: a back no navigator handles ends in SystemNavigator.pop.
    final platformCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      TechPieApp(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: theme,
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: oaGym,
        egateAppService: egateApp,
        uniAuthService: uniAuth,
        syncService: sync,
        updateService: UpdateService(),
        campusCardService: CampusCardService(),
        ecardBindService: EcardBindService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();

    // Only the debug section is reachable without an account; the window above is
    // tall enough for it to be on screen.
    await tester.tap(find.text('View Logs'));
    await tester.pumpAndSettle();
    expect(find.byType(DebugLogPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      platformCalls,
      isNot(contains('SystemNavigator.pop')),
      reason: 'the back gesture left the subpage, so the app must not be asked to close',
    );
    expect(find.byType(DebugLogPage), findsNothing);
  });
}
