import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/atrust_control_client.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';

/// A scripted stand-in for the campus pair: the aTrust controller and the IDS
/// CAS endpoint. The envelope shapes and the redirect chain are the ones the
/// live pair produced, so the client is driven through the real sequence rather
/// than a happy-path stub.
class _FakeCampus {
  _FakeCampus({this.smsRequired = true, this.castgcAccepted = true});

  final bool smsRequired;

  /// False models an expired campus session: IDS answers with its login page
  /// instead of bouncing back with a ticket.
  final bool castgcAccepted;

  final List<String> calls = [];
  final List<Map<String, String>> requestHeaders = [];
  String? submittedCode;

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        calls.add('${request.method} $path');
        requestHeaders.add(request.headers);

        if (path == '/passport/v1/public/authConfig') {
          return _json({
            'code': 0,
            'message': '成功',
            'data': {
              'security': {'csrfToken': 'csrf-1'},
              'antiMITMAttackData': {
                'devicePubKeyMod': 'MOD',
                'devicePubKeyExp': '10001',
                'rsaCert': 'CERT',
              },
              'firstAuth': [
                '/passport/v1/public/casLogin?sfDomain=Shanghaitech.edu.cn',
              ],
            },
          });
        }
        if (path == '/passport/v1/public/casLogin') {
          return _redirect(
            'https://ids.test/authserver/login?service='
            'https%3A%2F%2Fvpn.test%3A443%2Fpassport%2Fv1%2Fauth%2Fcas',
          );
        }
        if (path == '/authserver/login') {
          if (!castgcAccepted) {
            return http.Response('<html>login</html>', 200);
          }
          return _redirect(
            'https://vpn.test:443/passport/v1/auth/cas?ticket=ST-1',
            cookies: const {'route': 'r1', 'JSESSIONID': 'j1'},
          );
        }
        if (path == '/passport/v1/auth/cas') {
          final data = jsonEncode({
            'ticket': 'cas-ticket-1',
            'env': {'need': true},
          });
          return _redirect(
            'https://vpn.test/portal/shortcut.html?source=auth_cas'
            '&username=2023533189&data=${Uri.encodeComponent(data)}'
            '&nextService=auth%2FauthCheck',
            cookies: const {'sid': 'sid-1', 'sid-legacy': 'legacy-1'},
          );
        }
        if (path == '/controller/v1/public/reportEnv') {
          return _json({'code': 0, 'message': 'OK'});
        }
        if (path == '/passport/v1/auth/authCheck') {
          return _json({
            'code': 0,
            'message': '成功',
            'data': {
              'nextService': smsRequired ? 'auth/sms' : 'auth/authCheck',
              'nextServiceList': [
                {'authType': smsRequired ? 'auth/sms' : 'auth/authCheck'},
              ],
            },
          });
        }
        if (path == '/passport/v1/auth/sms') {
          final action = request.url.queryParameters['action'];
          if (action == 'sendsms') {
            return _json({
              'code': 0,
              'message': '短信发送成功',
              'data': {'tips': '验证码已发送到您的手机：155****7649'},
            });
          }
          submittedCode = (jsonDecode(request.body) as Map)['code'] as String?;
          return _json({
            'code': 0,
            'message': '短信认证成功',
            'data': {'sidTicket': 'sid-ticket-sms'},
          });
        }
        if (path == '/passport/v1/public/ticketExchange') {
          return _json({
            'code': 0,
            'message': '成功',
            'data': {'sidTicket': 'sid-ticket-known-device'},
          });
        }
        if (path == '/passport/v1/public/sessionIdExchange') {
          final body = jsonDecode(request.body) as Map;
          if (body['sidTicket'] != 'sid-ticket-sms' &&
              body['sidTicket'] != 'sid-ticket-known-device') {
            return _json({'code': 1, 'message': 'bad ticket'});
          }
          return _json(
            {'code': 0, 'message': '成功'},
            cookies: const {'sid': 'sid-final', 'sid.sig': 'sig-final'},
          );
        }
        if (path == '/passport/v1/user/onlineInfo') {
          return _json({
            'code': 0,
            'message': '成功',
            'data': {
              'isOnline': true,
              'username': '2023533189',
              'displayName': '贺泽邦',
            },
          });
        }
        if (path == '/controller/v1/user/clientResource') {
          return _json({
            'code': 0,
            'message': '成功',
            'data': {
              'appList': {
                'data': {
                  'config': {
                    'nodeGroupConf': {
                      'majorNodeGroup': {'id': 'group-1'},
                      'nodeGroupList': <dynamic>[],
                    },
                  },
                },
              },
            },
          });
        }
        return http.Response('unexpected $path', 404);
      });

  static http.Response _json(
    Map<String, dynamic> body, {
    Map<String, String>? cookies,
  }) =>
      http.Response(
        jsonEncode(body),
        200,
        headers: {
          'content-type': 'application/json',
          if (cookies != null)
            'set-cookie': cookies.entries
                .map((e) => '${e.key}=${e.value}; path=/; secure; httponly')
                .join(', '),
        },
      );

  static http.Response _redirect(String location,
          {Map<String, String>? cookies,}) =>
      http.Response(
        '',
        302,
        headers: {
          'location': location,
          if (cookies != null)
            'set-cookie': cookies.entries
                .map((e) => '${e.key}=${e.value}; path=/; secure; httponly')
                .join(', '),
        },
      );
}

