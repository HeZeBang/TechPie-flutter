import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/campus_identity.dart';
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

import 'support/eams_transport.dart';
import 'support/fake_ids_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('custom changes persist independently of an in-flight refresh', () async {
    final response = Completer<http.Response>();
    final requested = Completer<void>();
    final fixture = await _identityFixture((_, __) {
      requested.complete();
      return response.future;
    });
    final service = fixture.service;
    final owner = service.customDeadlineOwner;
    final due = DateTime(2027, 3, 1, 23, 59);
    final refresh = service.fetchAssignments();
    await requested.future;

    await Future.wait([
      service.saveCustomDeadline(owner: owner, title: 'First', due: due),
      service.saveCustomDeadline(owner: owner, title: 'Second', due: due),
    ]);
    final first = service.assignments.whereType<CustomDeadline>()
        .singleWhere((a) => a.title == 'First');
    await Future.wait([
      service.setCompleted(first, true),
      service.saveCustomDeadline(
        owner: owner,
        id: first.id,
        title: 'Edited',
        course: 'Course',
        notes: 'Bring printed copy',
        due: due.add(const Duration(hours: 1)),
      ),
    ]);

    response.complete(http.Response('{"success":true,"data":[]}', 200));
    await refresh;
    expect(fixture.storage.loadCachedAssignments().map((a) => a['id']), ['unrelated']);
    service.loadCached();
    expect(service.assignments.whereType<CustomDeadline>().map((a) => a.title), ['Second', 'Edited']);
    final edited = service.findCustomDeadline(first.id)!;
    expect(edited, isA<CustomDeadline>());
    expect(edited.course, 'Course');
    expect(edited.notes, 'Bring printed copy');
    expect(edited.due, due.add(const Duration(hours: 1)));
    expect(service.isCompleted(edited), isTrue);
    await service.toggleCompleted(edited);
    expect(service.findCustomDeadline(first.id)?.completed, isFalse);
    await service.deleteCustomDeadline(first.id, owner: owner);
    service.loadCached();
    expect(service.findCustomDeadline(first.id), isNull);
  });

  test('guest and account workspaces restore their own deadlines', () async {
    final fixture = await _identityFixture((_, __) => http.Response('', 503));
    final service = fixture.service;
    final session = fixture.auth.session!;
    final due = DateTime(2027, 3, 1, 23, 59);
    fixture.auth.onLogout = () async {
      await service.clearCache();
      await service.clearAllOverrides();
    };
    await service.saveCustomDeadline(owner: session.userId, title: 'Account', due: due);
    final accountDeadline = service.assignments.whereType<CustomDeadline>().single;
    await service.setCompleted(accountDeadline, true);
    await fixture.auth.logout();
    expect(service.assignments, isEmpty);
    expect(service.hasCachedData, isFalse);
    await expectLater(
      service.saveCustomDeadline(owner: session.userId, title: 'Stale draft', due: due),
      throwsStateError,
    );

    await service.saveCustomDeadline(owner: null, title: 'Guest', due: due);
    expect(service.hasCachedData, isTrue);
    expect(service.visibleAssignments.single.title, 'Guest');
    await fixture.storage.saveSession(session);
    await fixture.auth.loadSession();
    expect(service.visibleAssignments.single.title, 'Account');
    expect(service.isCompleted(service.visibleAssignments.single), isTrue);
    await fixture.auth.logout();
    expect(service.visibleAssignments.single.title, 'Guest');
  });

  test('IDS unbind clears campus deadlines and retains other cached sources', () async {
    final fixture = await _identityFixture(
      (_, __) => http.Response('unavailable', 503),
      account: FakeIdsClient.account('20240001'),
      cached: [
        for (final source in ['blackboard', 'exam', 'gradescope'])
          _assignmentJson(id: source, platform: source, due: DateTime.utc(2027)),
      ],
    );

    await fixture.thirdParty.unbind(ThirdPartyPlatform.ids);
    await Future<void>.delayed(Duration.zero);

    expect(fixture.service.assignments.map((a) => a.platform), ['gradescope']);
    expect(
      fixture.storage.loadCachedAssignments().map((a) => a['platform']),
      ['gradescope'],
    );
  });

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

  test('reminder completion overrides follow the third-party binding', () async {
    final shared = _assignmentJson(
      id: 'shared-assignment',
      platform: 'gradescope',
      due: DateTime.utc(2027),
    );
    final fixture = await _identityFixture(
      (_, __) => http.Response(
        jsonEncode({'success': true, 'data': [shared]}),
        200,
      ),
      cached: [shared],
    );
    final service = fixture.service;
    final oldAssignment = service.assignments.single;
    final oldKey = service.reminderKeyFor(oldAssignment);
    await service.applyReminderCompletions(
      {oldKey: (assignment: oldAssignment, completedAt: 100)},
      epoch: service.identityEpoch,
    );
    service.loadCached();
    expect(service.isCompleted(service.assignments.single), isTrue);

    await fixture.thirdParty.replaceAll([
      _gradescopeAccount('new-account', 'new-token'),
    ]);
    await service.fetchPlatform('gradescope');
    final newAssignment = service.assignments.single;
    expect(service.reminderKeyFor(newAssignment), isNot(oldKey));
    expect(service.isCompleted(newAssignment), isFalse);
    expect(service.hasCompletionOverride(newAssignment), isFalse);
    await service.setCompleted(newAssignment, true);
    await service.clearCompletionOverride(newAssignment);
    expect(service.isCompleted(newAssignment), isFalse);

    await fixture.thirdParty.replaceAll([
      _gradescopeAccount('old-account', 'old-token'),
    ]);
    await service.fetchPlatform('gradescope');
    expect(service.isCompleted(service.assignments.single), isTrue);
  });

  test('imported edits survive refresh and reload within their source binding', () async {
    final originalDue = DateTime.utc(2027, 1, 4, 12, 30, 45);
    final originalLateDue = originalDue.add(const Duration(days: 1));
    final editedDue = originalDue.add(const Duration(hours: 2));
    final initial = {
      ..._assignmentJson(id: 'same-id', platform: 'gradescope', due: originalDue),
      'lateDue': originalLateDue.millisecondsSinceEpoch ~/ 1000,
      'url': 'https://example.test/assignment/same-id',
    };
    final latest = {
      ...initial,
      'title': 'Updated by source',
      'due': originalDue.subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
      'status': 'Submitted',
    };
    final fixture = await _identityFixture(
      (_, __) => http.Response(
        jsonEncode({'success': true, 'data': [latest]}),
        200,
      ),
      cached: [initial],
    );
    final service = fixture.service;
    final original = service.assignments.single;
    final oldEpoch = service.identityEpoch;
    await expectLater(
      service.saveImportedDeadlineEdit(
        original,
        epoch: oldEpoch,
        lateDue: originalDue.subtract(const Duration(minutes: 1)),
      ),
      throwsArgumentError,
    );
    await service.saveImportedDeadlineEdit(original, epoch: oldEpoch, notes: 'Bring notes');
    expect(service.assignments.single.due.toUtc(), originalDue);
    expect(service.hasImportedDeadlineSourceEdit(original), isFalse);
    await service.saveImportedDeadlineEdit(original, epoch: oldEpoch, due: editedDue);
    expect(service.hasImportedDeadlineSourceEdit(original), isTrue);

    await service.fetchPlatform('gradescope');
    service.loadCached();
    final edited = service.assignments.single;
    expect(edited.due.toUtc(), editedDue);
    expect(edited.title, 'Updated by source');
    expect(edited.notes, 'Bring notes');
    expect(edited.url, original.url);
    expect(edited.effectiveLateDue?.toUtc(), originalLateDue);
    expect(service.isCompleted(edited), isTrue);
    expect(fixture.storage.loadCachedAssignments().single, isNot(contains('notes')));

    await fixture.thirdParty.replaceAll([_gradescopeAccount('new-account', 'new-token')]);
    await service.fetchPlatform('gradescope');
    expect(service.hasImportedDeadlineSourceEdit(service.assignments.single), isFalse);
    await expectLater(
      service.saveImportedDeadlineEdit(original, epoch: oldEpoch, title: 'Stale draft'),
      throwsStateError,
    );

    await fixture.thirdParty.replaceAll([_gradescopeAccount('old-account', 'old-token')]);
    await service.fetchPlatform('gradescope');
    expect(service.assignments.single.due.toUtc(), editedDue);
    await service.restoreImportedDeadline(edited, epoch: service.identityEpoch);
    service.loadCached();
    expect(service.assignments.single.due.millisecondsSinceEpoch ~/ 1000, latest['due']);
    expect(service.assignments.single.notes, 'Bring notes');
    expect(service.hasImportedDeadlineSourceEdit(service.assignments.single), isFalse);
  });

  test('scopes matching legacy reminder completions and keeps manual overrides', () async {
    final fixture = await _identityFixture(
      (_, __) => http.Response(
        jsonEncode({
          'success': true,
          'data': [
            _assignmentJson(id: 'old-cache', platform: 'gradescope', due: DateTime.utc(2027)),
          ],
        }),
        200,
      ),
    );
    final service = fixture.service;
    Assignment gradescopeAssignment() =>
        service.assignments.singleWhere((a) => a.platform == 'gradescope');
    final key = service.reminderKeyFor(gradescopeAssignment());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'assignment_overrides',
      jsonEncode({
        'completed': {
          'gradescope:old-cache': true,
          'synthetic:unrelated': true,
          'synthetic:manual-open': false,
        },
        'reminderCompletions': {key: 100},
      }),
    );
    service.loadCached();
    await service.readReminderSyncWork();
    expect(service.isCompleted(gradescopeAssignment()), isTrue);
    final unrelated =
        service.assignments.singleWhere((a) => a.platform == 'synthetic');
    expect(service.isCompleted(unrelated), isTrue);
    final saved = fixture.storage.loadAssignmentOverrides();
    expect(saved.completed, {
      'synthetic:unrelated': true,
      'synthetic:manual-open': false,
    });
    expect(saved.scopedCompleted, {key: true});
    expect(saved.reminderCompletions, {key: 100});

    await fixture.thirdParty.replaceAll([
      _gradescopeAccount('new-account', 'new-token'),
    ]);
    await service.fetchPlatform('gradescope');
    service.loadCached();
    expect(service.isCompleted(gradescopeAssignment()), isFalse);
    expect(service.isCompleted(unrelated), isTrue);
  });

  test('a renewal that rotates sid is not an account change', () async {
    var deadlineCalls = 0;
    final fixture = await _identityFixture(
      (url, body) {
        if (url.path.endsWith('/deadlines/gradescope')) deadlineCalls++;
        return http.Response('not found', 404);
      },
      account: _gradescopeAccount('old-account', 'old-token')
          .copyWith(sid: 'session-1'),
    );
    fixture.service.enableAutoRefetch();
    await fixture.thirdParty.replaceAll([
      _gradescopeAccount('old-account', 'renewed-token')
          .copyWith(sid: 'session-2'),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(fixture.service.identityEpoch, 0);
    expect(
      fixture.service.assignments.map((a) => a.id),
      ['old-cache', 'unrelated'],
    );
    // The new token is still worth a refetch.
    expect(deadlineCalls, 1);
  });

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
    await storage.setScheduleSource('20240001|20240001', CampusScheduleSource.undergraduate);

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
    await storage.saveCachedAssignments([
      oldBlackboard,
      oldGradescope,
      _assignmentJson(id: 'stable-legacy', platform: 'Blackboard', due: DateTime.utc(2026, 1, 6)),
    ]);
    // Primary account is the SSO identity session — no CASTGC on it.
    await storage.saveSession(
      UserSession(
        userId: 'user',
        userName: 'User',
        schoolName: 'School',
        createdAt: DateTime.utc(2026),
      ),
    );
    // Blackboard/exam fetches are gated on the IDS binding, not on the
    // primary UserSession. Bind one with the tgc the test expects.
    await storage.saveThirdPartyAccount(
      FakeIdsClient.account('20240001'),
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
      if (url.path.endsWith('/deadlines/gradescope')) {
        return http.Response(
          jsonEncode({'success': false, 'error': 'upstream failed'}),
          502,
        );
      }
      return http.Response('not found', 404);
    });
    final auth = AuthService(storage, httpClient, UniAuthService());
    final tpAuth = ThirdPartyAuthService(storage, httpClient, idsClient: FakeIdsClient());
    final schedule = ScheduleService(storage, httpClient, auth, tpAuth);
    await auth.loadSession();
    await tpAuth.initialize();

    final service = AssignmentService(
      storage,
      httpClient,
      auth,
      tpAuth,
      schedule,
      blackboardDeadlines: () async => [
        for (final id in ['blackboard-new', 'stable-legacy'])
          Assignment.fromJson(
            _assignmentJson(id: id, platform: 'blackboard', due: DateTime.utc(2026, 1, 5)),
          ),
      ],
    )..loadCached();
    final previous = service.assignments.singleWhere((a) => a.id == 'stable-legacy');
    final reminderKey = service.reminderKeyFor(previous);
    await service.setCompleted(previous, true);
    await service.hide(previous);

    await service.fetchAssignments();

    final refreshed = service.assignments.singleWhere((a) => a.id == previous.id);
    expect(service.reminderKeyFor(refreshed), reminderKey);
    expect(service.isCompleted(refreshed), isTrue);
    expect(service.isHidden(refreshed), isTrue);
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
    await storage.setScheduleSource('20240001|20240001', CampusScheduleSource.undergraduate);
    await storage.setSelectedSemester('263');
    await storage.saveSession(
      UserSession(
        userId: 'user',
        userName: 'User',
        schoolName: 'School',
        createdAt: DateTime.utc(2026),
      ),
    );
    // Exam fetch reads cookies from the IDS binding, not UserSession.
    await storage.saveThirdPartyAccount(
      FakeIdsClient.account('20240001'),
    );

    final seenBodies = <Map<String, dynamic>>[];
    final httpClient = _AssignmentHttpClient((url, body) {
      seenBodies.add(body);
      if (url.path.endsWith('/deadlines/blackboard')) {
        return http.Response(
          jsonEncode({'success': true, 'data': <Object?>[]}),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final auth = AuthService(storage, httpClient, UniAuthService());
    final tpAuth = ThirdPartyAuthService(storage, httpClient, idsClient: FakeIdsClient());
    final eamsRequests = <http.Request>[];
    final server = MockClient((r) async {
      eamsRequests.add(r);
      return http.Response.bytes(
        utf8.encode(r.url.path.endsWith('/stdExamTable.action') ? examBatches : examTable),
        200,
      );
    });
    final schedule = ScheduleService(
      storage,
      httpClient,
      auth,
      tpAuth,
      eamsTransport: eamsTransport(server),
      eamsInterval: Duration.zero,
    );
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
    expect(exam.url, 'https://eams.shanghaitech.edu.cn/eams/seat?examRoom.id=7987');
    expect(eamsRequests.first.url.queryParameters, {'semester.id': '263'});
    expect(eamsRequests.last.url.queryParameters, {'examBatch.id': '1222'});
    for (final r in eamsRequests) {
      expect(r.headers['cookie'], contains('JSESSIONID=eams-mock'));
      expect(r.headers['cookie'], isNot(contains('CASTGC')));
    }
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
  List<Map<String, dynamic>>? cached,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  if (account?.platform == ThirdPartyPlatform.ids) {
    await storage.setScheduleSource(
      '${account!.sid}|${account.account}', CampusScheduleSource.undergraduate,
    );
  }
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
  await storage.saveCachedAssignments(
    cached ?? [
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
    ],
  );
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
