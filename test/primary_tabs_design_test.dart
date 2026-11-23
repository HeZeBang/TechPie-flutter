import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course_table.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/assignments_page.dart';
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
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';
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

Future<Widget> _buildTestHost({
  required Widget child,
  bool signedIn = false,
  Map<String, Object> prefsValues = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'privacy_accepted_v1': true,
    ...prefsValues,
  });
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
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

  return ServiceProvider(
    authService: auth,
    debugLogger: logger,
    storageService: storage,
    themeService: themeService,
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
    child: MaterialApp(
      theme: themeService.lightTheme(),
      darkTheme: themeService.darkTheme(),
      builder: (_, inner) => AdaptiveFeedbackHost(
        key: adaptiveFeedbackHostKey,
        child: inner!,
      ),
      home: child,
    ),
  );
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

      final table = CourseTable(
        periods: const [
          CoursePeriod(index: 1, timeRange: '08:15-09:00'),
          CoursePeriod(index: 2, timeRange: '09:10-09:55'),
        ],
        courses: const [
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

      await tester.pumpWidget(host);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('schedule.view-mode-switch')),
        findsOneWidget,
      );
      expect(find.text('周课表'), findsOneWidget);
      expect(find.text('日程'), findsOneWidget);

      await tester.tap(find.text('日程'));
      await tester.pumpAndSettle();

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
    'AssignmentsPage renders borderless TpCard items with TpProgressBar',
    (tester) async {
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
        },
        child: const AssignmentsPage(),
      );

      await tester.pumpWidget(host);
      await tester.pumpAndSettle();

      expect(find.text('Lab 3: Virtual Memory'), findsOneWidget);
      expect(find.byType(TpCard), findsOneWidget);
      expect(find.byType(TpProgressBar), findsOneWidget);
      expect(find.byType(TpBadge), findsWidgets);
    },
  );

  testWidgets(
    'SettingsPage renders Inset Grouped TpCard sections with online hero card',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final host = await _buildTestHost(
        signedIn: true,
        child: const SettingsPage(),
      );

      await tester.pumpWidget(host);
      await tester.pumpAndSettle();

      expect(find.text('我的'), findsOneWidget);
      expect(find.text('在线'), findsOneWidget);
      expect(find.text('第三方账号'), findsOneWidget);
      expect(find.text('云同步'), findsOneWidget);
      expect(find.text('外观与体验'), findsOneWidget);
      expect(find.text('网络与支持'), findsOneWidget);
      expect(find.byType(TpCard), findsWidgets);
      expect(find.byType(TpListRow), findsWidgets);
    },
  );
}
