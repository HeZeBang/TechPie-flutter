import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course_table.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/assignments_page.dart';
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
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_allowance_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar_tokens.dart';

class _SignedInAuth extends AuthService {
  _SignedInAuth(super.storage, super.http, super.uniAuth, this._session);

  final UserSession _session;

  @override
  bool get isLoggedIn => true;

  @override
  UserSession? get session => _session;
}

class _BoundThirdParty extends ThirdPartyAuthService {
  _BoundThirdParty(super.storage, super.http);

  @override
  bool get hasIdsBinding => true;
}

Future<
    ({
      StorageService storage,
      Widget Function(Widget child) wrap,
      TechPieApp app,
    })> _createHarness({
  Map<String, Object> prefs = const {},
  bool signedIn = true,
  bool bindIds = false,
  List<EamsCourse>? courses,
  List<Assignment>? cachedAssignments,
}) async {
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final initialPrefs = <String, Object>{
    'privacy_accepted_v1': true,
    ...prefs,
  };
  if (courses != null) {
    final termCalendar = TermCalendar(
      code: 200,
      schoolYearTerm: '2026-2027-1',
      termBegin: monday,
      snapshotDate: null,
      snapshotWeekOfTerm: null,
      allTeachWeeks: 16,
      allTermWeeks: 18,
      amClasses: 4,
      pmClasses: 5,
      eveClasses: 4,
    );
    final table = CourseTable(
      periods: const [
        CoursePeriod(index: 1, timeRange: '08:15-09:00'),
        CoursePeriod(index: 2, timeRange: '09:10-09:55'),
        CoursePeriod(index: 3, timeRange: '10:15-11:00'),
        CoursePeriod(index: 4, timeRange: '11:10-11:55'),
      ],
      courses: courses,
    );
    initialPrefs['schedule_selected_semester'] = 'term1';
    initialPrefs['schedule_term_begin_term1'] =
        jsonEncode(termCalendar.toJson());
    initialPrefs['schedule_course_table_term1'] = jsonEncode(table.toJson());
  }
  if (cachedAssignments != null) {
    initialPrefs['cached_assignments'] =
        jsonEncode(cachedAssignments.map((a) => a.toJson()).toList());
  }

  SharedPreferences.setMockInitialValues(initialPrefs);
  final storage = StorageService(await SharedPreferences.getInstance());
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  addTearDown(http.close);
  final uniAuth = UniAuthService();
  final session = UserSession(
    userId: 'gp-uuid-98765',
    userName: 'Henry',
    schoolName: '上海科技大学',
    createdAt: DateTime(2026, 9, 1),
  );
  final auth = signedIn
      ? _SignedInAuth(storage, http, uniAuth, session)
      : AuthService(storage, http, uniAuth);
  final tpAuth = bindIds
      ? _BoundThirdParty(storage, http)
      : ThirdPartyAuthService(storage, http);
  final themeService = ThemeService(storage);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  await schedule.loadCachedData();
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule)
    ..loadCached();
  final oaGym = OaGymService(auth, storage, tpAuth);
  final egate = EgateAppService(auth, storage, tpAuth);
  final allowance = StudentAllowanceService(auth, tpAuth);
  final sync = SyncService(auth, tpAuth, storage);
  final update = UpdateService();
  final campusCard = CampusCardService();
  final ecardBind = EcardBindService();

  Widget wrap(Widget child) => ServiceProvider(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: themeService,
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: oaGym,
        egateAppService: egate,
        studentAllowanceService: allowance,
        uniAuthService: uniAuth,
        syncService: sync,
        updateService: update,
        campusCardService: campusCard,
        ecardBindService: ecardBind,
        child: MaterialApp(theme: themeService.lightTheme, home: child),
      );

  final app = TechPieApp(
    authService: auth,
    debugLogger: logger,
    storageService: storage,
    themeService: themeService,
    scheduleService: schedule,
    assignmentService: assignments,
    thirdPartyAuthService: tpAuth,
    oaGymService: oaGym,
    egateAppService: egate,
    uniAuthService: uniAuth,
    syncService: sync,
    updateService: update,
    campusCardService: campusCard,
    ecardBindService: ecardBind,
  );

  return (storage: storage, wrap: wrap, app: app);
}

