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

import 'support/fake_ids_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Renewing a campus session — or letting a sync merge replace it — changes what
  // a timetable fetch can see, and nothing about it looks like "the binding
  // changed". With an empty table on screen that is the difference between a page
  // that recovers by itself and one that stays empty until a manual pull.
  test('a session change with no timetable in hand fetches one', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.saveThirdPartyAccount(
      FakeIdsClient.account('20240001'),
    );

    final logger = DebugLogger();
    final requests = <Uri>[];
    final http = LoggingHttpClient(logger, inner: _RecordingClient(requests));
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    await auth.loadSession();
    final tpAuth = ThirdPartyAuthService(storage, http, idsClient: FakeIdsClient());
    await tpAuth.initialize();

    final schedule = ScheduleService(storage, http, auth, tpAuth);
    expect(requests, isEmpty, reason: 'constructing it does not fetch');
    expect(schedule.semesterInfo, isNull, reason: 'nothing in hand');

    // What a renewal or a sync merge amounts to, from a listener's point of view.
    await tpAuth.updateRaw(
      ThirdPartyPlatform.ids,
      const {'tgc': 'tgc-value', 'cookies': 'CASTGC=renewed'},
    );
    // Past the window requestFetch coalesces over.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(
      requests.where((url) => url.path.startsWith('/api/schedule/')),
      isNotEmpty,
      reason: 'the table was empty, so a renew has to lead to a fetch',
    );
  });
}

/// Answers everything with a failure: this test is about whether a fetch is
/// attempted, not about what it makes of the answer.
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
