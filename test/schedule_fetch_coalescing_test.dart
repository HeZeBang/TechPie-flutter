import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
        account: '20240001',
        sid: '20240001',
        token: 'session',
        raw: const {'tgc': 'tgc-value'},
        boundAt: DateTime.utc(2026),
      ),
    );

    final logger = DebugLogger();
    final requests = <Uri>[];
    final http = LoggingHttpClient(logger, inner: _RecordingClient(requests));
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    await auth.loadSession();
    final tpAuth = ThirdPartyAuthService(storage, http);
    await tpAuth.initialize();

    final schedule = ScheduleService(storage, http, auth, tpAuth);
    expect(schedule.semesterInfo, isNull, reason: 'nothing in hand yet');

    // The burst: every one of these notifies the schedule through the same
    // listener, milliseconds apart.
    for (final marker in ['a', 'b', 'c']) {
      await tpAuth.updateRaw(
        ThirdPartyPlatform.cpdaily,
        {'tgc': 'tgc-value', 'cookies': 'CASTGC=$marker'},
      );
    }

    // Past the coalescing window.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(
      requests.length,
      1,
      reason: 'the burst is one round; the client fails on the first request, '
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
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
        account: '20240001',
        sid: '20240001',
        token: 'session',
        raw: const {'tgc': 'tgc-value'},
        boundAt: DateTime.utc(2026),
      ),
    );

    final logger = DebugLogger();
    final requests = <Uri>[];
    final http = LoggingHttpClient(logger, inner: _AnsweringClient(requests));
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    await auth.loadSession();
    final tpAuth = ThirdPartyAuthService(storage, http);
    await tpAuth.initialize();

    final schedule = ScheduleService(storage, http, auth, tpAuth);
    schedule.requestFetch(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(
      _pathsOf(requests).where((path) => path.contains('/schedule/')).toList(),
      [
        '/api/schedule/semesters',
        '/api/schedule/course_table',
        '/api/schedule/term_begin',
      ],
      reason: 'the first forced trigger is what fetches at boot',
    );
    expect(schedule.error, isNull);

    // The fan-out's own forced call, for the same account.
    schedule.requestFetch(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(
      _pathsOf(requests).where((path) => path.contains('/schedule/')).length,
      3,
      reason: 'a successful round is the answer; do not ask for it again',
    );
  });
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
      // The eams cookie is minted from the parent tgc before a timetable fetch
      // can carry one.
      '/api/auth/third-party/eams' => jsonEncode({
          'success': true,
          'data': {'token': 'CASTGC=eams-cookie'},
        }),
      '/api/schedule/semesters' => jsonEncode({
          'success': true,
          'data': {
            'semesters': {
              '2025-2026': {'秋': 'sem-1'},
            },
            'defaultSemester': 'sem-1',
            'tableId': 't1',
          },
        }),
      '/api/schedule/course_table' => jsonEncode({
          'success': true,
          'data': {'periods': <Object?>[], 'courses': <Object?>[]},
        }),
      '/api/schedule/term_begin' => jsonEncode({
          'success': true,
          'data': {
            'termBegin': '2026-09-07T00:00:00.000',
            'allTeachWeeks': 16,
            'weekOfTerm': '1',
            'date': '2026-09-07T00:00:00.000',
          },
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
    throw const _Refused();
  }
}

class _Refused implements Exception {
  const _Refused();

  @override
  String toString() => 'SocketException: connection refused';
}
