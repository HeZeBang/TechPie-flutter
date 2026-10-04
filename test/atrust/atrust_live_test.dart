import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/atrust_control_client.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';

/// Opt-in test against the live campus. Skipped unless all three are set:
///
/// ```sh
/// ATRUST_CASTGC='TGT-…' ATRUST_DEVICE_ID='E8483C84…' ATRUST_SMS_CODE='123456' \
///   flutter test test/atrust/atrust_live_test.dart
/// ```
///
/// **Running this sends a real SMS**: the browser client type re-verifies the
/// device on every fresh login, so `login` reaches `needSms` and asks the
/// controller to text a code — the one you pass in — before it goes online. A
/// *restored* session needs no code at all.
///
/// The CASTGC is the campus binding's IDS session (TechPie stores it). Nothing
/// here is run by CI: no env, no network.
void main() {
  final castgc = Platform.environment['ATRUST_CASTGC'] ?? '';
  final deviceId = Platform.environment['ATRUST_DEVICE_ID'] ?? '';
  final smsCode = Platform.environment['ATRUST_SMS_CODE'] ?? '';

  test(
    'live: the campus session logs in and hands over a policy',
    () async {
      SharedPreferences.setMockInitialValues({'atrust_device_id': deviceId});
      FlutterSecureStorage.setMockInitialValues({});
      final storage = StorageService(await SharedPreferences.getInstance());
      final client = AtrustControlClient(
        http: _directHttp(),
        storage: storage,
        castgc: () => 'CASTGC=$castgc',
      );

      var state = await client.login();
      // ignore: avoid_print
      print('login → ${state.stage} ${state.hint}');
      expect(state.stage, AtrustStage.needSms);
      expect(state.hint, isNotEmpty);
      state = await client.submitSms(smsCode);
      // ignore: avoid_print
      print('submitSms → ${state.stage}');
      expect(state.stage, AtrustStage.online);

      final session = client.session!;
      final policy = jsonDecode(session.policyJson) as Map<String, dynamic>;
      final apps = (policy['appList'] as Map?)?['data'];
      // ignore: avoid_print
      print(
        'session: user=${session.username} sid=${session.sid.length}B '
        'cookies=${session.cookies.length} policy=${session.policyJson.length}B '
        'appList=${apps == null ? 'absent' : 'present'}',
      );
      expect(session.username, isNotEmpty);
      expect(session.sid, isNotEmpty);
      expect(policy, contains('appList'));

      // A second call must come from storage, not from a fresh login.
      final again = await clientFor(storage, castgc).ensureOnline();
      expect(again.restored, isTrue);
      // ignore: avoid_print
      print('restore → ${again.stage} restored=${again.restored} (no SMS)');

      // And the policy must survive the round trip through storage, because the
      // core library is handed exactly this string.
      final stored = AtrustSession.fromJson(
        jsonDecode((await storage.loadAtrustSession())!),
      )!;
      expect(stored.policyJson, session.policyJson);
      expect(stored.deviceId, deviceId);
    },
    skip: (castgc.isEmpty || deviceId.isEmpty || smsCode.isEmpty)
        ? 'set ATRUST_CASTGC, ATRUST_DEVICE_ID and ATRUST_SMS_CODE '
              '(running it sends a real SMS)'
        : false,
  );
}

AtrustControlClient clientFor(StorageService storage, String castgc) =>
    AtrustControlClient(
      http: _directHttp(),
      storage: storage,
      castgc: () => 'CASTGC=$castgc',
    );

/// Direct sockets. This machine's Dart HTTP is wrapped in a local proxy that
/// the campus edge terminates mid-handshake — a device has no such proxy, so
/// the test bypasses it to exercise what the app will actually see.
LoggingHttpClient _directHttp() => LoggingHttpClient(
  DebugLogger(),
  inner: IOClient(HttpClient()..findProxy = (uri) => 'DIRECT'),
);
