import 'dart:convert';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course.dart';
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
import 'package:techpie/theme/theme.dart';
import 'package:techpie/widgets/adaptive_checkbox.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';
import 'package:techpie/widgets/adaptive_navigation_scaffold.dart';
import 'package:techpie/widgets/course_detail_panel.dart';
import 'package:techpie/widgets/design_system/design_system.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';

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

Future<({Widget widget, StorageService storage})> _buildTestHost({
  required Widget child,
  bool signedIn = false,
  Map<String, Object> prefsValues = const {},
  CampusCardService? campusCardService,
  UpdateService? updateService,
}) async {
  SharedPreferences.setMockInitialValues({
    'privacy_accepted_v1': true,
    ...prefsValues,
  });
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  addTearDown(http.close);
  final uniAuth = UniAuthService();
  final session = UserSession(
    userId: '20240001',
    userName: '张同学',
    schoolName: 'ShanghaiTech',
    createdAt: DateTime(2026, 1, 1),
  );
  final auth = signedIn
      ? _SignedInAuth(storage, http, uniAuth, session)
      : AuthService(storage, http, uniAuth);
  final tpAuth = signedIn ? _BoundThirdParty(storage, http) : ThirdPartyAuthService(storage, http);
  final themeService = ThemeService(storage);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  await schedule.loadCachedData();
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule)..loadCached();

  final widget = ServiceProvider(
    authService: auth,
    debugLogger: logger,
    storageService: storage,
    themeService: themeService,
    scheduleService: schedule,
    assignmentService: assignments,
    thirdPartyAuthService: tpAuth,
    oaGymService: OaGymService(auth, storage, tpAuth),
    egateAppService: EgateAppService(auth, storage, tpAuth),
    studentAllowanceService: StudentAllowanceService(auth, tpAuth),
    uniAuthService: uniAuth,
    syncService: SyncService(auth, tpAuth, storage),
    updateService: updateService ?? UpdateService(),
    campusCardService: campusCardService ?? CampusCardService(),
    ecardBindService: EcardBindService(),
    child: ListenableBuilder(
      listenable: themeService,
      builder: (context, _) => MaterialApp(
        theme: themeService.lightTheme,
        darkTheme: themeService.darkTheme,
        themeMode: themeService.themeMode,
        builder: (_, inner) => AdaptiveFeedbackHost(
          key: adaptiveFeedbackHostKey,
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  return (widget: widget, storage: storage);
}

void main() {
  for (final width in [360.0, 1280.0]) {
    testWidgets('edit and reset a grid title at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const fullName = '普通物理学（上）(PHYS1001)';
      const table = CourseTable(
        periods: [
          CoursePeriod(index: 1, timeRange: '08:15-09:00'),
          CoursePeriod(index: 2, timeRange: '09:10-09:55'),
        ],
        courses: [
          EamsCourse(
            name: fullName,
            classroom: 'H101',
            teachers: '',
            weeks: '011',
            times: {
              1: [1, 2],
            },
          ),
        ],
      );
      final host = await _buildTestHost(
        signedIn: true,
        prefsValues: {
          'schedule_selected_semester': 'term',
          'schedule_course_table_term': jsonEncode(table.toJson()),
        },
        child: const SchedulePage(),
      );
      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();
      expect(find.text('H101'), findsWidgets);
      await tester.tap(find.text('普物（上）').first);
      await tester.pumpAndSettle();
      expect(find.text(fullName), findsOneWidget);

      Future<void> edit(String input, String action) async {
        await tester.tap(find.byTooltip('编辑课表简称'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), input);
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
      }

      await edit('力学', '保存');
      expect(find.text('力学'), findsWidgets);
      final reopened = StorageService(await SharedPreferences.getInstance());
      expect(reopened.courseShortName(null, 'course:$fullName'), '力学');
      expect(reopened.courseShortName('another account', 'course:$fullName'), isNull);
      await tester.tap(find.text('力学').first);
      await tester.pumpAndSettle();
      expect(find.text('课表简称 · 力学'), findsOneWidget);
      await edit('丢弃', '取消');
      await tester.tap(find.text('力学').first);
      await tester.pumpAndSettle();
      expect(find.text('课表简称 · 力学'), findsOneWidget);
      await edit('  ', '保存');
      await tester.tap(find.text('普物（上）').first);
      await tester.pumpAndSettle();
      expect(find.text('课表简称 · 普物（上）'), findsOneWidget);
      expect(reopened.courseShortName(null, 'course:$fullName'), isNull);
      expect(find.text(fullName), findsOneWidget);
    });
  }

  testWidgets(
    'SchedulePage agenda scrolls across weeks and updates the header',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final monday = DateUtils.addDaysToDate(now, 1 - now.weekday);
      final examDue = now.add(const Duration(days: 20));
      const earlierCourse = '本周较早的课程';

      final termCalendar = TermCalendar(
        code: 200,
        schoolYearTerm: '2026-2027-1',
        termBegin: DateUtils.addDaysToDate(monday, -7),
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
        ],
        courses: [
          EamsCourse(
            name: '计算机系统导论',
            classroom: '信息学院 1B-201',
            teachers: '王老师',
            weeks: '00100000000000000',
            times: {
              now.weekday: const [1, 2],
            },
          ),
          if (now.weekday > DateTime.monday)
            const EamsCourse(
              name: earlierCourse,
              classroom: '教学中心 102',
              teachers: '陈老师',
              weeks: '00100000000000000',
              times: {
                DateTime.monday: [1],
              },
            ),
          const EamsCourse(
            name: '上周课程',
            classroom: '教学中心 101',
            teachers: '陈老师',
            weeks: '01000000000000000',
            times: {
              DateTime.monday: [1],
            },
          ),
          const EamsCourse(
            name: '下周课程',
            classroom: '教学中心 103',
            teachers: '陈老师',
            weeks: '00010000000000000',
            times: {
              DateTime.monday: [1],
            },
          ),
        ],
      );

      final exam = ExamAssignment(
        id: 'term1:exam-1',
        title: '计算机系统导论 期末考试',
        course: '计算机系统导论',
        semesterId: 'term1',
        due: examDue,
        location: '教学中心 301',
        batchName: '期末考试',
      );

      final host = await _buildTestHost(
        signedIn: true,
        prefsValues: {
          'schedule_selected_semester': 'term1',
          'schedule_term_begin_term1': jsonEncode(termCalendar.toJson()),
          'schedule_course_table_term1': jsonEncode(table.toJson()),
          'cached_assignments': jsonEncode([exam.toJson()]),
        },
        child: const SchedulePage(),
      );

      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      // Smart weekend default hides Sat/Sun when semester has only weekday classes.
      expect(find.text('一'), findsOneWidget);
      expect(find.text('六'), now.weekday == DateTime.saturday ? findsOneWidget : findsNothing);
      expect(find.text('日'), now.weekday == DateTime.sunday ? findsOneWidget : findsNothing);

      expect(
        find.byKey(const ValueKey('schedule.view-mode-switch')),
        findsOneWidget,
      );
      expect(find.text('周课表'), findsOneWidget);
      expect(find.text('日程'), findsOneWidget);

      final thumbBefore = tester.getTopLeft(
        find.byKey(const ValueKey('schedule.view-mode-thumb')),
      );
      await tester.tap(find.text('日程'));
      await tester.pump();
      // The first frame shows today's course, with earlier days above it.
      expect(find.text('计算机系统导论').hitTestable(), findsOneWidget);
      expect(find.text(earlierCourse).hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(host.storage.scheduleViewMode, 'agenda');
      final thumbAfter = tester.getTopLeft(
        find.byKey(const ValueKey('schedule.view-mode-thumb')),
      );
      expect(thumbAfter.dx, greaterThan(thumbBefore.dx + 40));

      expect(find.byType(TpAccentRow), findsWidgets);
      expect(find.text('计算机系统导论'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule.upcoming-exams')),
        findsOneWidget,
      );
      expect(find.text('近期考试'), findsOneWidget);
      expect(find.text('计算机系统导论 期末考试'), findsOneWidget);

      final agenda = find.byType(CustomScrollView);
      final position = tester.widget<CustomScrollView>(agenda).controller!.position;
      Finder headerWeek(int week) => find.descendant(
            of: find.byType(AppBar),
            matching: find.text('第 $week 周'),
          );
      expect(headerWeek(2), findsOneWidget);

      await tester.drag(agenda, const Offset(0, 440));
      await tester.pumpAndSettle();
      expect(headerWeek(1), findsOneWidget);
      expect(find.text('上周课程').hitTestable(), findsOneWidget);
      expect(tester.widget<CustomScrollView>(agenda).controller!.position, same(position));
      final floatingToday = find.byType(FloatingActionButton);
      expect(floatingToday, findsOneWidget);
      expect(
        tester.widget<Icon>(find.descendant(of: floatingToday, matching: find.byType(Icon))).icon,
        Icons.keyboard_arrow_down,
      );
      expect(find.byTooltip('下一周'), findsNothing);

      await tester.tap(headerWeek(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一周'));
      await tester.pumpAndSettle();
      expect(headerWeek(2), findsOneWidget);
      expect(find.text('计算机系统导论').hitTestable(), findsOneWidget);
      expect(find.text(earlierCourse).hitTestable(), findsNothing);
      expect(floatingToday, findsNothing);

      await tester.timedDrag(agenda, const Offset(0, -320), const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(headerWeek(3), findsOneWidget);
      expect(find.text('下周课程').hitTestable(), findsOneWidget);
      expect(tester.widget<CustomScrollView>(agenda).controller!.position, same(position));

      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(headerWeek(18), findsOneWidget);

      tester.view.physicalSize = const Size(600, 812);
      await tester.pumpAndSettle();
      expect(floatingToday, findsOneWidget);
      expect(
        tester.widget<Icon>(find.descendant(of: floatingToday, matching: find.byType(Icon))).icon,
        Icons.keyboard_arrow_up,
      );

      tester.view.physicalSize = const Size(359, 812);
      await tester.pumpAndSettle();
      expect(floatingToday, findsOneWidget);
      expect(tester.getSize(floatingToday), const Size(48, 48));
      await tester.tap(floatingToday);
      await tester.pumpAndSettle();
      expect(headerWeek(2), findsOneWidget);
      expect(find.text('计算机系统导论').hitTestable(), findsOneWidget);
      expect(floatingToday, findsNothing);

      if (now.weekday > DateTime.monday) {
        position.jumpTo(-52);
        await tester.pumpAndSettle();
        expect(headerWeek(2), findsOneWidget);
        expect(floatingToday, findsOneWidget);
      }

      tester.view.physicalSize = const Size(390, 812);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(floatingToday, findsOneWidget);
    },
  );

  testWidgets(
    'SchedulePage auto-shows scheduled weekend column and persists explicit weekend override',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
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
      const table = CourseTable(
        periods: [
          CoursePeriod(index: 1, timeRange: '08:15-09:00'),
          CoursePeriod(index: 2, timeRange: '09:10-09:55'),
        ],
        courses: [
          EamsCourse(
            name: '周末研讨课',
            classroom: '报告厅',
            teachers: '王老师',
            weeks: '01111111111111111',
            times: {
              6: [1, 2],
            },
          ),
        ],
      );

      final host = await _buildTestHost(
        signedIn: true,
        prefsValues: {
          'schedule_selected_semester': 'term1',
          'schedule_term_begin_term1': jsonEncode(termCalendar.toJson()),
          'schedule_course_table_term1': jsonEncode(table.toJson()),
        },
        child: const SchedulePage(),
      );
      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      expect(find.text('六'), findsOneWidget);
      expect(find.text('日'), findsNothing);

      await tester.tap(find.byTooltip('视图设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示周日'));
      await tester.pumpAndSettle();
      expect(host.storage.scheduleShowSunday, isTrue);
      expect(find.text('日'), findsOneWidget);
    },
  );

  testWidgets(
    'AssignmentsPage renders borderless TpCard items and persists filter preferences',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final upcomingDue = DateTime.now().add(const Duration(hours: 10));
      final assignment = Assignment(
        id: 'hw-1',
        platform: 'gradescope',
        title: 'Lab 3: Virtual Memory',
        course: 'CS110',
        due: upcomingDue,
        status: 'No Submission',
      );

      final host = await _buildTestHost(
        signedIn: true,
        prefsValues: {
          'cached_assignments': jsonEncode([assignment.toJson()]),
          'deadlines_show_exams': false,
        },
        child: const AssignmentsPage(),
      );

      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      expect(find.text('Lab 3: Virtual Memory'), findsOneWidget);
      expect(find.byType(TpCard), findsOneWidget);
      expect(find.byType(TpProgressBar), findsOneWidget);
      expect(find.byType(TpBadge), findsWidgets);

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示作业'));
      await tester.pumpAndSettle();
      expect(host.storage.deadlinesShowAssignments, isFalse);
      expect(host.storage.deadlinesShowExams, isFalse);
    },
  );

  testWidgets(
    'HomePage personalizes greeting, avoids duplicate Campus Card in quick actions, and includes late-window deadlines',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final lateWindow = Assignment(
        id: 'hw-late',
        platform: 'gradescope',
        course: 'CS100',
        title: 'Late Window Homework',
        due: now.subtract(const Duration(hours: 2)),
        lateDue: now.add(const Duration(hours: 6)),
      );

      final host = await _buildTestHost(
        signedIn: true,
        prefsValues: {
          'cached_assignments': jsonEncode([lateWindow.toJson()]),
        },
        child: const HomePage(),
      );
      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home.greeting-header')),
          matching: find.textContaining('，张同学'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home.quick-actions')),
          matching: find.text('校园卡'),
        ),
        findsNothing,
      );
      expect(find.text('Late Window Homework'), findsOneWidget);
      expect(find.textContaining('迟交剩余'), findsOneWidget);
    },
  );

  testWidgets('Home opens the campus hub and reads the saved shortcuts on return', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = await _buildTestHost(child: const HomePage());
    await tester.pumpWidget(host.widget);
    await tester.pumpAndSettle();
    final quick = find.byKey(const ValueKey('home.quick-actions'));
    await tester.tap(find.descendant(of: quick, matching: find.text('更多')));
    await tester.pumpAndSettle();
    expect(find.text('校园服务中心'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑首页快捷'));
    await tester.pumpAndSettle();
    for (final title in ['学生请假', '学生津贴']) {
      final tile = find.widgetWithText(AdaptiveCheckboxRow, title);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.descendant(of: quick, matching: find.text('学生津贴')), findsOneWidget);
    expect(find.descendant(of: quick, matching: find.text('学生请假')), findsNothing);
  });

  testWidgets(
    'SettingsPage renders restructured sections, places logout before deletion, and keeps desktop proxy configurable',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final host = await _buildTestHost(
        signedIn: true,
        child: const SettingsPage(),
      );

      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      expect(find.text('我的'), findsOneWidget);
      expect(find.text('张同学'), findsOneWidget);
      expect(find.text('GeekPie Uni-Auth'), findsOneWidget);
      expect(find.textContaining('20240001'), findsNothing);
      expect(find.text('Huawei Watch'), findsNothing);
      expect(find.text('设备与提醒'), findsNothing);
      expect(find.text('在线'), findsOneWidget);
      expect(find.text('第三方账号'), findsOneWidget);
      expect(find.text('云同步'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('网络'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings.app-proxy-address')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings.app-proxy-enabled')), findsNothing);
      expect(find.text('支持与关于'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);
      expect(find.text('账号操作'), findsOneWidget);
      expect(find.text('开发者'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings.developer-options')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings.debug-mode')), findsNothing);
      expect(find.byType(TpCard), findsWidgets);
      expect(find.byType(TpListRow), findsWidgets);

      final logoutTop = tester.getTopLeft(find.text('退出登录')).dy;
      final deleteTop = tester.getTopLeft(find.text('注销账号')).dy;
      expect(logoutTop, lessThan(deleteTop));

      // Desktop single-row proxy dialog configures both enabled switch and URL.
      await tester.tap(find.byKey(const ValueKey('settings.app-proxy-address')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings.app-proxy-enabled')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings.app-proxy-enabled')));
      await tester.enterText(find.byType(TextField), '127.0.0.1:7890');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(host.storage.appProxyEnabled, isTrue);
      expect(host.storage.appProxyUrl, '127.0.0.1:7890');
      expect(find.text('127.0.0.1:7890'), findsOneWidget);
    },
  );

  testWidgets(
    'Android SettingsPage hides in-app proxy and shows Huawei Watch under 设备与提醒',
    variant: TargetPlatformVariant.only(TargetPlatform.android),
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final host = await _buildTestHost(
        signedIn: true,
        child: const SettingsPage(),
      );

      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      expect(find.text('网络'), findsNothing);
      expect(find.byKey(const ValueKey('settings.app-proxy-address')), findsNothing);
      expect(find.text('设备与提醒'), findsOneWidget);
      expect(find.text('Huawei Watch'), findsOneWidget);
    },
  );

  testWidgets(
    'iOS settings show and check the App Store using simulator package metadata',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'TechPie',
        packageName: 'club.geekpie.techpie',
        version: '1.1.0',
        buildNumber: '32',
        buildSignature: '',
        installerStore: 'com.apple.simulator',
      );
      const alertChannel = MethodChannel('cn_alert');
      const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = tester.binding.defaultBinaryMessenger;
      final alertTitles = <String>[];
      final openedUrls = <String>[];
      messenger.setMockMethodCallHandler(alertChannel, (call) async {
        alertTitles.add(call.arguments['title'] as String);
        return {'index': 1};
      });
      messenger.setMockMethodCallHandler(launcherChannel, (call) async {
        openedUrls.add(call.arguments['url'] as String);
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(alertChannel, null);
        messenger.setMockMethodCallHandler(launcherChannel, null);
      });
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({
            'results': [
              {'trackId': 6771316576, 'version': '1.1.1'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final host = await _buildTestHost(
        child: const SettingsPage(),
        updateService: UpdateService(client: client),
      );
      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('settings.check-update'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(find.text('v1.1.0+32'), findsOneWidget);
      expect(find.text('点击检查 App Store 最新版本'), findsOneWidget);
      await tester.tap(row);
      await tester.pump();

      expect(
        requests,
        [Uri.parse('https://itunes.apple.com/lookup?id=6771316576')],
      );
      expect(alertTitles, ['发现新版本 1.1.1']);
      expect(openedUrls, ['itms-apps://apps.apple.com/app/id6771316576']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iOS settings hide proxy, use unified plain inline menus with TechRed tint and color dots, and keep logout row-aligned',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      final host = await _buildTestHost(signedIn: true, child: const SettingsPage());
      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      expect(find.text('网络'), findsNothing);
      expect(find.byKey(const ValueKey('settings.app-proxy-address')), findsNothing);
      expect(find.byKey(const ValueKey('settings.app-proxy-enabled')), findsNothing);
      expect(find.text('设备与提醒'), findsOneWidget);
      expect(find.text('Apple Watch'), findsOneWidget);
      expect(find.byType(TpListRow), findsWidgets);

      final logoutRow = find.byKey(const ValueKey('settings.logout'));
      final deleteRow = find.byKey(const ValueKey('settings.delete-account'));
      expect(logoutRow, findsOneWidget);
      expect(deleteRow, findsOneWidget);
      expect(tester.getTopLeft(logoutRow).dy, lessThan(tester.getTopLeft(deleteRow).dy));

      CNPopupMenuButton menuFor(String label) => tester.widget<CNPopupMenuButton>(
            find.byWidgetPredicate(
              (widget) => widget is CNPopupMenuButton && widget.semanticLabel == label,
            ),
          );

      final modeMenu = menuFor('主题模式');
      final colorMenu = menuFor('主题色');
      expect(modeMenu.buttonLabel, '跟随系统');
      expect(colorMenu.buttonLabel, '科技红 · TechRed');
      expect(modeMenu.buttonStyle, CNButtonStyle.plain);
      expect(colorMenu.buttonStyle, CNButtonStyle.plain);
      expect(modeMenu.tint, TpTokens.techRedLight);
      expect(colorMenu.tint, TpTokens.techRedLight);

      final items = colorMenu.items.whereType<CNPopupMenuItem>().toList();
      expect(items[0].label, '科技红 · TechRed');
      expect(items[0].icon?.color, TpTokens.techRedLight);
      expect(items[1].label, '系统蓝');
      expect(items[1].icon?.color, TpTokens.iosBlueLight);

      final systemIndex = colorMenu.items.indexWhere(
        (item) => item is CNPopupMenuItem && item.label == '系统蓝',
      );
      expect(systemIndex, isNonNegative);

      colorMenu.onSelected(systemIndex);
      await tester.pumpAndSettle();

      final updatedColorMenu = menuFor('主题色');
      expect(updatedColorMenu.buttonLabel, '系统蓝');
      expect(
        updatedColorMenu.tint,
        TpColors.light(accent: TpTokens.iosBlueLight).brandInk,
      );
      expect((updatedColorMenu.items[systemIndex] as CNPopupMenuItem).checked, isTrue);
      expect(host.storage.colorScheme, AppColorScheme.system.name);

      final body = find.ancestor(
        of: find.byType(ListView),
        matching: find.byWidgetPredicate(
          (widget) => widget is ClipRect && widget.clipper != null,
        ),
      );
      final clipper = tester.widget<ClipRect>(body).clipper!;
      expect(clipper.getClip(tester.getSize(body)).top, 0);

      final scroll = tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
      scroll.outerController.jumpTo(scroll.outerController.position.maxScrollExtent);
      await tester.pumpAndSettle();

      final clipTop = clipper.getClip(tester.getSize(body)).top;
      expect(tester.getTopLeft(body).dy + clipTop, closeTo(62 + 44, 0.01));
    },
  );

  testWidgets(
    'CourseDetailContent renders accent bar, kind badge, and copies title & location',
    (tester) async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      const examCourse = Course(
        name: '线性代数期末考试',
        location: '教学中心 204',
        dayOfWeek: 3,
        placement: CoursePlacement(
          startPeriod: 1,
          endPeriod: 2,
          gridStart: 0,
          gridEnd: 2,
          usesCustomTime: false,
          startTime: '08:15',
          endTime: '09:55',
          label: '08:15 – 09:55 (第1-2节)',
        ),
        color: CourseColor.error,
        teachers: '王老师',
        weeksText: '第 18 周',
        source: ExamCourseSource('exam-1'),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: CourseDetailContent(course: examCourse),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('course-detail.accent-bar')),
        findsOneWidget,
      );
      expect(find.text('考试'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('course-detail.title')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(copiedText, '线性代数期末考试');

      await tester.tap(find.byKey(const ValueKey('course-detail.location')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(copiedText, '教学中心 204');
    },
  );

  testWidgets(
    'HomePage opens PaymentCodePage when tapping Campus Card surface in both compact and Bento modes',
    (tester) async {
      final runtime = await buildDemoRuntime();
      await runtime.auth.signIn(const DemoAuthCredential());

      final store = InMemorySecureCredentialStore();
      await SecureSessionCredentialStore(store).stageOpenId('demo-openid-1234');
      final campusCard = CampusCardService.withStore(
        store,
        runtimeFactory: () => runtime,
      );
      addTearDown(campusCard.dispose);
      await campusCard.refreshAccount();
      expect(campusCard.configured, isTrue);

      Future<void> pumpAndVerifyPaymentCodeOpened(Finder tapTarget) async {
        await tester.tap(tapTarget);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
        expect(find.byKey(const Key('card-manage-page')), findsNothing);
        await tester.tap(find.byTooltip('返回'));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(find.byKey(const Key('payment-code-page')), findsNothing);
      }

      // 1. Compact mobile layout: tapping the thumbnail/title area opens payment code.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final compactHost = await _buildTestHost(
        signedIn: true,
        campusCardService: campusCard,
        child: const HomePage(),
      );
      await tester.pumpWidget(compactHost.widget);
      await tester.pumpAndSettle();

      await pumpAndVerifyPaymentCodeOpened(
        find.byKey(const ValueKey('home.campus-card-mini-thumb')),
      );

      // 2. Wide Bento layout: tapping the entity card header band opens payment code.
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();

      await pumpAndVerifyPaymentCodeOpened(
        find.byKey(const ValueKey('home.campus-card-header-band')),
      );
    },
  );

  testWidgets(
    'IosNativeNavigationBar preserves large title typography when title is interactive',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var tapped = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveNavigationScaffold(
            appBar: IosNativeNavigationBar(
              title: '第 2 周',
              subtitle: '2026-2027 秋季学期',
              largeTitleMode: true,
              onTitlePressed: () => tapped++,
            ),
            body: ListView.builder(
              primary: true,
              itemCount: 30,
              itemBuilder: (_, i) => ListTile(title: Text('Row $i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titleContexts = tester.elementList(find.text('第 2 周')).toList();
      expect(
        titleContexts.any((c) {
          final style = DefaultTextStyle.of(c).style;
          return (style.fontSize ?? 0) >= 30 && style.fontWeight == FontWeight.w700;
        }),
        isTrue,
      );
      await tester.tap(find.text('第 2 周').last);
      await tester.pump();
      expect(tapped, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'SchedulePage agenda coordinates with iOS large title and exposes refresh menu',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final monday = DateUtils.addDaysToDate(now, 1 - now.weekday);
      final termCalendar = TermCalendar(
        code: 200,
        schoolYearTerm: '2026-2027-1',
        termBegin: DateUtils.addDaysToDate(monday, -7),
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
        ],
        courses: [
          for (var w = 1; w <= 5; w++)
            EamsCourse(
              name: '第$w周课程',
              classroom: '教学中心 10$w',
              teachers: '王老师',
              weeks: List.generate(17, (i) => i == w ? '1' : '0').join(),
              times: {
                DateTime.monday: const [1],
                now.weekday: const [1],
              },
            ),
        ],
      );
      final host = await _buildTestHost(
        signedIn: true,
        prefsValues: {
          'schedule_view_mode': 'agenda',
          'schedule_selected_semester': 'term1',
          'schedule_term_begin_term1': jsonEncode(termCalendar.toJson()),
          'schedule_course_table_term1': jsonEncode(table.toJson()),
        },
        child: const SchedulePage(),
      );
      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      final bar = tester
          .widget<AdaptiveNavigationScaffold>(find.byType(AdaptiveNavigationScaffold))
          .appBar as IosNativeNavigationBar;
      expect(bar.trailingItems.last.menuItems.any((m) => m.value == 'refresh'), isTrue);

      final nested = tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
      final beforeOuter = nested.outerController.offset;
      await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(nested.outerController.offset, greaterThan(beforeOuter));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'SchedulePage week picker aligns return-to-week button in header row and sets initial Today arrow direction',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final monday = DateUtils.addDaysToDate(now, 1 - now.weekday);
      final termCalendar = TermCalendar(
        code: 200,
        schoolYearTerm: '2026-2027-1',
        termBegin: DateUtils.addDaysToDate(monday, -7),
        snapshotDate: null,
        snapshotWeekOfTerm: null,
        allTeachWeeks: 16,
        allTermWeeks: 18,
        amClasses: 4,
        pmClasses: 5,
        eveClasses: 4,
      );
      final table = CourseTable(
        periods: const [CoursePeriod(index: 1, timeRange: '08:15-09:00')],
        courses: [
          EamsCourse(
            name: '导论',
            classroom: '101',
            teachers: '张老师',
            weeks: '01111100000000000',
            times: {
              now.weekday: const [1],
            },
          ),
        ],
      );
      final host = await _buildTestHost(
        signedIn: true,
        prefsValues: {
          'schedule_selected_semester': 'term1',
          'schedule_term_begin_term1': jsonEncode(termCalendar.toJson()),
          'schedule_course_table_term1': jsonEncode(table.toJson()),
        },
        child: const SchedulePage(),
      );
      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      // Advance to Week 4 (after Week 2) in Week mode, then open Week Picker.
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('第 4 周')), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('第 4 周')));
      await tester.pumpAndSettle();
      final sheetTitleTop = tester.getTopLeft(find.text('选择周数')).dy;
      final backToWeekTop = tester.getTopLeft(find.text('回到本周')).dy;
      expect((sheetTitleTop - backToWeekTop).abs(), lessThan(20));

      // Dismiss bottom sheet, switch to Agenda mode on frame 1 -> arrow should point UP immediately.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日程'));
      await tester.pump();
      final fabIcon = tester.widget<Icon>(
        find.descendant(of: find.byType(FloatingActionButton), matching: find.byType(Icon)),
      );
      expect(fabIcon.icon, Icons.keyboard_arrow_up);

      // Mobile agenda overflow menu exposes '刷新'.
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('视图设置'));
      await tester.pumpAndSettle();
      expect(find.text('刷新'), findsOneWidget);
    },
  );
}
