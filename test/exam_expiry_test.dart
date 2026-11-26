import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course_table.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/assignments_page.dart';
import 'package:techpie/pages/home_page.dart';
import 'package:techpie/pages/schedule_page.dart';
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
import 'package:techpie/services/wear/techpie_wear_data_source.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';

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

Future<({Widget widget, AssignmentService assignments})> _buildTestHost({
  required Widget child,
  Map<String, Object> prefsValues = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'privacy_accepted_v1': true,
    ...prefsValues,
  });
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  addTearDown(http.close);
  final uniAuth = UniAuthService();
  final session = UserSession(
    userId: '20240001',
    userName: '测试同学',
    schoolName: '上海科技大学',
    createdAt: DateTime(2026, 1, 1),
  );
  final auth = _SignedInAuth(storage, http, uniAuth, session);
  final tpAuth = _BoundThirdParty(storage, http);
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
    campusCardService: CampusCardService(),
    ecardBindService: EcardBindService(),
    child: MaterialApp(
      theme: themeService.lightTheme,
      darkTheme: themeService.darkTheme,
      builder: (_, inner) => AdaptiveFeedbackHost(
        child: inner ?? const SizedBox.shrink(),
      ),
      home: child,
    ),
  );
  return (widget: widget, assignments: assignments);
}

