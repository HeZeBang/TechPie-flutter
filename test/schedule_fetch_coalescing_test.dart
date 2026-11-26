import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/campus_identity.dart';
import 'package:techpie/models/course_table.dart';
import 'package:techpie/models/ids_passkey.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/ids/ids_client.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/school_calendar_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

import 'support/eams_transport.dart';
import 'support/fake_ids_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manual watch sync adopts an unowned legacy table for one account across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final http = LoggingHttpClient(DebugLogger());
    final auth = AuthService(storage, http, UniAuthService());
    final accounts = ThirdPartyAuthService(storage, http);
    await storage.setSelectedSemester('old');
    await storage.saveCourseTable('old', const CourseTable(periods: [], courses: []));
    final schedule = ScheduleService(storage, http, auth, accounts);
    await schedule.loadCachedData();
    expect(schedule.courseTableForWatch('wear:alice'), isNull);
    await schedule.adoptLegacyCourseTable('wear:alice');
    final reopened = ScheduleService(storage, http, auth, accounts);
    await reopened.loadCachedData();
    await reopened.adoptLegacyCourseTable('wear:bob');
    expect(reopened.courseTableForWatch('wear:alice'), isNotNull);
    expect(reopened.courseTableForWatch('wear:bob'), isNull);
    expect(reopened.courseTable, isNotNull);

    // Grants written by the older watch branch used the owner field.
    await storage.saveCourseTable('old', const CourseTable(periods: [], courses: []), owner: 'wear:alice');
    expect(reopened.courseTableForWatch('wear:alice'), isNotNull);
    expect(reopened.courseTableForWatch('wear:bob'), isNull);
  });

  // Around a login the triggers all fire inside the same second — the binding
  // lands, the session is renewed, a child cookie is minted — and each of them
  // used to start a round of its own: three rounds of three requests for one
  // login. They go through one funnel now, which collapses the burst.
  test('a burst of triggers is one round of requests, not one each', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.saveThirdPartyAccount(
      FakeIdsClient.account('20240001'),
    );

    final logger = DebugLogger();
    final requests = <Uri>[];
    final server = _RecordingClient(requests);
    final http = LoggingHttpClient(logger, inner: server);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    await auth.loadSession();
    final tpAuth = ThirdPartyAuthService(storage, http, idsClient: FakeIdsClient());
    await tpAuth.initialize();

    final schedule = ScheduleService(
      storage,
      http,
      auth,
      tpAuth,
      eamsTransport: eamsTransport(server),
      eamsInterval: Duration.zero,
    );
    addTearDown(schedule.dispose);
    expect(schedule.semesterInfo, isNull, reason: 'nothing in hand yet');

    // The burst: every one of these notifies the schedule through the same
    // listener, milliseconds apart.
    for (final marker in ['a', 'b', 'c']) {
      await tpAuth.updateRaw(
        ThirdPartyPlatform.ids,
        {'tgc': 'tgc-value', 'cookies': 'CASTGC=$marker'},
      );
    }

    // Past the coalescing window.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(
      _pathsOf(requests).where((path) => path.startsWith('/eams/courseTableForStd')).length,
      1,
      reason: 'the burst is one round; the client fails on the first business request, '
          'so a second round would show up as a second request',
    );
  });
  // Triggers keep arriving while a round is in flight — the keep-alive and the
  // renewal both notify — and the boot's fan-out asks again with `force` for the
  // same account. Once a round has succeeded there is nothing left to ask for,
  // so neither may start a second one.
  test('triggers during and after a round do not repeat it',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.saveThirdPartyAccount(
      FakeIdsClient.account('20240001'),
    );

    final logger = DebugLogger();
    final requests = <Uri>[];
    final server = _AnsweringClient(requests);
    final http = LoggingHttpClient(logger, inner: server);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    await auth.loadSession();
    final tpAuth = ThirdPartyAuthService(storage, http, idsClient: FakeIdsClient());
    await tpAuth.initialize();

    final schedule = ScheduleService(
      storage,
      http,
      auth,
      tpAuth,
      eamsTransport: eamsTransport(server),
      eamsInterval: Duration.zero,
    );
    addTearDown(schedule.dispose);
    schedule.requestFetch(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(
      _pathsOf(requests)
          .where(
            (path) =>
                (path.startsWith('/eams/courseTableForStd') || path == '/eams/dataQuery.action'),
          )
          .toList(),
      [
        '/eams/courseTableForStd.action',
        '/eams/dataQuery.action',
        '/eams/courseTableForStd!courseTable.action',
      ],
      reason: 'the first forced trigger is what fetches at boot',
    );
    expect(
      _pathsOf(requests).where((path) => path == SchoolCalendarClient.calendarPath).toList(),
      [SchoolCalendarClient.calendarPath],
      reason: 'term calendar is fetched directly from eGate instead of /api/schedule/term_begin',
    );
    expect(schedule.error, isNull);

    // The fan-out's own forced call, for the same account.
    schedule.requestFetch(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(
      _pathsOf(requests)
          .where(
            (path) =>
                (path.startsWith('/eams/courseTableForStd') || path == '/eams/dataQuery.action'),
          )
          .length,
      3,
      reason: 'a successful round is the answer; do not ask for it again',
    );
  });

  test('fetchTermBegin authenticates directly against eGate via IDS and isolates CASTGC', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.saveThirdPartyAccount(FakeIdsClient.account('20240001'));

    final recorded = <http.BaseRequest>[];
    final idsClient = _RotatingIdsClient();
    final httpClient = LoggingHttpClient(
      DebugLogger(),
      inner: _CalendarCasClient(recorded),
    );
    final auth = AuthService(storage, httpClient, UniAuthService());
    await auth.loadSession();
    final tpAuth = ThirdPartyAuthService(storage, httpClient, idsClient: idsClient);
    await tpAuth.initialize();

    final schedule = ScheduleService(storage, httpClient, auth, tpAuth);
    addTearDown(schedule.dispose);
    await storage.setScheduleSource('20240001|20240001', CampusScheduleSource.undergraduate);

    await schedule.fetchTermBegin('2026', '1', 'sem-2026-1');

    expect(schedule.termBegin, DateTime(2026, 9, 14));
    expect(schedule.termCalendar?.allTeachWeeks, 16);
    expect(schedule.termCalendar?.snapshotWeekOfTerm, 11);
    expect(idsClient.loginCalls, 1, reason: 'stale CASTGC triggers one IDS Passkey renewal');
    expect(
      recorded.any((r) => r.url.path.contains('/api/schedule/term_begin')),
      isFalse,
      reason: 'must not send EAMS cookies to /api/schedule/term_begin',
    );
    for (final req in recorded.where((r) => r.url.host == SchoolCalendarClient.host)) {
      expect(
        req.headers['Cookie'] ?? '',
        isNot(contains('CASTGC=')),
        reason: 'CASTGC must never be sent to egate.shanghaitech.edu.cn',
      );
    }
    expect(
      recorded
          .where((r) => r.url.host == SchoolCalendarClient.idsHost)
          .every((r) => (r.headers['Cookie'] ?? '').contains('CASTGC=')),
      isTrue,
    );
  });
}

