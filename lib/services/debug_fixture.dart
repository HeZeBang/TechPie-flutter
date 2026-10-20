import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../models/course_table.dart';
import '../models/custom_course.dart';
import '../models/third_party_account.dart';
import '../models/user_session.dart';
import 'debug_preview_http_client.dart';
import 'storage_service.dart';

/// Enables the local UI fixture with:
/// `flutter run --dart-define=TECHPI_DEBUG_FIXTURE=true`.
const debugFixtureEnabled = bool.fromEnvironment('TECHPI_DEBUG_FIXTURE');

const debugFixtureUserId = 'debug-fixture-user';

UserSession debugFixtureSession() => UserSession(
      userId: debugFixtureUserId,
      userName: 'UI Preview Student',
      schoolName: '上海科技大学（本地预览）',
      studentId: '20240001',
      createdAt: DateTime(2026, 10, 12),
      geekpieToken: 'debug-fixture-token',
    );

/// Installs process-local stores before any app service is constructed.
/// Existing preferences and secure credentials are neither read nor changed.
Future<void> initializeDebugFixture() async {
  if (!kDebugMode) throw UnsupportedError('Preview is debug-only');
  // The debug fixture intentionally uses process-local preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  // The plugin's memory implementation also works in a debug app. Deliberately
  // replace its platform store so all secure-storage consumers stay local.
  // ignore: invalid_use_of_visible_for_testing_member
  FlutterSecureStorage.setMockInitialValues({
    'user_session': jsonEncode(debugFixtureSession().toJson()),
    'third_party_cpdaily': jsonEncode(
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
        account: '20240001',
        name: '本地预览学生',
        token: 'synthetic-campus-token',
        boundAt: DateTime(2026, 10, 19),
      ).toJson(),
    ),
  });
  await seedDebugFixture(StorageService(await SharedPreferences.getInstance()));
}

/// Shared TechPie API requests stay local even when pulling to refresh.
http.Client debugFixtureHttpClient() {
  const origin = String.fromEnvironment('TECHPI_GENAI_PROXY_ORIGIN');
  if (origin.isNotEmpty) return DebugPreviewHttpClient(proxyOrigin: origin);
  return MockClient(
    (_) async => http.Response(
      '{"message":"Local preview: campus services are unavailable"}',
      503,
      headers: {'content-type': 'application/json'},
    ),
  );
}

/// Seeds only the process-local preview caches.
Future<void> seedDebugFixture(StorageService storage) async {
  final today = DateTime.now();
  final monday = DateTime(today.year, today.month, today.day)
      .subtract(Duration(days: today.weekday - 1));
  final termBegin = monday.subtract(const Duration(days: 7));
  const semesterId = 'debug-2026-spring';
  final periods = [
    for (final period in defaultPeriods.take(8))
      CoursePeriod(
        index: period.number,
        timeRange: '${period.startTime}-${period.endTime}',
      ),
  ];
  final allWeeks = List.filled(27, '1').join();

  await storage.saveSemesters(
    const SemesterInfo(
      semesters: {
        '2026': {'春': semesterId},
      },
      defaultSemester: semesterId,
      tableId: 'debug-table',
    ),
  );
  await storage.setSelectedSemester(semesterId);
  await storage.saveCourseTable(
    semesterId,
    CourseTable(
      periods: periods,
      courses: [
        EamsCourse(
          name: 'UI 预览：软件工程',
          classroom: '教学楼 A101',
          teachers: 'Demo Teacher',
          weeks: allWeeks,
          times: const {
            1: [1, 2],
          },
        ),
        EamsCourse(
          name: 'UI 预览：数据结构',
          classroom: '教学楼 B203',
          teachers: 'Demo Teacher',
          weeks: allWeeks,
          times: const {
            3: [3, 4],
          },
        ),
      ],
    ),
  );
  await storage.saveTermCalendar(
    semesterId,
    TermCalendar(
      code: 200,
      schoolYearTerm: semesterId,
      termBegin: termBegin,
      snapshotDate: today,
      snapshotWeekOfTerm: 2,
      allTeachWeeks: 16,
      allTermWeeks: 18,
      amClasses: 4,
      pmClasses: 4,
      eveClasses: 2,
    ),
  );
  await storage.saveCustomCourses(
    semesterId,
    [
      const CustomCourse(
        id: 'debug-custom-course',
        semesterId: 'debug-2026-spring',
        name: 'UI 预览：自定义课程',
        location: '线上',
        teachers: 'Preview',
        weekdays: [5],
        weeks: [2, 3, 4, 5, 6],
        time: ClockCourseTime(startTime: '19:00', endTime: '20:30'),
      ),
    ],
  );
  await storage.saveCachedAssignments([
    Assignment(
      id: 'debug-assignment',
      platform: 'debug',
      title: 'UI 预览：提交实验报告',
      course: '软件工程',
      due: today.add(const Duration(days: 2)),
      status: 'Pending',
    ).toJson(),
    ExamAssignment(
      id: '$semesterId:debug-exam',
      title: 'UI 预览：期中考试',
      course: '数据结构',
      due: today.add(const Duration(days: 4, hours: 9)),
      lateDue: today.add(const Duration(days: 4, hours: 11)),
      semesterId: semesterId,
      location: '教学楼 C301',
      batchName: '本地预览场次',
    ).toJson(),
  ]);
}