void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
  });

  AtrustControlClient clientFor(_FakeCampus campus,
          {String castgc = 'CASTGC=TGT-1',}) =>
      AtrustControlClient(
        http: LoggingHttpClient(DebugLogger(), inner: campus.client()),
        storage: storage,
        castgc: () => castgc,
        baseUrl: Uri.parse('https://vpn.test'),
      );

  test('a session that needs SMS completes and is handed over intact',
      () async {
    final campus = _FakeCampus();
    final client = clientFor(campus);

    final first = await client.login();
    expect(first.stage, AtrustStage.needSms);
    expect(first.hint, contains('155****7649'));

    final second = await client.submitSms('720235');
    expect(second.stage, AtrustStage.online);
    expect(campus.submittedCode, '720235');

    final session = client.session!;
    expect(session.sid, 'sid-final');
    expect(session.username, '2023533189');
    expect(session.cookies['sid.sig'], 'sig-final');
    // The policy is the controller's own bytes, re-encoded — not a re-modelled
    // subset of it.
    expect(jsonDecode(session.policyJson), contains('appList'));

    // Every controller call after authConfig carries the CSRF header.
    final authed = campus.calls.indexOf('POST /controller/v1/public/reportEnv');
    expect(authed, greaterThan(0));
    expect(campus.requestHeaders[authed]['x-csrf-token'], 'csrf-1');

    // It survives a restart.
    final stored = AtrustSession.fromJson(
      jsonDecode((await storage.loadAtrustSession())!),
    )!;
    // 32 uppercase hex: a shorter or lowercase value is a different device to
    // the controller, which costs the user another SMS.
    expect(RegExp(r'^[0-9A-F]{32}$').hasMatch(stored.deviceId), isTrue);
  });

  test('a stored session is restored without logging in again', () async {
    final campus = _FakeCampus();
    await clientFor(campus).submitSmsAfterLogin('720235');

    final callsBefore = campus.calls.length;
    final restored = await clientFor(campus).ensureOnline();

    expect(restored.stage, AtrustStage.online);
    expect(restored.restored, isTrue);
    expect(campus.calls.sublist(callsBefore),
        ['GET /passport/v1/user/onlineInfo'],);
  });

  test('a device the controller already knows skips SMS', () async {
    final campus = _FakeCampus(smsRequired: false);
    final state = await clientFor(campus).login();

    expect(state.stage, AtrustStage.online);
    expect(campus.calls, contains('POST /passport/v1/public/ticketExchange'));
    expect(campus.calls, isNot(contains('POST /passport/v1/auth/sms')));
  });

  test('an expired campus session fails as a CAS failure, not a crash',
      () async {
    final campus = _FakeCampus(castgcAccepted: false);
    await expectLater(
      clientFor(campus).login(),
      throwsA(
        isA<AtrustException>().having((e) => e.code, 'code', 'casTicket'),
      ),
    );
  });

  test('no campus binding means no login attempt at all', () async {
    final campus = _FakeCampus();
    final state = await clientFor(campus, castgc: '').login();

    expect(state.stage, AtrustStage.unavailable);
    expect(campus.calls, isEmpty);
  });

  test('logout drops the stored session', () async {
    final campus = _FakeCampus();
    final client = clientFor(campus);
    await client.submitSmsAfterLogin('720235');
    expect(await storage.loadAtrustSession(), isNotNull);

    await client.logout();

    expect(client.session, isNull);
    expect(await storage.loadAtrustSession(), isNull);
  });
}

extension on AtrustControlClient {
  /// Convenience for tests: login, then answer the SMS the controller asked for.
  Future<AtrustLoginState> submitSmsAfterLogin(String code) async {
    final state = await login();
    return state.stage == AtrustStage.needSms ? submitSms(code) : state;
  }
}