ExamAssignment _exam({
  required String id,
  required String title,
  required DateTime due,
  DateTime? lateDue,
  String semesterId = 'term1',
  String location = '教学中心 201',
}) =>
    ExamAssignment(
      id: id,
      title: title,
      course: '$title · $location',
      due: due,
      lateDue: lateDue,
      semesterId: semesterId,
      location: location,
      batchName: '期末考试',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExamAssignment expiration semantics', () {
    test('exams never enter overdue and expire immediately at end time', () {
      final start = DateTime(2026, 6, 15, 14, 0);
      final end = DateTime(2026, 6, 15, 16, 0);
      final timedExam = _exam(id: 'e1', title: '高数期末考试', due: start, lateDue: end);
      final pointExam = _exam(id: 'e2', title: '线代测验', due: start);
      final homework = Assignment(
        id: 'hw1',
        platform: 'blackboard',
        title: 'Homework 1',
        course: 'CS100',
        due: start,
      );

      expect(homework.canBeOverdue, isTrue);
      expect(homework.isExpiredAt(end.add(const Duration(days: 5))), isFalse);

      expect(timedExam.canBeOverdue, isFalse);
      expect(timedExam.endTime, end);
      expect(timedExam.isExpiredAt(start.subtract(const Duration(minutes: 1))), isFalse);
      expect(timedExam.isInProgressAt(start), isTrue);
      expect(timedExam.isExpiredAt(start), isFalse);
      expect(timedExam.isInProgressAt(start.add(const Duration(minutes: 45))), isTrue);
      expect(timedExam.isInProgressAt(end), isFalse);
      expect(timedExam.isExpiredAt(end), isTrue);
      expect(timedExam.isExpiredAt(end.add(const Duration(minutes: 1))), isTrue);

      expect(pointExam.canBeOverdue, isFalse);
      expect(pointExam.endTime, start);
      expect(pointExam.isInProgressAt(start), isFalse);
      expect(pointExam.isExpiredAt(start), isTrue);
    });
  });

  group('Exam expiration in UI and Wear', () {
    testWidgets('AssignmentsPage hides ended exams, keeps in-progress exams, and leaves homework overdue', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final endedTimed = _exam(
        id: 'term1:ended-timed',
        title: '已结束物理考试',
        due: now.subtract(const Duration(hours: 4)),
        lateDue: now.subtract(const Duration(hours: 2)),
      );
      final endedPoint = _exam(
        id: 'term1:ended-point',
        title: '已结束口试',
        due: now.subtract(const Duration(hours: 1)),
      );
      final ongoingExam = _exam(
        id: 'term1:ongoing',
        title: '正在进行算法考试',
        due: now.subtract(const Duration(minutes: 30)),
        lateDue: now.add(const Duration(minutes: 60)),
      );
      final futureExam = _exam(
        id: 'term1:future',
        title: '未来高数考试',
        due: now.add(const Duration(days: 2)),
        lateDue: now.add(const Duration(days: 2, hours: 2)),
      );
      final overdueHw = Assignment(
        id: 'hw-overdue',
        platform: 'blackboard',
        title: '逾期作业',
        course: 'CS101',
        due: now.subtract(const Duration(hours: 5)),
      );

      final host = await _buildTestHost(
        prefsValues: {
          'cached_assignments': jsonEncode([
            endedTimed.toJson(),
            endedPoint.toJson(),
            ongoingExam.toJson(),
            futureExam.toJson(),
            overdueHw.toJson(),
          ]),
        },
        child: const AssignmentsPage(),
      );

      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      expect(find.text('已结束物理考试'), findsNothing);
      expect(find.text('已结束口试'), findsNothing);
      expect(find.text('正在进行算法考试'), findsOneWidget);
      expect(find.text('未来高数考试'), findsOneWidget);
      expect(find.text('考试中'), findsOneWidget);
      expect(find.text('已逾期 (1)'), findsOneWidget);
      await tester.tap(find.text('已逾期 (1)'));
      await tester.pumpAndSettle();
      expect(find.text('逾期作业'), findsOneWidget);
      expect(find.text('已结束物理考试'), findsNothing);
      expect(find.text('已结束口试'), findsNothing);
    });

    testWidgets('AssignmentsPage shows no overdue section when only ended exams exist in the past', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final endedExam = _exam(
        id: 'term1:ended-only',
        title: '早间微积分考试',
        due: now.subtract(const Duration(hours: 5)),
        lateDue: now.subtract(const Duration(hours: 3)),
      );
      final futureHw = Assignment(
        id: 'hw-future',
        platform: 'blackboard',
        title: '本周作业',
        course: 'CS100',
        due: now.add(const Duration(hours: 12)),
      );

      final host = await _buildTestHost(
        prefsValues: {
          'cached_assignments': jsonEncode([
            endedExam.toJson(),
            futureHw.toJson(),
          ]),
        },
        child: const AssignmentsPage(),
      );

      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      expect(find.text('早间微积分考试'), findsNothing);
      expect(find.textContaining('已逾期'), findsNothing);
      expect(find.text('本周作业'), findsOneWidget);
    });

    testWidgets('HomePage hides ended exams and highlights in-progress exams', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final endedExam = _exam(
        id: 'term1:home-ended',
        title: '昨日结束考试',
        due: now.subtract(const Duration(days: 1, hours: 2)),
        lateDue: now.subtract(const Duration(days: 1)),
      );
      final ongoingExam = _exam(
        id: 'term1:home-ongoing',
        title: '当前正在考试',
        due: now.subtract(const Duration(minutes: 20)),
        lateDue: now.add(const Duration(minutes: 40)),
      );

      final host = await _buildTestHost(
        prefsValues: {
          'cached_assignments': jsonEncode([
            endedExam.toJson(),
            ongoingExam.toJson(),
          ]),
        },
        child: const HomePage(),
      );

      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      expect(find.text('昨日结束考试'), findsNothing);
      expect(find.text('当前正在考试'), findsOneWidget);
      expect(find.text('考试中'), findsOneWidget);
    });

    testWidgets('SchedulePage agenda omits ended exams from earlier today and retains upcoming exams', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
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
      const table = CourseTable(
        periods: [
          CoursePeriod(index: 1, timeRange: '08:15-09:00'),
        ],
        courses: [],
      );
      final endedExam = _exam(
        id: 'term1:agenda-ended',
        title: '今日已结束考试',
        due: now.subtract(const Duration(minutes: 3)),
        lateDue: now.subtract(const Duration(minutes: 1)),
      );
      final ongoingExam = _exam(
        id: 'term1:agenda-ongoing',
        title: '今日进行中考试',
        due: now.subtract(const Duration(minutes: 20)),
        lateDue: now.add(const Duration(minutes: 40)),
      );

      final host = await _buildTestHost(
        prefsValues: {
          'schedule_selected_semester': 'term1',
          'schedule_term_begin_term1': jsonEncode(termCalendar.toJson()),
          'schedule_course_table_term1': jsonEncode(table.toJson()),
          'cached_assignments': jsonEncode([
            endedExam.toJson(),
            ongoingExam.toJson(),
          ]),
        },
        child: const SchedulePage(),
      );

      await tester.pumpWidget(host.widget);
      await tester.pumpAndSettle();

      await tester.tap(find.text('日程'));
      await tester.pumpAndSettle();

      final upcomingCard = find.byKey(const ValueKey('schedule.upcoming-exams'));
      expect(upcomingCard, findsOneWidget);
      expect(
        find.descendant(of: upcomingCard, matching: find.text('今日已结束考试')),
        findsNothing,
      );
      expect(
        find.descendant(of: upcomingCard, matching: find.text('今日进行中考试')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: upcomingCard, matching: find.text('1 场')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: upcomingCard, matching: find.text('考试中')),
        findsOneWidget,
      );
    });

    test('TechPieWearDataSource omits ended exams from deadlines()', () async {
      final now = DateTime(2026, 6, 15, 16, 5);
      final endedExam = _exam(
        id: 'term1:wear-ended',
        title: 'Ended Wear Exam',
        due: DateTime(2026, 6, 15, 14, 0),
        lateDue: DateTime(2026, 6, 15, 16, 0),
      );
      final futureHomework = Assignment(
        id: 'hw-wear',
        platform: 'blackboard',
        title: 'Wear Homework',
        course: 'CS100',
        due: DateTime(2026, 6, 16, 12, 0),
      );

      SharedPreferences.setMockInitialValues({
        'cached_assignments': jsonEncode([
          endedExam.toJson(),
          futureHomework.toJson(),
        ]),
      });
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final logger = DebugLogger();
      final http = LoggingHttpClient(logger);
      addTearDown(http.close);
      final uniAuth = UniAuthService();
      final auth = AuthService(storage, http, uniAuth);
      final tpAuth = ThirdPartyAuthService(storage, http);
      final schedule = ScheduleService(storage, http, auth, tpAuth);
      final assignments = AssignmentService(storage, http, auth, tpAuth, schedule)
        ..loadCached();

      final wear = TechPieWearDataSource(
        auth: auth,
        accounts: tpAuth,
        assignments: assignments,
        campusCard: CampusCardService(),
        timetable: schedule,
        now: () => now,
      );

      final items = await wear.deadlines();
      expect(items.map((item) => item.title), ['Wear Homework']);
    });
  });
}
