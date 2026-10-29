import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/main.dart';
import 'package:techpie/pages/settings_page.dart';
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
import 'package:techpie/widgets/adaptive_page_navigation.dart';

/// On iOS the tab bar is the app's top level: a page pushed from a tab stays
/// inside that tab, under the bar, so another tab is always one tap away and
/// coming back finds the tab where it was left. A second tap on the selected
/// tab unwinds its stack, as UITabBarController does.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    runtime = await buildDemoRuntime();
  });

  tearDown(() async {
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

  void selectTab(WidgetTester tester, int index) =>
      tester.widget<CNTabBar>(find.byType(CNTabBar)).onTap(index);

  testWidgets(
    'a pushed page keeps the tab bar, and each tab keeps its own stack',
    (tester) async {
      await pumpApp(tester);
      selectTab(tester, 3);
      await tester.pumpAndSettle();

      const detail = Key('settings-detail');
      unawaited(
        pushAdaptivePage<void>(
          tester.element(find.byType(SettingsPage)),
          builder: (_) => const Scaffold(key: detail),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(detail), findsOneWidget);
      expect(find.byType(CNTabBar), findsOneWidget);

      // Another tab is one tap away, and the detail waits in its own tab.
      selectTab(tester, 0);
      await tester.pumpAndSettle();
      expect(find.byKey(detail), findsNothing);
      selectTab(tester, 3);
      await tester.pumpAndSettle();
      expect(find.byKey(detail), findsOneWidget);

      // Tapping the selected tab returns it to its root.
      selectTab(tester, 3);
      await tester.pumpAndSettle();
      expect(find.byKey(detail), findsNothing);
      expect(find.byType(SettingsPage), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'a page pushed on the root navigator covers the tab bar',
    (tester) async {
      await pumpApp(tester);
      selectTab(tester, 3);
      await tester.pumpAndSettle();

      const modal = Key('full-screen');
      unawaited(
        pushAdaptivePage<void>(
          tester.element(find.byType(SettingsPage)),
          rootNavigator: true,
          builder: (_) => const Scaffold(key: modal),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(modal), findsOneWidget);
      expect(find.byType(CNTabBar), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
