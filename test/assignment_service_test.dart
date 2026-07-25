import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed platform fetch keeps that platform cache', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    final oldBlackboard = _assignmentJson(
      id: 'blackboard-old',
      platform: 'blackboard',
      due: DateTime.utc(2026, 1, 10),
    );
    final oldGradescope = _assignmentJson(
      id: 'gradescope-old',
      platform: 'gradescope',
      due: DateTime.utc(2026, 1, 20),
    );
    await storage.saveCachedAssignments([oldBlackboard, oldGradescope]);
    // Primary account is the SSO identity session — no CASTGC on it.
    await storage.saveSession(
      UserSession(
        userId: 'user',
        userName: 'User',
        schoolName: 'School',
        createdAt: DateTime.utc(2026),
      ),
    );
    // Blackboard/exam fetches are gated on the eGate binding, not on the
    // primary UserSession. Bind one with the tgc the test expects.
    await storage.saveThirdPartyAccount(
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
        account: 'student',
        sid: 'student',
        token: 'session',
        raw: const {
          'tgc': 'tgc',
          'cookies': '',
          'sessionToken': 'session',
          'userId': 'user',
          'tenantId': 'tenant',
        },
        boundAt: DateTime.utc(2026),
      ),
    );
    await storage.saveThirdPartyAccount(
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.gradescope,
        account: 'gradescope@example.com',
        token: 'gradescope-token',
        boundAt: DateTime.utc(2026),
      ),
    );

    final httpClient = _AssignmentHttpClient((url, _) {
      if (url.path.endsWith('/auth/third-party/elearning')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'token': 'session_id=elearning-mock'},
          }),
          200,
        );
      }
      if (url.path.endsWith('/deadlines/blackboard')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              _assignmentJson(
                id: 'blackboard-new',
                platform: 'blackboard',
                due: DateTime.utc(2026, 1, 5),
              ),
            ],
          }),
          200,
        );
      }
      if (url.path.endsWith('/deadlines/gradescope')) {
        return http.Response(
          jsonEncode({'success': false, 'error': 'upstream failed'}),
          502,
        );
      }
      return http.Response('not found', 404);
    });
    final auth = AuthService(storage, httpClient, UniAuthService());
    final tpAuth = ThirdPartyAuthService(storage, httpClient);
    final schedule = ScheduleService(storage, httpClient, auth, tpAuth);
    await auth.loadSession();
    await tpAuth.initialize();

    final service =
        AssignmentService(storage, httpClient, auth, tpAuth, schedule)
          ..loadCached();

    await service.fetchAssignments();

    expect(
      service.assignments.map((a) => a.id),
      containsAll(['blackboard-new', 'gradescope-old']),
    );
    expect(
      service.assignments.map((a) => a.id),
      isNot(contains('blackboard-old')),
    );
    expect(service.platformErrors['gradescope'], 'upstream failed');

    final cachedIds =
        storage.loadCachedAssignments().map((a) => a['id']).toList();
    expect(cachedIds, containsAll(['blackboard-new', 'gradescope-old']));
    expect(cachedIds, isNot(contains('blackboard-old')));
  });

  test('fetches exam table as exam deadlines', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.setSelectedSemester('263');
    await storage.saveSession(
      UserSession(
        userId: 'user',
        userName: 'User',
        schoolName: 'School',
        createdAt: DateTime.utc(2026),
      ),
    );
    // Exam fetch reads cookies from the eGate binding, not UserSession.
    await storage.saveThirdPartyAccount(
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
        account: 'student',
        sid: 'student',
        token: 'session',
        raw: const {
          'tgc': 'tgc',
          'cookies': 'SESSION=abc',
          'sessionToken': 'session',
          'userId': 'user',
          'tenantId': 'tenant',
        },
        boundAt: DateTime.utc(2026),
      ),
    );

    final seenBodies = <Map<String, dynamic>>[];
    final httpClient = _AssignmentHttpClient((url, body) {
      seenBodies.add(body);
      if (url.path.endsWith('/auth/third-party/elearning')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'token': 'session_id=elearning-mock'},
          }),
          200,
        );
      }
      if (url.path.endsWith('/auth/third-party/eams')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'token': 'JSESSIONID=eams-mock'},
          }),
          200,
        );
      }
      if (url.path.endsWith('/deadlines/blackboard')) {
        return http.Response(
          jsonEncode({'success': true, 'data': <Object?>[]}),
          200,
        );
      }
      if (url.path.endsWith('/schedule/exam_table')) {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'success': true,
              'data': {
                'examBatchId': '1222',
                'examBatchName': '2025-2026学年春季学期期中考试',
                'semesterId': '263',
                'studentId': '26192',
                'exams': [
                  {
                    'courseCode': 'CS130.01',
                    'courseName': '操作系统I',
                    'examType': '期中考试',
                    'examDate': '2026-04-23',
                    'examTimeRange': '15:00~16:40',
                    'examPlace': '教学中心204',
                    'examStatus': '正常',
                    'seatUrl': 'https://eams.example/seat',
                    'examRoomId': '7987',
                  },
                ],
              },
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('not found', 404);
    });
    final auth = AuthService(storage, httpClient, UniAuthService());
    final tpAuth = ThirdPartyAuthService(storage, httpClient);
    final schedule = ScheduleService(storage, httpClient, auth, tpAuth);
    await auth.loadSession();
    await tpAuth.initialize();
    await schedule.loadCachedData();

    final service =
        AssignmentService(storage, httpClient, auth, tpAuth, schedule);

    await service.fetchAssignments();

    expect(
      service.assignments,
      hasLength(1),
      reason: 'errors=${service.platformErrors}, bodies=$seenBodies',
    );
    final exam = service.assignments.single;
    expect(exam.platform, 'exam');
    expect(exam.kind, DeadlineKind.exam);
    expect(exam.title, '操作系统I 期中考试');
    expect(exam.course, contains('教学中心204'));
    expect(exam.due, DateTime(2026, 4, 23, 15));
    expect(exam.lateDue, DateTime(2026, 4, 23, 16, 40));
    expect(exam.status, '正常');
    expect(exam.url, 'https://eams.example/seat');
    expect(
      seenBodies,
      contains(
        predicate<Map<String, dynamic>>((body) {
          return body['semester_id'] == '263' &&
              body['cookies'] == 'JSESSIONID=eams-mock';
        }),
      ),
    );
    expect(storage.loadCachedAssignments().single['kind'], 'exam');
  });
}

Map<String, dynamic> _assignmentJson({
  required String id,
  required String platform,
  required DateTime due,
}) =>
    {
      'id': id,
      'platform': platform,
      'title': id,
      'course': 'Course',
      'due': due.millisecondsSinceEpoch ~/ 1000,
    };

class _AssignmentHttpClient extends LoggingHttpClient {
  _AssignmentHttpClient(this._handler) : super(DebugLogger());

  final http.Response Function(Uri url, Map<String, dynamic> body) _handler;

  @override
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    String? tag,
  }) async {
    final decodedBody = body is String
        ? jsonDecode(body) as Map<String, dynamic>
        : <String, dynamic>{};
    return _handler(url, decodedBody);
  }
}
