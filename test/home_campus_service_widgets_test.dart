import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/academic_certificate.dart';
import 'package:techpie/models/course.dart';
import 'package:techpie/models/grade_record.dart';
import 'package:techpie/models/home_layout.dart';
import 'package:techpie/models/pnp_and_minor.dart';
import 'package:techpie/models/study_plan.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/academic_certificate_service.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus/campus_clients.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/course_catalog_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/grade_service.dart';
import 'package:techpie/services/holiday_travel_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/pnp_minor_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_allowance_service.dart';
import 'package:techpie/services/student_leave_service.dart';
import 'package:techpie/services/study_plan_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';
import 'package:techpie/widgets/home/home_campus_service_widgets.dart';

import 'support/fake_ids_client.dart';

const _campusServiceWidgetIds = [
  HomeWidgetId.campusGrades,
  HomeWidgetId.campusStudyPlan,
  HomeWidgetId.campusBlackboard,
  HomeWidgetId.campusElrcRecordings,
  HomeWidgetId.campusEcourse,
  HomeWidgetId.campusCourseCatalog,
  HomeWidgetId.campusCertificates,
  HomeWidgetId.campusOaGym,
  HomeWidgetId.campusStudentLeave,
  HomeWidgetId.campusHolidayTravel,
  HomeWidgetId.campusActivities,
  HomeWidgetId.campusJobs,
  HomeWidgetId.campusStudentAllowance,
  HomeWidgetId.campusPnpMinor,
];

