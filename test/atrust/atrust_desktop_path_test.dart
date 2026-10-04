import 'dart:convert';

import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/atrust_control_client.dart';
import 'package:techpie/services/atrust_crypto.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';

/// Records what the desktop path and the trusted-terminal calls put on the wire,
/// so the shapes the protocol notes insist on can be asserted instead of assumed.
class _RecordingCampus {
  final List<http.Request> requests = [];
  bool trustDeviceAccepted = true;

  /// Fresh logins on this campus demand an SMS; once a session exists the
  /// controller answers without one (the trusted-terminal effect).
  int _authChecks = 0;

  http.Request? last(String path) {
    final matches = requests.where((r) => r.url.path == path);
    return matches.isEmpty ? null : matches.last;
  }

  bool calledEvery(String path) => requests.any((r) => r.url.path == path);

  http.Client client() => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path == '/passport/v1/public/authConfig') {
          return _json({
            'code': 0,
            'data': {
              'security': {'csrfToken': 'csrf-1'},
              'antiMITMAttackData': {
                'devicePubKeyMod': 'B9D641',
                'devicePubKeyExp': '10001',
                'challenge': 'Y2hhbGxlbmdlLWJhc2U2NA==',
                'rsaCert': 'CERT',
              },
            },
          });
        }
        if (path == '/passport/v1/public/casLogin') {
          return _redirect(
            'https://ids.test/authserver/login?service=https%3A%2F%2Fvpn.test%3A443',
          );
        }
        if (path == '/authserver/login') {
          return _redirect(
              'https://vpn.test:443/passport/v1/auth/cas?ticket=ST-1',);
        }
        if (path == '/passport/v1/auth/cas') {
          final data = jsonEncode({'ticket': 'cas-ticket-1'});
          return _redirect(
            'https://vpn.test/portal/shortcut.html?data=${Uri.encodeComponent(data)}',
            cookies: const {'sid': 'sid-1'},
          );
        }
        if (path == '/controller/v1/public/reportEnv') {
          return _json({'code': 0, 'message': 'OK'});
        }
        if (path == '/passport/v1/auth/authCheck') {
          final needsSms = _authChecks++ == 0;
          return _json({
            'code': 0,
            'data': {'nextService': needsSms ? 'auth/sms' : 'auth/authCheck'},
          });
        }
        if (path == '/passport/v1/auth/sms') {
          if (request.url.queryParameters['action'] == 'sendsms') {
            return _json({
              'code': 0,
              'data': {'tips': '验证码已发送到您的手机：155****7649'},
            });
          }
          return _json({
            'code': 0,
            'data': {'sidTicket': 'sid-ticket-1'},
          });
        }
        if (path == '/passport/v1/public/ticketExchange') {
          return _json({
            'code': 0,
            'data': {'sidTicket': 'sid-ticket-known'},
          });
        }
        if (path == '/passport/v1/public/sessionIdExchange') {
          return _json(
            {'code': 0, 'message': '成功'},
            cookies: const {'sid': 'sid-final'},
          );
        }
        if (path == '/passport/v1/user/onlineInfo') {
          return _json({
            'code': 0,
            'data': {'isOnline': true, 'username': '2023533189'},
          });
        }
        if (path == '/passport/v1/security/trustDevice') {
          return _json(
            trustDeviceAccepted
                ? {'code': 0, 'message': '成功'}
                : {
                    'code': 75500000,
                    'message': 'trusted terminals are not enabled',
                  },
          );
        }
        if (path == '/passport/v1/security/queryDevice') {
          return _json({
            'code': 0,
            'data': {
              'selfId': 'dev-self',
              'currentTrustStatus': 1,
              'trustDeviceConfig': {'enable': true},
              'data': [
                {
                  'id': 'dev-self',
                  'deviceName': 'Mac',
                  'deviceType': 'Mac',
                  'onlineStatus': true,
                },
              ],
            },
          });
        }
        if (path == '/controller/v1/user/clientResource') {
          return _json({
            'code': 0,
            'data': {
              'appList': {
                'data': <String, dynamic>{'config': <String, dynamic>{}},
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
                .map((e) => '${e.key}=${e.value}; path=/; secure')
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
                .map((e) => '${e.key}=${e.value}; path=/; secure')
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
    _RecordingCampus campus, {
    AtrustClientType type = AtrustClientType.desktop,
  }) =>
      AtrustControlClient(
        http: LoggingHttpClient(DebugLogger(), inner: campus.client()),
        storage: storage,
        castgc: () => 'CASTGC=TGT-1',
        clientType: type,
        baseUrl: Uri.parse('https://vpn.test'),
      );

  group('the desktop proof (protocol notes §10.1–10.2)', () {
    const modulus = 'B9D641';
    const exponent = '10001';
    const challenge = 'Y2hhbGxlbmdlLWJhc2U2NA==';

    test('derives a stable uppercase-hex key that moves with its inputs', () {
      final key = AtrustCrypto.signKey(
        devicePubKeyMod: modulus,
        devicePubKeyExp: exponent,
        challenge: challenge,
      );
      expect(RegExp(r'^[0-9A-F]{64}$').hasMatch(key), isTrue);
      expect(
        AtrustCrypto.signKey(
          devicePubKeyMod: modulus,
          devicePubKeyExp: exponent,
          challenge: challenge,
        ),
        key,
      );
      expect(
        AtrustCrypto.signKey(
          devicePubKeyMod: modulus,
          devicePubKeyExp: exponent,
          challenge: '${challenge}x',
        ),
        isNot(key),
      );
    });

    test('the encrypted challenge decrypts back to the challenge text',
        () async {
      final encrypted = await AtrustCrypto.encryptedChallenge(
        devicePubKeyMod: modulus,
        devicePubKeyExp: exponent,
        challenge: challenge,
      );
      expect(RegExp(r'^[0-9A-F]+$').hasMatch(encrypted), isTrue);
      expect(encrypted.length.isEven, isTrue);

      // Reproduce §10.2's key derivation and take the padding off by hand: if
      // this round trip holds, the cipher, the mode and the key source are the
      // ones the notes describe.
      final digest = sha256
          .convert(utf8.encode('$modulus$exponent'
              'OrHWuJz7gku5awmVb5w1sKTmfeCWHmzokBxmn0sn0faIcv1G10PdrbbRGKBrrZ3m'),)
          .bytes;
      final algorithm = AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty);
      final clear = await algorithm.decrypt(
        SecretBox(
          _hexToBytes(encrypted),
          nonce: digest.sublist(16, 32),
          mac: Mac.empty,
        ),
        secretKey: SecretKey(digest.sublist(0, 16)),
      );
      expect(utf8.decode(clear), challenge);
    });
  });

  test('a desktop login proves itself, is bound, and signs its resource fetch',
      () async {
    final campus = _RecordingCampus();
    final client = clientFor(campus);

    var state = await client.login();
    expect(state.stage, AtrustStage.needSms);
    state = await client.submitSms('720235');
    expect(state.stage, AtrustStage.online);
    expect(client.session!.trusted, isTrue);

    // reportEnv: enable=1 plus the encrypted challenge, addressed as SDPClient
    // with the platform first and no `lang` (a signed request's target is
    // covered byte for byte).
    final reportEnv = campus.last('/controller/v1/public/reportEnv')!;
    final body = jsonDecode(reportEnv.body) as Map<String, dynamic>;
    final antiMitm = body['antiMITMAttackData'] as Map<String, dynamic>;
    expect(antiMitm['enable'], 1);
    expect((antiMitm['encryptedChallenge'] as String).isNotEmpty, isTrue);
    expect(reportEnv.url.queryParameters['clientType'], 'SDPClient');
    expect(reportEnv.url.queryParameters.containsKey('lang'), isFalse);
    expect(
      reportEnv.url.queryParameters.keys.toList().sublist(0, 2),
      ['platform', 'clientType'],
    );

    // The device was bound after the login completed.
    expect(campus.calledEvery('/passport/v1/security/trustDevice'), isTrue);

    // The resource fetch on this path is signed over its exact target + body.
    final resource = campus.last('/controller/v1/user/clientResource')!;
    final expected = Hmac(
      sha256,
      _hexToBytes(AtrustCrypto.signKey(
        devicePubKeyMod: 'B9D641',
        devicePubKeyExp: '10001',
        challenge: 'Y2hhbGxlbmdlLWJhc2U2NA==',
      ),),
    ).convert(utf8.encode('${resource.url.path}?${resource.url.query}'
        '${jsonEncode(jsonDecode(resource.body))}'),);
    expect(
      resource.headers['X-Request-Sig']?.toUpperCase(),
      expected.toString().toUpperCase(),
    );
  });

  test('a browser login stays unsigned and never tries to bind', () async {
    final campus = _RecordingCampus();
    final client = clientFor(campus, type: AtrustClientType.browser);

    final state = await client.submitSmsAfterLogin('720235');
    expect(state.stage, AtrustStage.online);

    final reportEnv = campus.last('/controller/v1/public/reportEnv')!;
    final body = jsonDecode(reportEnv.body) as Map<String, dynamic>;
    final antiMitm = body['antiMITMAttackData'] as Map<String, dynamic>;
    expect(antiMitm['enable'], 0);
    expect(antiMitm['encryptedChallenge'], isNull);
    expect(reportEnv.url.queryParameters['clientType'], 'SDPBrowserClient');
    expect(reportEnv.url.queryParameters['lang'], 'zh-CN');
    expect(campus.calledEvery('/passport/v1/security/trustDevice'), isFalse);
    expect(
        campus
            .last('/controller/v1/user/clientResource')!
            .headers['X-Request-Sig'],
        isNull,);
    expect(client.session!.trusted, isFalse);
  });

  test('a refused binding leaves the session usable', () async {
    final campus = _RecordingCampus()..trustDeviceAccepted = false;
    final client = clientFor(campus);

    final state = await client.submitSmsAfterLogin('720235');

    expect(state.stage, AtrustStage.online);
    expect(client.session!.trusted, isFalse);
    expect(client.session!.policyJson, isNotEmpty);
  });

  test('the trusted-terminal list is readable', () async {
    final campus = _RecordingCampus();
    final client = clientFor(campus);
    await client.submitSmsAfterLogin('720235');

    final trust = await client.trustState();

    expect(trust.isTrusted, isTrue);
    expect(trust.devices.single.name, 'Mac');
  });
}

List<int> _hexToBytes(String hex) => <int>[
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

extension on AtrustControlClient {
  Future<AtrustLoginState> submitSmsAfterLogin(String code) async {
    final state = await login();
    return state.stage == AtrustStage.needSms ? submitSms(code) : state;
  }
}
