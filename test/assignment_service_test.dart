import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
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

  for (final singlePlatform in [false, true]) {
    for (final expired in [false, true]) {
      test(
          'failed ${expired ? 'scheduled' : '401'} renewal does not repeat ${singlePlatform ? 'platform' : 'all'} sync',
          () async {
        var renewCalls = 0;
        var deadlineCalls = 0;
        final unexpectedRenewal = Completer<http.Response>();
        final fixture = await _identityFixture(
          (url, body) {
            if (url.path.endsWith('/auth/third-party/gradescope')) {
              renewCalls++;
              // Bound a regression's retry loop so the test can report it.
              if (renewCalls > 2) return unexpectedRenewal.future;
              return http.Response(
                jsonEncode({'success': false, 'error': 'server unavailable'}),
                500,
              );
            }
            if (url.path.endsWith('/deadlines/gradescope')) {
              deadlineCalls++;
              return http.Response('{"success":false}', 401);
            }
            return http.Response('not found', 404);
          },
          account: _gradescopeAccount('old-account', 'old-token').copyWith(
            autoRenew: true,
            password: 'synthetic-password',
            expire: DateTime.now()
                    .add(
                      expired
                          ? const Duration(days: -1)
                          : const Duration(days: 30),
                    )
                    .millisecondsSinceEpoch ~/
                1000,
          ),
        );
        fixture.service.enableAutoRefetch();
        final fetch = singlePlatform
            ? () => fixture.service.fetchPlatform('gradescope')
            : fixture.service.fetchAssignments;

        await fetch();
        await Future<void>.delayed(Duration.zero);

        expect(renewCalls, 1);
        expect(deadlineCalls, expired ? 0 : 1);
        expect(fixture.service.loading, isFalse);
        expect(fixture.thirdParty.renewStatus('gradescope')?.success, isFalse);
        expect(
          fixture.service.assignments.map((a) => a.id),
          ['old-cache', 'unrelated'],
        );

        await fetch();
        await Future<void>.delayed(Duration.zero);

        expect(renewCalls, 2, reason: 'an explicit retry remains available');
        expect(deadlineCalls, expired ? 0 : 2);
        expect(fixture.service.loading, isFalse);
      });
    }
  }

  for (final singlePlatform in [false, true]) {
    test(
        'account replacement rejects old ${singlePlatform ? 'platform' : 'all'} fetch and refetches',
        () async {
      final oldResponse = Completer<http.Response>();
      final requested = Completer<void>();
      final refreshed = Completer<void>();
      final fixture = await _identityFixture((url, body) {
        if (url.path.endsWith('/deadlines/gradescope')) {
          if (body['token'] == 'old-token') {
            if (!requested.isCompleted) requested.complete();
            return oldResponse.future;
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                _assignmentJson(
                  id: 'new-account',
                  platform: 'gradescope',
                  due: DateTime.utc(2027),
                ),
              ],
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      fixture.service.enableAutoRefetch();
      fixture.service.addListener(() {
        if (!fixture.service.loading &&
            fixture.service.assignments.any((a) => a.id == 'new-account') &&
            !refreshed.isCompleted) {
          refreshed.complete();
        }
      });
      final fetch = singlePlatform
          ? fixture.service.fetchPlatform('gradescope')
          : fixture.service.fetchAssignments();
      await requested.future;
      await fixture.thirdParty
          .replaceAll([_gradescopeAccount('new-account', 'new-token')]);
      expect(fixture.service.identityEpoch, greaterThan(0));
      expect(fixture.service.assignments.map((a) => a.id), ['unrelated']);
      oldResponse.complete(
        http.Response(
          jsonEncode({
            'success': true,
            'data': [
              _assignmentJson(
                id: 'stale-response',
                platform: 'gradescope',
                due: DateTime.utc(2027),
              ),
            ],
          }),
          200,
        ),
      );
      await fetch;
      await refreshed.future.timeout(const Duration(seconds: 3));
      expect(
        fixture.service.assignments.map((a) => a.id),
        containsAll(['new-account', 'unrelated']),
      );
      expect(
        fixture.storage.loadCachedAssignments().map((a) => a['id']),
        isNot(contains('stale-response')),
      );
    });
  }

  test(
      'logout invalidates pending results and binding renewal cannot restore them',
      () async {
    final response = Completer<http.Response>();
    final requested = Completer<void>();
    final fixture = await _identityFixture((url, body) {
      requested.complete();
      return response.future;
    });
    fixture.service.enableAutoRefetch();
    final fetch = fixture.service.fetchAssignments();
    await requested.future;
    await fixture.auth.logout();
    await fixture.thirdParty
        .replaceAll([_gradescopeAccount('old-account', 'renewed-token')]);
    response.complete(
      http.Response(
        jsonEncode({
          'success': true,
          'data': [
            _assignmentJson(
              id: 'stale-response',
              platform: 'gradescope',
              due: DateTime.utc(2027),
            ),
          ],
        }),
        200,
      ),
    );
    await fetch;
    expect(fixture.service.assignments, isEmpty);
    expect(fixture.service.hasCachedData, isFalse);
    expect(fixture.storage.hasCachedAssignments, isFalse);
  });

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
    expect(exam, isA<ExamAssignment>());
    final examDetails = exam as ExamAssignment;
    expect(examDetails.semesterId, '263');
    expect(examDetails.location, '教学中心204');
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
    final cached = Assignment.fromJson(storage.loadCachedAssignments().single);
    expect(cached, isA<ExamAssignment>());
    expect((cached as ExamAssignment).semesterId, '263');
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

  final FutureOr<http.Response> Function(Uri url, Map<String, dynamic> body)
      _handler;

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

ThirdPartyAccount _gradescopeAccount(String account, String token) =>
    ThirdPartyAccount(
      platform: ThirdPartyPlatform.gradescope,
      account: account,
      token: token,
      boundAt: DateTime.utc(2026),
    );

Future<
    ({
      AssignmentService service,
      ThirdPartyAuthService thirdParty,
      AuthService auth,
      StorageService storage
    })> _identityFixture(
  FutureOr<http.Response> Function(Uri, Map<String, dynamic>) handler, {
  ThirdPartyAccount? account,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  await storage.saveSession(
    UserSession(
      userId: 'synthetic-user',
      userName: 'Synthetic',
      schoolName: 'School',
      createdAt: DateTime.utc(2026),
    ),
  );
  await storage.saveThirdPartyAccount(
    account ?? _gradescopeAccount('old-account', 'old-token'),
  );
  await storage.saveCachedAssignments([
    _assignmentJson(
      id: 'old-cache',
      platform: 'gradescope',
      due: DateTime.utc(2027),
    ),
    _assignmentJson(
      id: 'unrelated',
      platform: 'synthetic',
      due: DateTime.utc(2027),
    ),
  ]);
  final client = _AssignmentHttpClient(handler);
  final auth = AuthService(storage, client, UniAuthService());
  final thirdParty = ThirdPartyAuthService(storage, client);
  await auth.loadSession();
  await thirdParty.initialize();
  final schedule = ScheduleService(storage, client, auth, thirdParty);
  final service = AssignmentService(storage, client, auth, thirdParty, schedule)
    ..loadCached();
  addTearDown(() {
    service.dispose();
    schedule.dispose();
    thirdParty.dispose();
    auth.dispose();
    client.close();
  });
  return (
    service: service,
    thirdParty: thirdParty,
    auth: auth,
    storage: storage
  );
}