class _RotatingIdsClient extends FakeIdsClient {
  int loginCalls = 0;

  @override
  Future<IdsSession> login(IdsPasskey secret, {bool backedUp = false}) async {
    loginCalls++;
    return IdsSession(secret.username, {'tgc': 'tgc-fresh', 'cookies': ''}, name: 'User');
  }
}

class _CalendarCasClient extends http.BaseClient {
  _CalendarCasClient(this.recorded);

  final List<http.BaseRequest> recorded;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    recorded.add(request);
    final uri = request.url;
    final cookie = request.headers['Cookie'] ?? '';
    if (uri.host == SchoolCalendarClient.host && uri.path == SchoolCalendarClient.calendarPath) {
      expect(uri.queryParameters['schoolYearTerm'], '2026-2027-2');
      expect(uri.queryParameters['termJump'], 'prev');
      if (uri.queryParameters['ticket'] == 'ST-calendar-ok') {
        return http.StreamedResponse(
          Stream.value(const []),
          302,
          headers: {
            'location': SchoolCalendarClient.buildCalendarUri(
              schoolYearTerm: '2026-2027-2',
              termJump: 'prev',
            ).toString(),
            'set-cookie': 'MOD_AUTH_CAS=cal-session; Path=/publicapp; Secure; HttpOnly',
          },
        );
      }
      if (cookie.contains('MOD_AUTH_CAS=cal-session')) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'code': '200',
                'schoolYearTerm': '2026-2027-1',
                'termBegin': '2026-09-14',
                'date': '2026-11-24',
                'weekOfTerm': 11,
                'allTeachWeeks': '16',
                'allTermWeeks': '18',
                'amClasses': '4',
                'pmClasses': '5',
                'eveClasses': '4',
              }),
            ),
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.StreamedResponse(
        Stream.value(const []),
        302,
        headers: {
          'location': Uri.https(
            SchoolCalendarClient.idsHost,
            '/authserver/login',
            {'service': uri.toString()},
          ).toString(),
        },
      );
    }
    if (uri.host == SchoolCalendarClient.idsHost && uri.path == '/authserver/login') {
      if (cookie.contains('CASTGC=tgc-fresh')) {
        final service = Uri.parse(uri.queryParameters['service']!);
        return http.StreamedResponse(
          Stream.value(const []),
          302,
          headers: {
            'location': service.replace(
              queryParameters: {...service.queryParameters, 'ticket': 'ST-calendar-ok'},
            ).toString(),
          },
        );
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode('<html><input name="execution" value="e1s1">统一身份认证</html>')),
        200,
        headers: const {'content-type': 'text/html; charset=utf-8'},
      );
    }
    return http.StreamedResponse(Stream.value(const []), 404);
  }
}

