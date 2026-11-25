import 'dart:convert';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:techpie/widgets/adaptive_feedback.dart';
import 'package:techpie/widgets/course_detail_panel.dart';
import 'package:techpie/widgets/design_system/design_system.dart';

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
  final tpAuth = signedIn
      ? _BoundThirdParty(storage, http)
      : ThirdPartyAuthService(storage, http);
  final themeService = ThemeService(storage);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  await schedule.loadCachedData();
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule)
    ..loadCached();

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
    updateService: UpdateService(),
    campusCardService: campusCardService ?? CampusCardService(),
    ecardBindService: EcardBindService(),
    child: MaterialApp(
      theme: themeService.lightTheme,
      darkTheme: themeService.darkTheme,
      builder: (_, inner) => AdaptiveFeedbackHost(
        key: adaptiveFeedbackHostKey,
        child: inner!,
      ),
      home: child,
    ),
  );
  return (widget: widget, storage: storage);
}

void main() {
  testWidgets(
    'SchedulePage supports switching between 周课表 and 日程 agenda with upcoming exams',
    (tester) async {
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final examDue = now.add(const Duration(days: 20));

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
            name: '计算机系统导论',
            classroom: '信息学院 1B-201',
            teachers: '王老师',
            weeks: '01111111111111111',
            times: {
              1: [1, 2],
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
      expect(find.text('六'), findsNothing);
      expect(find.text('日'), findsNothing);

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
            times: {6: [1, 2]},
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

  testWidgets(
    'SettingsPage renders Inset Grouped TpCard sections with plain account header and platform-gated watch entry',
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
      expect(find.text('在线'), findsOneWidget);
      expect(find.text('第三方账号'), findsOneWidget);
      expect(find.text('云同步'), findsOneWidget);
      expect(find.text('外观与体验'), findsOneWidget);
      expect(find.text('网络与支持'), findsOneWidget);
      expect(find.byType(TpCard), findsWidgets);
      expect(find.byType(TpListRow), findsWidgets);
    },
  );

  testWidgets(
    'iOS settings use inline theme menus and persist the system color',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      final host = await _buildTestHost(child: const SettingsPage());
      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      CNPopupMenuButton menuFor(String label) => tester.widget<CNPopupMenuButton>(
            find.byWidgetPredicate(
              (widget) => widget is CNPopupMenuButton && widget.semanticLabel == label,
            ),
          );

      final modeMenu = menuFor('主题模式');
      final colorMenu = menuFor('主题色');
      expect(modeMenu.buttonLabel, 'System');
      expect(colorMenu.buttonLabel, 'TechRed');
      expect(modeMenu.buttonStyle, CNButtonStyle.glass);
      expect(colorMenu.buttonStyle, CNButtonStyle.glass);
      final systemIndex = colorMenu.items.indexWhere(
        (item) => item is CNPopupMenuItem && item.label == 'system',
      );
      expect(systemIndex, isNonNegative);

      colorMenu.onSelected(systemIndex);
      await tester.pumpAndSettle();

      final updatedColorMenu = menuFor('主题色');
      expect(updatedColorMenu.buttonLabel, 'system');
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
}
