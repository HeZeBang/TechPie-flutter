import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:techpie/main.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/widgets/app_shell/app_shell.dart';

void main() {
  testWidgets('iOS-style destination switching lazily preserves visited pages',
      (
    WidgetTester tester,
  ) async {
    var selectedIndex = 0;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return AppDestinationSwitcher(
              pages: const [
                _StatefulDestination(label: 'First'),
                _StatefulDestination(label: 'Second'),
              ],
              selectedIndex: selectedIndex,
              previousSelectedIndex: 0,
              preserveVisitedPages: true,
              animationsEnabled: true,
            );
          },
        ),
      ),
    );

    expect(find.text('First: 0'), findsOneWidget);
    expect(find.text('Second: 0'), findsNothing);
    await tester.tap(find.text('First: 0'));
    await tester.pump();

    setHostState(() => selectedIndex = 1);
    await tester.pump();
    expect(find.text('First: 1'), findsNothing);
    expect(find.text('Second: 0'), findsOneWidget);

    setHostState(() => selectedIndex = 0);
    await tester.pump();
    expect(find.text('First: 1'), findsOneWidget);
    expect(find.text('Second: 0'), findsNothing);
  });

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
        uniAuthService: uniAuth,
        syncService: sync,
      ),
    );

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(
      navigationBar.overlayColor?.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    // Starts on Home
    expect(find.text('Welcome to TechPie'), findsOneWidget);

    // Tap Schedule
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    // Not logged in, so shows login prompt
    expect(find.byIcon(Icons.calendar_month), findsOneWidget);
    expect(find.text('登录以查看课表'), findsOneWidget);

    // Tap Deadlines
    await tester.tap(find.text('Deadlines'));
    await tester.pumpAndSettle();
    expect(find.text('No upcoming deadlines'), findsOneWidget);

    // Tap Settings
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
  });
}

class _StatefulDestination extends StatefulWidget {
  const _StatefulDestination({required this.label});

  final String label;

  @override
  State<_StatefulDestination> createState() => _StatefulDestinationState();
}

class _StatefulDestinationState extends State<_StatefulDestination> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _count++),
      child: Text('${widget.label}: $_count'),
    );
  }
}
