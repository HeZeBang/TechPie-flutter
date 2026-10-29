import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/pages/assignments_page.dart';
import 'package:techpie/pages/hidden_assignments_page.dart';
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
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/adaptive_page_navigation.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';

/// On iOS the tab bar is the app's top level: a page pushed from a tab stays
/// inside that tab, under the bar, so another tab is always one tap away and
/// coming back finds the tab where it was left. A second tap on the selected
/// tab unwinds its stack, as UITabBarController does.
void main() {
  late AppRuntime runtime;
  late AssignmentService assignmentService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    runtime = await buildDemoRuntime();
  });

  tearDown(() async {
    await runtime.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // A portrait phone, where the tab bar can tell a tap on the selected tab.
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    assignmentService = assignments;

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
    'ignored items can scroll above the tab bar and the selection toolbar',
    (tester) async {
      await pumpApp(tester);
      selectTab(tester, 3);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SettingsPage));
      ServiceProvider.of(context).assignmentService.overrides.hidden.addAll(
        List.generate(30, (index) => 'hidden-$index'),
      );
      unawaited(
        pushAdaptivePage<void>(
          context,
          builder: (_) => const HiddenAssignmentsPage(),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byType(HiddenAssignmentsPage),
        matching: find.byType(ListView),
      );
      await tester.drag(list, const Offset(0, -4000));
      await tester.pumpAndSettle();
      final lastRow = find.ancestor(
        of: find.text('hidden-29'),
        matching: find.byType(ListTile),
      );
      expect(tester.getBottomLeft(lastRow).dy, lessThanOrEqualTo(874 - 49));

      tester.widget<IosNativeNavigationBar>(
        find.byType(IosNativeNavigationBar),
      ).onItemPressed!('select');
      await tester.pumpAndSettle();
      expect(tester.widget<ListView>(list).padding, EdgeInsets.zero);
      await tester.drag(list, const Offset(0, -400));
      await tester.pumpAndSettle();
      final restore = find.byWidgetPredicate(
        (widget) => widget is CNButton && widget.label == '恢复',
      );
      expect(
        tester.getBottomLeft(lastRow).dy,
        lessThanOrEqualTo(tester.getTopLeft(restore).dy),
      );
      tester.widget<IosNativeNavigationBar>(
        find.byType(IosNativeNavigationBar),
      ).onItemPressed!('done');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

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
      // The bar is part of the pushed page's safe area, as a tab bar
      // controller's is for its children: exactly the 49pt it covers (the test
      // view has no home indicator), not the transparent headroom above it.
      expect(
        MediaQuery.paddingOf(tester.element(find.byKey(detail))).bottom,
        49,
      );

      // Another tab is one tap away, and the detail waits in its own tab.
      selectTab(tester, 0);
      await tester.pumpAndSettle();
      expect(find.byKey(detail), findsNothing);
      selectTab(tester, 3);
      await tester.pumpAndSettle();
      expect(find.byKey(detail), findsOneWidget);

      // Tapping the selected tab returns it to its root. UITabBar does not
      // report a reselect, so this is a real tap on the item, not the plugin's
      // callback.
      final bar = tester.getRect(find.byType(CNTabBar));
      await tester.tapAt(Offset(bar.left + bar.width * 7 / 8, bar.top + 24));
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

  testWidgets(
    'selecting hides the tab bar only while the selecting page is on screen',
    (tester) async {
      await pumpApp(tester);
      await assignmentService.hide(
        Assignment(
          id: 'hw1',
          platform: 'gradescope',
          title: 'Homework 1',
          course: 'CS101',
          due: DateTime(2030),
        ),
      );
      selectTab(tester, 2);
      await tester.pumpAndSettle();
      unawaited(
        pushAdaptivePage<void>(
          tester.element(find.byType(AssignmentsPage)),
          builder: (_) => const HiddenAssignmentsPage(),
        ),
      );
      await tester.pumpAndSettle();
      final barHeight = tester.getSize(find.byType(CNTabBar)).height;
      expect(barHeight, greaterThan(0));

      final bar = tester.widget<IosNativeNavigationBar>(find.byType(IosNativeNavigationBar).last);
      bar.onItemPressed!('select');
      await tester.pumpAndSettle();
      expect(find.text('选择项目'), findsOneWidget);
      expect(tester.getSize(find.byType(CNTabBar)).height, 0);

      // Something pushed into the same tab (a deep link) gets the bar back…
      const covering = Key('covering');
      unawaited(
        pushAdaptivePage<void>(
          tester.element(find.byType(HiddenAssignmentsPage)),
          builder: (_) => const Scaffold(key: covering),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CNTabBar)).height, barHeight);

      // …and selection resumes with it hidden again on the way back.
      Navigator.of(tester.element(find.byKey(covering))).pop();
      await tester.pumpAndSettle();
      expect(find.text('选择项目'), findsOneWidget);
      expect(tester.getSize(find.byType(CNTabBar)).height, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
