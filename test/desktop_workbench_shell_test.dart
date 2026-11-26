import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/assignments_page.dart';
import 'package:techpie/pages/campus_services_page.dart';
import 'package:techpie/pages/grades_page.dart';
import 'package:techpie/pages/home_page.dart';
import 'package:techpie/pages/schedule_page.dart';
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
import 'package:techpie/utils/adaptive_layout.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_shell.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar_tokens.dart';
import 'package:techpie/widgets/app_shell/mobile_shell.dart';
import 'package:techpie/widgets/app_shell/tg_bottom_nav_bar.dart';

class _TestSignedInAuth extends AuthService {
  _TestSignedInAuth(super.storage, super.http, super.uniAuth);

  @override
  bool get isLoggedIn => true;

  @override
  UserSession? get session => UserSession(
        userId: '20260001',
        userName: '测试用户',
        schoolName: 'ShanghaiTech',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _TestBoundThirdParty extends ThirdPartyAuthService {
  _TestBoundThirdParty(super.storage, super.http);

  static final ThirdPartyAccount _ids = ThirdPartyAccount(
    platform: ThirdPartyPlatform.ids,
    account: '20260001',
    sid: '20260001',
    name: '测试用户',
    email: 'test@example.edu.cn',
    token: 'mock-token',
    boundAt: DateTime(2026, 1, 1),
  );

  @override
  bool get hasIdsBinding => true;

  @override
  ThirdPartyAccount? get idsAccount => _ids;

  @override
  List<ThirdPartyPlatform> get boundPlatforms => const [ThirdPartyPlatform.ids];
}

Future<({TechPieApp app, StorageService storage})> _pumpWorkbenchApp(
  WidgetTester tester, {
  Size windowSize = const Size(1280, 800),
  Map<String, Object> extraPrefs = const {},
}) async {
  tester.view.physicalSize = windowSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({
    'privacy_accepted_v1': true,
    ...extraPrefs,
  });
  final storage = StorageService(await SharedPreferences.getInstance());
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  addTearDown(http.close);
  final uniAuth = UniAuthService();
  final auth = _TestSignedInAuth(storage, http, uniAuth);
  final tpAuth = _TestBoundThirdParty(storage, http);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  await schedule.loadCachedData();
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule)
    ..loadCached();
  final campusCard = CampusCardService();

  final app = TechPieApp(
    authService: auth,
    debugLogger: logger,
    storageService: storage,
    themeService: ThemeService(storage),
    scheduleService: schedule,
    assignmentService: assignments,
    thirdPartyAuthService: tpAuth,
    oaGymService: OaGymService(auth, storage, tpAuth),
    egateAppService: EgateAppService(auth, storage, tpAuth),
    uniAuthService: uniAuth,
    syncService: SyncService(auth, tpAuth, storage),
    updateService: UpdateService(),
    campusCardService: campusCard,
    ecardBindService: EcardBindService(),
  );
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return (app: app, storage: storage);
}

Future<void> _sendChord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey? modifier,
  bool settle = true,
}) async {
  if (modifier != null) {
    await tester.sendKeyDownEvent(modifier);
  }
  try {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
  } finally {
    if (modifier != null) {
      await tester.sendKeyUpEvent(modifier);
    }
  }
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets(
    'desktop medium width (600-959dp) auto-collapses sidebar rail while mobile stays on MobileShell',
    (tester) async {
      await _pumpWorkbenchApp(tester, windowSize: const Size(760, 800));

      expect(find.byType(DesktopShell), findsOneWidget);
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.byType(MobileShell), findsNothing);
      expect(
        tester.getSize(find.byType(DesktopSidebar)).width,
        closeTo(DesktopSidebarTokens.collapsedWidth, 0.5),
      );
      expect(
        find.byKey(const ValueKey('desktop.sidebar-toggle')),
        findsNothing,
      );

      // Expanding to >=960dp restores user's non-collapsed sidebar & toggle button.
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(DesktopSidebar)).width,
        greaterThan(DesktopSidebarTokens.collapsedWidth),
      );
      expect(
        find.byKey(const ValueKey('desktop.sidebar-toggle')),
        findsOneWidget,
      );

      // Shrinking <600dp falls back cleanly to MobileShell.
      tester.view.physicalSize = const Size(500, 800);
      await tester.pumpAndSettle();
      expect(find.byType(MobileShell), findsOneWidget);
      expect(find.byType(TgBottomNavBar), findsOneWidget);
      expect(find.byType(DesktopSidebar), findsNothing);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'mobile target at 760dp stays on MobileShell and omits PlatformMenuBar',
    (tester) async {
      await _pumpWorkbenchApp(tester, windowSize: const Size(760, 800));
      expect(
        usesDesktopSidebarShell(tester.element(find.byType(MobileShell))),
        isFalse,
      );
      expect(find.byType(MobileShell), findsOneWidget);
      expect(find.byType(DesktopSidebar), findsNothing);
      expect(find.byType(PlatformMenuBar), findsNothing);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'sidebar exposes command trigger, Campus Services, and compact account summary with PlatformMenuBar on macOS',
    (tester) async {
      await _pumpWorkbenchApp(tester);

      expect(find.byType(PlatformMenuBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop.command-palette-trigger')),
        findsOneWidget,
      );
      expect(find.text('⌘K'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop.sidebar-campus-services')),
        findsOneWidget,
      );

      final accountTile = find.byKey(const ValueKey('desktop.sidebar-account'));
      expect(accountTile, findsOneWidget);
      expect(
        find.descendant(of: accountTile, matching: find.text('测试用户')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: accountTile, matching: find.text('已绑定 1 项服务')),
        findsOneWidget,
      );

      // Tapping account footer opens the Settings/Profile tab.
      await tester.tap(accountTile);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);

      // Tapping Campus Services opens CampusServicesPage, and Cmd+[ pops back.
      await tester.tap(
        find.byKey(const ValueKey('desktop.sidebar-campus-services')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CampusServicesPage), findsOneWidget);

      await _sendChord(
        tester,
        LogicalKeyboardKey.bracketLeft,
        modifier: LogicalKeyboardKey.metaLeft,
      );
      expect(find.byType(CampusServicesPage), findsNothing);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'desktop global shortcuts switch tabs, toggle sidebar, open/filter command palette, and guard R inside TextField',
    (tester) async {
      final built = await _pumpWorkbenchApp(tester);

      // Linux shows Ctrl K shortcut label and does not mount macOS PlatformMenuBar.
      expect(find.byType(PlatformMenuBar), findsNothing);
      expect(find.text('Ctrl K'), findsOneWidget);

      // Ctrl+2 -> Schedule (SchedulePage shows loading spinner without cached semester),
      // then Ctrl+3 -> Deadlines, Ctrl+4 -> Settings, Ctrl+1 -> Home.
      await _sendChord(
        tester,
        LogicalKeyboardKey.digit2,
        modifier: LogicalKeyboardKey.controlLeft,
        settle: false,
      );
      expect(find.byType(SchedulePage), findsOneWidget);

      await _sendChord(
        tester,
        LogicalKeyboardKey.digit3,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(find.byType(AssignmentsPage), findsOneWidget);

      await _sendChord(
        tester,
        LogicalKeyboardKey.digit4,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(find.byType(SettingsPage), findsOneWidget);

      await _sendChord(
        tester,
        LogicalKeyboardKey.digit1,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(find.byType(HomePage), findsOneWidget);

      // Ctrl+\ toggles sidebar collapse state.
      await _sendChord(
        tester,
        LogicalKeyboardKey.backslash,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(built.storage.desktopSidebarCollapsed, isTrue);
      await _sendChord(
        tester,
        LogicalKeyboardKey.backslash,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(built.storage.desktopSidebarCollapsed, isFalse);

      // Plain R refreshes when no text field is focused.
      await _sendChord(tester, LogicalKeyboardKey.keyR, settle: false);
      expect(find.text('正在刷新数据…'), findsOneWidget);
      adaptiveFeedbackHostKey.currentState?.dismiss();
      await tester.pump(const Duration(milliseconds: 250));

      // Ctrl+K opens command palette; typing filters services; Enter launches item.
      await _sendChord(
        tester,
        LogicalKeyboardKey.keyK,
        modifier: LogicalKeyboardKey.controlLeft,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.byKey(const ValueKey('desktop.command-palette')),
        findsOneWidget,
      );

      // Ctrl+K while open toggles it closed.
      await _sendChord(
        tester,
        LogicalKeyboardKey.keyK,
        modifier: LogicalKeyboardKey.controlLeft,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.byKey(const ValueKey('desktop.command-palette')),
        findsNothing,
      );

      // Re-open palette, search 'gpa', verify match and ArrowDown/Enter navigation.
      await _sendChord(
        tester,
        LogicalKeyboardKey.keyK,
        modifier: LogicalKeyboardKey.controlLeft,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(
        find.byKey(const ValueKey('desktop.command-palette-input')),
        'gpa',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('成绩与 GPA'), findsOneWidget);

      await _sendChord(tester, LogicalKeyboardKey.enter, settle: false);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(GradesPage), findsOneWidget);

      // Pressing Escape pops active pushed route back to Home.
      await _sendChord(tester, LogicalKeyboardKey.escape, settle: false);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(GradesPage), findsNothing);

      // Also verify ArrowDown navigation inside command palette (default list).
      await _sendChord(
        tester,
        LogicalKeyboardKey.keyK,
        modifier: LogicalKeyboardKey.controlLeft,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _sendChord(tester, LogicalKeyboardKey.arrowDown, settle: false);
      await _sendChord(tester, LogicalKeyboardKey.enter, settle: false);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(SchedulePage), findsOneWidget);

      // Inside CampusServicesPage search field, pressing keyR does NOT trigger refresh.
      await tester.tap(
        find.byKey(const ValueKey('desktop.sidebar-campus-services')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CampusServicesPage), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await _sendChord(tester, LogicalKeyboardKey.keyR, settle: false);
      expect(find.text('正在刷新数据…'), findsNothing);
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );
}