/// Answers the three timetable endpoints successfully, so a round can finish and
/// the service can record which account it fetched for.
class _AnsweringClient extends http.BaseClient {
  _AnsweringClient(this.requests);

  final List<Uri> requests;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final body = switch (request.url.path) {
      '/personalInfo/personCenter/index.html' => '<html>IDS</html>',
      '/personalInfo/common/getUserConf' => jsonEncode({
        'code': '0',
        'datas': {'uid': '20240001', 'categoryName': '学生/本科生'},
      }),
      '/eams/courseTableForStd.action' => scheduleEntry('sem-1'),
      '/eams/dataQuery.action' => semesterOptions('2025-2026', 'sem-1'),
      '/eams/courseTableForStd!courseTable.action' => emptyTimetable,
      SchoolCalendarClient.calendarPath => jsonEncode({
          'code': 200,
          'schoolYearTerm': '2025-2026-1',
          'termBegin': '2026-09-07T00:00:00.000',
          'allTeachWeeks': 16,
          'weekOfTerm': '1',
          'date': '2026-09-07T00:00:00.000',
        }),
      _ => jsonEncode({'success': false, 'error': 'unexpected'}),
    };
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

List<String> _pathsOf(List<Uri> requests) =>
    [for (final uri in requests) uri.path];

/// Counts what was asked for and answers with a failure: this test is about how
/// many rounds are started, not about what comes back.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.requests);

  final List<Uri> requests;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    if (request.url.host == 'ids.shanghaitech.edu.cn') {
      final body = request.url.path.endsWith('index.html')
          ? '<html>IDS</html>'
          : jsonEncode({
              'code': '0',
              'datas': {'uid': '20240001', 'categoryName': '学生/本科生'},
            });
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    }
    throw const _Refused();
  }
}

class _Refused implements Exception {
  const _Refused();

  @override
  String toString() => 'SocketException: connection refused';
}