void main() {
  testWidgets(
      'Settings shows plain username + GeekPie Uni-Auth without trailing id, updated subtitle, reordered proxy, and hides Huawei Watch on non-Android',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final h = await _createHarness(signedIn: true);
    await tester.pumpWidget(h.wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Henry'), findsOneWidget);
    expect(find.text('GeekPie Uni-Auth'), findsOneWidget);
    expect(find.textContaining('gp-uuid-98765'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings.mask-personal-info')),
      findsNothing,
    );
    expect(
      find.text('已绑定 0 / 4 项 · IDS / eCard / Gradescope / Hydro'),
      findsOneWidget,
    );
    expect(find.text('Huawei Watch'), findsNothing);

    final feedbackY = tester.getTopLeft(find.text('问题反馈 / 功能建议')).dy;
    final aboutY = tester.getTopLeft(find.text('关于 TechPie')).dy;
    final proxyY = tester
        .getTopLeft(find.byKey(const ValueKey('settings.app-proxy-address')))
        .dy;
    expect(feedbackY, lessThan(aboutY));
    expect(aboutY, lessThan(proxyY));
  });

  testWidgets(
      'Home shows personalized greeting, 3x2 quick actions without duplicate Campus Card, and includes late-window deadlines',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final lateWindowItem = Assignment(
      id: 'hw-late-1',
      platform: 'gradescope',
      course: 'CS100',
      title: 'Late Window Homework',
      due: now.subtract(const Duration(hours: 2)),
      lateDue: now.add(const Duration(hours: 6)),
    );

    final h = await _createHarness(
      signedIn: true,
      cachedAssignments: [lateWindowItem],
    );
    await tester.pumpWidget(h.wrap(const HomePage()));
    await tester.pumpAndSettle();

    // Greeting includes signed-in username.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home.greeting-header')),
        matching: find.textContaining('，Henry'),
      ),
      findsOneWidget,
    );

    // Quick actions removes duplicate Campus Card tile (leaves 6 symmetric items).
    final quickActions = find.byKey(const ValueKey('home.quick-actions'));
    expect(
      find.descendant(of: quickActions, matching: find.text('校园卡')),
      findsNothing,
    );
    expect(
      find.descendant(of: quickActions, matching: find.text('课程录播')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quickActions, matching: find.text('学生津贴')),
      findsOneWidget,
    );

    // Home Deadlines card includes active late-window assignment.
    expect(find.text('Late Window Homework'), findsOneWidget);
    expect(find.textContaining('迟交剩余'), findsOneWidget);
  });

  testWidgets(
      'DesktopShell restores persisted sidebar collapsed state on launch',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final h = await _createHarness(
      prefs: {'desktop_sidebar_collapsed': true},
    );
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      closeTo(DesktopSidebarTokens.collapsedWidth, 0.5),
    );
  });

  testWidgets(
      'SchedulePage smart weekend auto-hides empty Sat/Sun, auto-shows when scheduled, and persists explicit preferences',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 1. Weekday-only semester hides Sat & Sun automatically.
    final weekdayOnly = await _createHarness(
      signedIn: true,
      bindIds: true,
      courses: const [
        EamsCourse(
          name: '算法设计',
          classroom: '教学中心 101',
          teachers: '李老师',
          weeks: '0111111111111111111',
          times: {1: [1, 2]},
        ),
      ],
    );
    await tester.pumpWidget(weekdayOnly.wrap(const SchedulePage()));
    await tester.pumpAndSettle();

    expect(find.text('一'), findsOneWidget);
    expect(find.text('五'), findsOneWidget);
    expect(find.text('六'), findsNothing);
    expect(find.text('日'), findsNothing);

    // Explicit toggle persists Saturday visibility & view mode.
    await tester.tap(find.byTooltip('视图设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示周六'));
    await tester.pumpAndSettle();
    expect(weekdayOnly.storage.scheduleShowSaturday, isTrue);
    expect(find.text('六'), findsOneWidget);

    // Dismiss popover and switch to 日程 mode.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    expect(weekdayOnly.storage.scheduleViewMode, 'agenda');

    // 2. Semester with a Saturday course auto-shows Saturday even with no override.
    final withSaturday = await _createHarness(
      signedIn: true,
      bindIds: true,
      courses: const [
        EamsCourse(
          name: '周末研讨课',
          classroom: '报告厅',
          teachers: '王老师',
          weeks: '0111111111111111111',
          times: {6: [3, 4]},
        ),
      ],
    );
    await tester.pumpWidget(
      withSaturday.wrap(const SchedulePage(key: ValueKey('schedule-with-sat'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('六'), findsOneWidget);
    expect(find.text('日'), findsNothing);
  });

  testWidgets(
      'AssignmentsPage persists and restores showAssignments / showExams filters',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final h = await _createHarness(
      prefs: {'deadlines_show_exams': false},
    );
    await tester.pumpWidget(h.wrap(const AssignmentsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示作业'));
    await tester.pumpAndSettle();

    expect(h.storage.deadlinesShowAssignments, isFalse);
    expect(h.storage.deadlinesShowExams, isFalse);
  });
}