Future<void> _pumpAllCampusWidgets(
  WidgetTester tester, {
  required bool authenticated,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;

  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  if (authenticated) {
    await storage.saveSession(
      UserSession(
        userId: 'user',
        userName: 'User',
        schoolName: 'ShanghaiTech',
        createdAt: DateTime(2026),
      ),
    );
    await storage.saveThirdPartyAccount(FakeIdsClient.account('bound'));
    final owner = jsonEncode(['user', 'bound']);
    final bbOwnerKey =
        sha256.convert(utf8.encode(jsonEncode(['user', 'bound']))).toString();

    await storage.saveGradeCache(
      owner,
      GradeScope.all.name,
      jsonEncode({
        'updated': '2026-11-27T09:00:00Z',
        'courses': [
          const CourseGrade(
            semester: '2025-2026 秋',
            courseCode: 'CS101',
            courseName: '计算机科学导论',
            courseType: '必修',
            credits: 4.0,
            scoreText: 'A',
            gradePoint: 4.0,
            passed: true,
            isRetake: false,
          ).toJson(),
          const CourseGrade(
            semester: '2025-2026 春',
            courseCode: 'EE102',
            courseName: '电路分析',
            courseType: '必修',
            credits: 3.0,
            scoreText: 'A-',
            gradePoint: 3.7,
            passed: true,
            isRetake: false,
          ).toJson(),
        ],
      }),
    );

    final planSnapshot = StudyPlanSnapshot(
      [
        PlanCategoryProgress(
          '通识核心课程',
          0,
          requiredCredits: 20,
          completed: 16,
          actual: 16,
          met: true,
          children: const <PlanCategoryProgress>[],
          courses: const <PlanCourseItem>[],
        ),
      ],
      140,
      98,
      DateTime(2026, 11, 27),
    );
    await storage.saveStudyPlanCache(false, {
      'owner': owner,
      'snapshot': planSnapshot.toJson(),
    });

    await storage.saveBlackboardIndex({
      'owner': bbOwnerKey,
      'courses': [
        {
          'id': 'c1',
          'courseId': 'CS101',
          'name': '数据结构与算法',
          'term': '2026-2027学年 第一学期',
        },
      ],
      'announcements': [
        {'title': '第一次编程作业发布', 'text': '请注意截止时间'},
      ],
    });

    await storage.saveCatalogHistory(owner, ['算法导论', '人工智能']);
    await storage.saveAcademicCertificateCache(
      owner,
      CertificateKind.transcript.name,
      jsonEncode([
        {'申请状态': '审核通过', '学年学期': '2025-2026'},
      ]),
    );
    await storage.savePnpMinorHistory(
      owner,
      jsonEncode({
        'P/NP 历史申请': [
          const AcademicApplicationRow('摄影艺术基础', {'审核结果': '通过'}).toJson(),
        ],
      }),
    );
    await storage.writeEmapCache(
      'student_leave',
      jsonEncode({
        'user': 'user',
        'ids': 'bound',
        'values': {
          'history': [
            {
              'SQBH': 'L1',
              'QJLX_DISPLAY': '事假',
              'SHZT_DISPLAY': '审批通过',
              'QJKSRQ': '2026-11-28',
              'QJJSRQ': '2026-11-29',
            },
          ],
        },
      }),
    );
    await storage.writeEmapCache(
      'holiday_travel',
      jsonEncode({
        'user': 'user',
        'ids': 'bound',
        'values': {
          'history': [
            {
              'WID': 'H1',
              'JJRDM_DISPLAY': '国庆节',
              'QRZT_DISPLAY': '已登记',
              'QXSF_DISPLAY': '上海市',
              'QXCS_DISPLAY': '浦东新区',
              'DJRQ': '2026-09-29',
            },
          ],
        },
      }),
    );
  }

  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  final uniAuth = UniAuthService();
  final auth = AuthService(storage, http, uniAuth);
  await auth.loadSession();
  final tpAuth = ThirdPartyAuthService(storage, http, idsClient: FakeIdsClient());
  await tpAuth.initialize();
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
  final clients = CampusClients(auth, tpAuth, storage: storage);
  final grades = GradeService(clients.eams, storage, auth, tpAuth);
  final studyPlan = StudyPlanService(
    clients.eams,
    storage,
    () => (user: auth.session?.userId, ids: tpAuth.idsAccount?.account),
    Listenable.merge([auth, tpAuth]),
  );
  final catalog = CourseCatalogService(clients.eams, storage, auth, tpAuth);
  final certs = AcademicCertificateService(clients.eams, storage, auth, tpAuth);
  final pnp = PnpMinorService(clients.eams, storage, auth, tpAuth);
  final oaGym = OaGymService(auth, storage, tpAuth);
  final egate = EgateAppService(auth, storage, tpAuth);
  final allowance = StudentAllowanceService(auth, tpAuth);
  final leave = StudentLeaveService(
    clients.emap,
    storage,
    Listenable.merge([auth, tpAuth]),
  );
  final travel = HolidayTravelService(
    clients.emap,
    storage,
    Listenable.merge([auth, tpAuth]),
  );
  final card = CampusCardService(storage: storage);
  final sync = SyncService(auth, tpAuth, storage, ecard: card);
  final theme = ThemeService(storage);
  final bind = EcardBindService();
  final update = UpdateService();

  const todayCourse = Course(
    name: '计算机图形学',
    teachers: '张老师',
    location: '信息学院 1A',
    dayOfWeek: 1,
    placement: CoursePlacement(
      startPeriod: 3,
      endPeriod: 4,
      gridStart: 2.0,
      gridEnd: 4.0,
      usesCustomTime: false,
      startTime: '10:00',
      endTime: '11:40',
      label: '10:00 – 11:40  (第3-4节)',
    ),
    weeksText: '1-16周',
  );

  try {
    await tester.pumpWidget(
      ServiceProvider(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: theme,
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: oaGym,
        egateAppService: egate,
        campusClients: clients,
        gradeService: grades,
        studyPlanService: studyPlan,
        courseCatalog: catalog,
        certificates: certs,
        pnpMinor: pnp,
        studentLeaveService: leave,
        holidayTravelService: travel,
        studentAllowanceService: allowance,
        uniAuthService: uniAuth,
        syncService: sync,
        updateService: update,
        campusCardService: card,
        ecardBindService: bind,
        child: MaterialApp(
          theme: theme.lightTheme,
          darkTheme: theme.darkTheme,
          themeMode:
              brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final id in _campusServiceWidgetIds)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Builder(
                        builder: (context) => buildCampusServiceHomeWidget(
                          context,
                          id,
                          todayCourses: [todayCourse],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final id in _campusServiceWidgetIds) {
      expect(find.byKey(ValueKey('home.widget-${id.key}')), findsOneWidget);
    }

    if (authenticated) {
      expect(find.text('GPA 3.87'), findsOneWidget);
      expect(find.text('计算机科学导论'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('通识核心课程'), findsOneWidget);
      expect(find.text('数据结构与算法'), findsOneWidget);
      expect(find.text('最新公告：第一次编程作业发布'), findsOneWidget);
      expect(find.text('计算机图形学'), findsOneWidget);
      expect(find.text('算法导论'), findsOneWidget);
      expect(find.text('PDF'), findsNothing);
      expect(find.text('事假'), findsOneWidget);
      expect(find.text('国庆节'), findsOneWidget);
      expect(find.text('摄影艺术基础'), findsOneWidget);
    } else {
      expect(find.textContaining('登录'), findsWidgets);
    }
  } finally {
    await tester.pumpWidget(const SizedBox());
    clients.dispose();
    grades.dispose();
    studyPlan.dispose();
    catalog.dispose();
    certs.dispose();
    pnp.dispose();
    schedule.dispose();
    assignments.dispose();
    egate.dispose();
    oaGym.dispose();
    leave.dispose();
    travel.dispose();
    card.dispose();
    allowance.dispose();
    http.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  testWidgets(
      'all 14 campus service Home widgets render cached data cleanly in light and dark modes',
      (tester) async {
    await _pumpAllCampusWidgets(
      tester,
      authenticated: true,
      brightness: Brightness.light,
    );
    await _pumpAllCampusWidgets(
      tester,
      authenticated: false,
      brightness: Brightness.dark,
    );
  });

  testWidgets(
      'HomePage widget gallery filters by keyword, adds campus service widgets, and persists on Mobile and Desktop Bento',
      (tester) async {
    const feedbackChannel = MethodChannel('techpie/feedback');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(feedbackChannel, (_) async => null);

    Future<void> runFlow(Size size, TargetPlatform platform, bool isBento) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      debugDefaultTargetPlatformOverride = platform;

      SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
      final storage = StorageService(await SharedPreferences.getInstance());
      final logger = DebugLogger();
      final http = LoggingHttpClient(logger);
      try {
        final uniAuth = UniAuthService();
        final auth = AuthService(storage, http, uniAuth);
        final tpAuth = ThirdPartyAuthService(storage, http);
        final schedule = ScheduleService(storage, http, auth, tpAuth);
        final assignments =
            AssignmentService(storage, http, auth, tpAuth, schedule);
        await tester.pumpWidget(
          TechPieApp(
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
            campusCardService: CampusCardService(),
            ecardBindService: EcardBindService(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('home.edit-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('home.open-gallery')));
        await tester.pumpAndSettle();

        expect(find.text('已添加 4/${HomeWidgetId.values.length}'), findsOneWidget);
        expect(find.text('核心主页'), findsOneWidget);
        expect(find.text('学业与课程'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('home.gallery-search')),
          'GPA',
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('home.gallery-add-campus_grades')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('home.gallery-add-campus_egate_xshd')),
          findsNothing,
        );

        await tester
            .tap(find.byKey(const ValueKey('home.gallery-add-campus_grades')));
        await tester.pumpAndSettle();
        expect(find.text('已添加 5/${HomeWidgetId.values.length}'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('home.gallery-close')));
        await tester.pumpAndSettle();
        adaptiveFeedbackHostKey.currentState?.dismiss();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('home.widget-campus_grades')),
          findsOneWidget,
        );
        if (isBento) {
          expect(
            storage.homeDesktopLayout.contains(HomeWidgetId.campusGrades),
            isTrue,
          );
        } else {
          expect(
            storage.homeMobileLayout.contains(HomeWidgetId.campusGrades),
            isTrue,
          );
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        http.close();
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    }

    try {
      await runFlow(const Size(390, 844), TargetPlatform.iOS, false);
      await runFlow(const Size(1280, 840), TargetPlatform.macOS, true);
    } finally {
      messenger.setMockMethodCallHandler(feedbackChannel, null);
    }
  });
}
