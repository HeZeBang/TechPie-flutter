import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:techpie/main.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/widgets/app_shell/tg_bottom_nav_bar.dart';

void main() {
  testWidgets('App shell renders with desktop sidebar', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final logger = DebugLogger();
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
      ),
    );

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Schedule'), findsWidgets);
    expect(find.text('Deadlines'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('Navigation switches pages', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    final tpAuth = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, tpAuth);
    final assignments =
        AssignmentService(storage, http, auth, tpAuth, schedule);
    final oaGym = OaGymService(auth, storage, tpAuth);
    final egateApp = EgateAppService(auth, storage, tpAuth);
    final sync = SyncService(auth, tpAuth, storage);

    await tester.pumpWidget(
      TechPieApp(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: ThemeService(storage),
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: oaGym,
        egateAppService: egateApp,
        uniAuthService: uniAuth,
        syncService: sync,
      ),
    );

    expect(find.byType(TgBottomNavBar), findsOneWidget);
    // Starts on Home
    expect(find.text('Welcome to TechPie'), findsOneWidget);

    // Tap Schedule
    await tester.tap(find.text('Schedule').first);
    await tester.pumpAndSettle();
    // Not logged in, so shows login prompt
    expect(find.byIcon(Icons.calendar_month), findsOneWidget);
    expect(find.text('登录以查看课表'), findsOneWidget);

    // Tap Deadlines
    await tester.tap(find.text('Deadlines').first);
    await tester.pumpAndSettle();
    expect(find.text('No upcoming deadlines'), findsOneWidget);

    // Tap Settings
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
  });
}
