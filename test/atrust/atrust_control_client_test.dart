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
  _FakeCampus({
    this.smsRequired = true,
    this.castgcAccepted = true,
    this.sendsmsErrorCode,
  });

  final bool smsRequired;

  /// False models an expired campus session: IDS answers with its login page
  /// instead of bouncing back with a ticket.
  final bool castgcAccepted;

  /// When set, `sendsms` answers this controller code instead of sending.
  /// 75500401 is what the real controller answers to a repeat inside a code's
  /// lifetime.
  final int? sendsmsErrorCode;

  /// Whether the controller accepts a trusted-terminal binding. False models the
  /// refusal that leaves a session untrusted — and so costs an SMS on the next
  /// full login.
  bool trustDeviceAccepted = true;

  /// Bodies the controller received for the terminal-management calls.
  Map<String, dynamic>? untrustBody;
  Map<String, dynamic>? trustBody;
  Map<String, dynamic>? logoutBody;

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
            if (sendsmsErrorCode != null) {
              return _json({
                'code': sendsmsErrorCode,
                'message': '短信发送被拒',
              });
            }
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
        if (path == '/passport/v1/security/queryDevice') {
          return _json({
            'code': 0,
            'message': '成功',
            'data': {
              'selfId': 'dev-self',
              'currentTrustStatus': 0,
              'trustDeviceConfig': {'enable': true},
              'data': const <Object>[],
            },
          });
        }
        if (path == '/passport/v1/security/logoutDevice') {
          logoutBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'code': 0, 'message': '成功'});
        }
        if (path == '/passport/v1/security/trustDevice') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          // A removal is the same call with `untrustIdList` (captured from the
          // campus portal); a binding carries `idList`.
          if (body.containsKey('untrustIdList')) {
            untrustBody = body;
            return _json({'code': 0, 'message': '成功'});
          }
          trustBody = body;
          return _json({
            'code': trustDeviceAccepted ? 0 : 75500000,
            'message': trustDeviceAccepted ? '成功' : '当前会话无法添加授信终端',
          });
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

  AtrustControlClient clientFor(
    _FakeCampus campus, {
    String castgc = 'CASTGC=TGT-1',
    AtrustClientType type = AtrustClientType.browser,
  }) =>
      AtrustControlClient(
        http: LoggingHttpClient(DebugLogger(), inner: campus.client()),
        storage: storage,
        castgc: () => castgc,
        clientType: type,
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

  test('a code that is still valid is not a failure', () async {
    final campus = _FakeCampus(sendsmsErrorCode: 75500401);
    final client = clientFor(campus);

    final state = await client.login();

    // No second text was sent, but the retry still lands on the code prompt
    // instead of failing — the user has a code, they just have to type it.
    expect(state.stage, AtrustStage.needSms);
    expect(state.hint, isNotEmpty);

    final online = await client.submitSms('720235');
    expect(online.stage, AtrustStage.online);
    expect(campus.submittedCode, '720235');
  });

  test('any other refusal to send the code is still a failure', () async {
    final campus = _FakeCampus(sendsmsErrorCode: 75599999);
    await expectLater(
      clientFor(campus).login(),
      throwsA(
        isA<AtrustException>()
            .having((e) => e.code, 'code', 'sendsms')
            .having((e) => e.controllerCode, 'controllerCode', 75599999),
      ),
    );
  });

  test('a restored client-mode session can be bound manually', () async {
    final campus = _FakeCampus()..trustDeviceAccepted = false;
    final first = clientFor(campus, type: AtrustClientType.desktop);
    await first.submitSmsAfterLogin('720235');
    expect(first.session!.trusted, isFalse);
    // The refusal is kept, because the caller turns it into the sentence the
    // user reads (a full list vs. a session that needs an SMS code).
    expect(first.lastBindRefusal, 75500000);

    // A refusal is not fatal; when the controller starts accepting bindings,
    // the feature page's explicit bind action can retry on the same session.
    campus.trustDeviceAccepted = true;
    final restoredClient = clientFor(campus, type: AtrustClientType.desktop);
    final restored = await restoredClient.ensureOnline();

    expect(restored.stage, AtrustStage.online);
    expect(restored.restored, isTrue);
    expect(await restoredClient.bindDevice(), isTrue);
    expect(campus.calls, contains('POST /passport/v1/security/trustDevice'));
  });

  test('a terminal can be removed from the trusted list', () async {
    final campus = _FakeCampus();
    final client = clientFor(campus, type: AtrustClientType.desktop);
    await client.submitSmsAfterLogin('720235');

    // The list has a limit, so removing a terminal is how a new device fits.
    await client.untrustDevices(const ['dev-1', 'dev-2']);
    await client.logoutDevice('dev-3');

    // The captured campus portal removes terminals with `trustDevice` itself,
    // carrying `untrustIdList` — not with `/security/untrustDevice`, which this
    // controller answers 75510008 for every id its own list hands out.
    expect(campus.calls, contains('POST /passport/v1/security/trustDevice'));
    expect(campus.calls, contains('POST /passport/v1/security/logoutDevice'));
    expect(campus.untrustBody, {
      'untrustIdList': ['dev-1', 'dev-2'],
    });
    expect(campus.logoutBody, {'id': 'dev-3'});
  });

  test('removing nothing is refused before it reaches the controller', () async {
    final campus = _FakeCampus();
    final client = clientFor(campus, type: AtrustClientType.desktop);
    await client.submitSmsAfterLogin('720235');

    await expectLater(
      client.untrustDevices(const []),
      throwsA(
        isA<AtrustException>()
            .having((e) => e.code, 'code', 'trustDevice'),
      ),
    );
    expect(campus.untrustBody, isNull);
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

  test('a stored session records the path it was opened on', () async {
    final campus = _FakeCampus();
    await clientFor(campus, type: AtrustClientType.desktop)
        .submitSmsAfterLogin('720235');

    final raw = jsonDecode((await storage.loadAtrustSession())!)
        as Map<String, dynamic>;
    expect(raw['client_type'], 'desktop');

    // A session from a build that recorded no path belongs to neither one, so
    // it is never handed to a client that asks on one of them.
    raw.remove('client_type');
    expect(AtrustSession.fromJson(raw)!.clientType, isNull);
  });

  test('a session opened on one path is not handed to the other', () async {
    final campus = _FakeCampus();
    await clientFor(campus, type: AtrustClientType.desktop)
        .submitSmsAfterLogin('720235');

    // The mode is a property of the session — the server fixes it from the path
    // that opened it, and a pure web session never carries the client path's
    // tunnel. Restoring it onto the other path is what kept such a session in
    // play forever while every tunnel attempt was refused, so this re-opens the
    // session instead of answering from storage.
    final other = await clientFor(campus).ensureOnline();
    expect(other.restored, isFalse);
    expect(other.stage, AtrustStage.needSms);
  });
}

extension on AtrustControlClient {
  /// Convenience for tests: login, then answer the SMS the controller asked for.
  Future<AtrustLoginState> submitSmsAfterLogin(String code) async {
    final state = await login();
    return state.stage == AtrustStage.needSms ? submitSms(code) : state;
  }
}
