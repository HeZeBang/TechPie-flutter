import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/ids_passkey.dart';
import 'package:techpie/services/ids/campus_http.dart';
import 'package:techpie/services/ids/ids_client.dart';
import 'package:techpie/services/ids/software_passkey.dart';

void main() {
  test('distinguishes a rejected password and asks for captcha after repeated failures', () async {
    final adapter = _School()..passwordErrors.addAll(['您提供的用户名或者密码有误', '用户名或密码错误']);
    final client = IdsClient(http: Dio()..httpClientAdapter = adapter);
    Future<({IdsPasskey credential, IdsSession session})> attempt() => client.register(
          '20240001',
          'synthetic-password',
          promptCaptcha: (_, error, {required refresh}) async => 'manual-code',
          saveCandidate: (key) async {
            adapter.key = key;
          },
        );
    for (var i = 0; i < 2; i++) {
      await expectLater(
        attempt(),
        throwsA(
          isA<IdsException>().having((e) => e.message, 'message', contains('账号或密码错误')),
        ),
      );
    }
    expect(adapter.authCaptchaRequests, 0);
    await attempt();
    expect(adapter.authCaptchaRequests, 1);
    expect(adapter.passwordForms.last['captcha'], 'manual-code');
    expect(
      adapter.requests.where((r) => r.uri.path.endsWith('checkNeedCaptcha.htl')),
      hasLength(3),
    );
  });

  test('a wrong login captcha prompts again with a fresh execution and explicit error', () async {
    final adapter = _School()
      ..forceLoginCaptcha = true
      ..passwordErrors.add('验证码错误');
    final client = IdsClient(http: Dio()..httpClientAdapter = adapter);
    final errors = <String?>[];
    await client.register(
      '20240001',
      'synthetic-password',
      promptCaptcha: (_, error, {required refresh}) async {
        errors.add(error);
        return 'manual-code';
      },
      saveCandidate: (key) async {
        adapter.key = key;
      },
    );
    expect(errors, [null, '验证码错误，请重试', null]);
    expect(adapter.authCaptchaRequests, 2);
    expect(adapter.passwordForms.map((f) => f['execution']), ['e1s1', 'e1s2']);
  });

  test('registration recheck distinguishes captcha and password rejection', () async {
    final adapter = _School()..recheckCodes.addAll(['2106010003', '0']);
    final client = IdsClient(http: Dio()..httpClientAdapter = adapter);
    final errors = <String?>[];
    await client.register(
      '20240001',
      'synthetic-password',
      promptCaptcha: (_, error, {required refresh}) async {
        errors.add(error);
        return 'manual-code';
      },
      saveCandidate: (key) async {
        adapter.key = key;
      },
    );
    expect(errors, [null, '验证码错误，请重试']);
    adapter.recheckCodes.add('2106040000');
    await expectLater(
      client.register(
        '20240001',
        'synthetic-password',
        promptCaptcha: (_, __, {required refresh}) async => 'manual-code',
        saveCandidate: (_) async {},
      ),
      throwsA(isA<IdsException>().having((e) => e.message, 'message', contains('密码错误'))),
    );
  });

  test('registers with manual recheck captcha, then logs in from independent cookie jars',
      () async {
    final adapter = _School();
    final client = IdsClient(http: Dio()..httpClientAdapter = adapter);
    var prompts = 0;
    final binding = await client.register(
      '20240001',
      'synthetic-password',
      promptCaptcha: (image, error, {required refresh}) async {
        prompts++;
        expect(image, isNotEmpty);
        return 'manual-code';
      },
      saveCandidate: (key) async {
        adapter.key = key;
      },
    );
    expect(prompts, 1);
    expect(adapter.finishedRegistration, true);
    expect(adapter.registeredDeviceName, matches(r'^Techpie-[a-zA-Z0-9]{6}$'));
    expect(binding.session.username, '20240001');
    expect(binding.session.name, 'IDS Profile Name');
    final second = await client.login(binding.credential, backedUp: true);
    expect(second.raw['tgc'], isNot(binding.session.raw['tgc']));
    expect(adapter.assertionCounters, [0, 0]);
    expect(adapter.assertionFlags, [0x09, 0x19]);
    expect(adapter.emptyLoginStarts, 3);
    expect(jsonEncode(second.raw), isNot(contains('synthetic-password')));
    expect(jsonEncode(second.raw), isNot(contains(binding.credential.privateKey)));
  });

  test('regenerates colliding names before registering a single Passkey', () async {
    final adapter = _School()
      ..deviceNames.addAll(['Techpie-aaaaaa', 'Techpie-bbbbbb', 'Other device']);
    final client = IdsClient(http: Dio()..httpClientAdapter = adapter, nameRandom: _NameRandom());
    var candidates = 0;
    await client.register(
      '20240001',
      'synthetic-password',
      promptCaptcha: (_, __, {required refresh}) async => 'manual-code',
      saveCandidate: (key) async {
        candidates++;
        adapter.key = key;
      },
    );
    expect(adapter.registeredDeviceName, 'Techpie-cccccc');
    expect(candidates, 1);
    expect(adapter.registrations, 1);
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/queryAllDevices')), hasLength(1));
  });

  test('does not start registration when existing device names cannot be read', () async {
    final adapter = _School()..deviceQueryCode = 'error';
    final client = IdsClient(http: Dio()..httpClientAdapter = adapter);
    var savedCandidate = false;
    await expectLater(
      client.register(
        '20240001',
        'synthetic-password',
        promptCaptcha: (_, __, {required refresh}) async => 'manual-code',
        saveCandidate: (_) async {
          savedCandidate = true;
        },
      ),
      throwsA(isA<IdsException>().having((e) => e.message, 'message', contains('无法读取 IDS'))),
    );
    expect(savedCandidate, false);
    expect(adapter.requests.any((r) => r.uri.path.endsWith('/startRegister')), false);
    expect(adapter.registrations, 0);
  });

  test('remote unbind rechecks manually and deletes only this credential device ID', () async {
    final adapter = _School();
    final client = IdsClient(http: Dio()..httpClientAdapter = adapter);
    final registered = await client.register(
      '20240001',
      'synthetic-password',
      promptCaptcha: (_, __, {required refresh}) async => 'manual-code',
      saveCandidate: (key) async {
        adapter.key = key;
      },
    );
    adapter.extraDevices.add({
      'id': 'other-device',
      'userId': 'opaque-owner-id',
      'deviceName': adapter.registeredDeviceName,
    });
    adapter.recheckCodes.addAll(['2106040000', '2106010003', '0']);
    final errors = <String?>[];
    await client.revoke(
      registered.credential,
      promptVerification: (image, error, {required refresh}) async {
        expect(image, isNotEmpty);
        errors.add(error);
        return (password: 'synthetic-password', captcha: 'manual-code');
      },
    );
    expect(errors, [null, '密码错误，请重试', '验证码错误，请重试']);
    expect(adapter.deleteCalls, 1);
    expect(adapter.deletedId, registered.credential.anonBiometricsId);
    expect(adapter.extraDevices.single['id'], 'other-device');
  });

  test('cancelled school verification does not submit a delete request', () async {
    final adapter = _School();
    final client = IdsClient(http: Dio()..httpClientAdapter = adapter);
    final registered = await client.register(
      '20240001',
      'synthetic-password',
      promptCaptcha: (_, __, {required refresh}) async => 'manual-code',
      saveCandidate: (key) async {
        adapter.key = key;
      },
    );
    await expectLater(
      client.revoke(
        registered.credential,
        promptVerification: (_, __, {required refresh}) async => null,
      ),
      throwsA(isA<IdsException>()),
    );
    expect(adapter.deleteCalls, 0);
  });

  test('school delete errors are reported without selecting another device', () async {
    final adapter = _School()..deleteCode = 'error';
    final client = IdsClient(http: Dio()..httpClientAdapter = adapter);
    final registered = await client.register(
      '20240001',
      'synthetic-password',
      promptCaptcha: (_, __, {required refresh}) async => 'manual-code',
      saveCandidate: (key) async {
        adapter.key = key;
      },
    );
    await expectLater(
      client.revoke(
        registered.credential,
        promptVerification: (_, __, {required refresh}) async =>
            (password: 'synthetic-password', captcha: 'manual-code'),
      ),
      throwsA(isA<IdsException>()),
    );
    expect(adapter.deleteCalls, 1);
  });

  test('mints all four downstream cookies locally and scopes cookies per host/path', () async {
    final adapter = _School();
    final client = IdsClient(http: Dio()..httpClientAdapter = adapter);
    final bound = await client.register(
      '20240001',
      'synthetic-password',
      promptCaptcha: (_, __, {required refresh}) async => 'manual-code',
      saveCandidate: (key) async {
        adapter.key = key;
      },
    );
    final expected = {
      'eams': 'JSESSIONID=eams-local',
      'elearning': 'session_id=bb-local',
      'egateApp': 'MOD_AUTH_CAS=egate-local',
      'oa': 'shkjdx_session=oa-local',
    };
    for (final entry in expected.entries) {
      expect(await client.mintCookie(entry.key, bound.session.raw), contains(entry.value));
    }
    expect(adapter.primedEams, true);
    expect(adapter.submittedBlackboardForm, true);
    expect(adapter.requests.every((r) => CampusHttp.hosts.contains(r.uri.host)), true);
    for (final request in adapter.requests.where((r) => r.uri.host != IdsPasskey.rpId)) {
      expect(_cookie(request), isNot(contains('CASTGC=')));
      expect(_cookie(request), isNot(contains('REFERERCE_TOKEN=')));
    }
  });

  test('restoring a cookie jar retains host-only, path and expired-cookie semantics', () async {
    final dio = Dio()..httpClientAdapter = _CookieResponse();
    final first = CampusHttp(dio);
    await first.request(Uri.parse('${SoftwarePasskey.origin}/authserver/login'));
    final restored = CampusHttp(dio);
    await restored.restore(first.snapshot);
    expect(
      await restored.cookieHeader(Uri.parse('${SoftwarePasskey.origin}/authserver/login')),
      'CASTGC=scoped',
    );
    expect(
      await restored.cookieHeader(Uri.parse('${SoftwarePasskey.origin}/personalInfo/')),
      isEmpty,
    );
    expect(
      await restored.cookieHeader(Uri.parse('https://eams.shanghaitech.edu.cn/eams/')),
      isEmpty,
    );
  });
}

String _cookie(RequestOptions request) =>
    (request.headers['Cookie'] ?? request.headers['cookie'] ?? '').toString();

class _NameRandom implements Random {
  int _calls = 0;
  @override
  int nextInt(int max) => (_calls++ ~/ 6) % max;
  @override
  bool nextBool() => throw UnsupportedError('unused');
  @override
  double nextDouble() => throw UnsupportedError('unused');
}

class _CookieResponse implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        'ok',
        200,
        headers: {
          'set-cookie': [
            'CASTGC=scoped; Path=/authserver; Secure; HttpOnly',
            'expired=gone; Path=/; Max-Age=0',
          ],
        },
      );
  @override
  void close({bool force = false}) {}
}

class _School implements HttpClientAdapter {
  IdsPasskey? key;
  final deviceNames = <String>{};
  String deviceQueryCode = '0';
  String? registeredDeviceName;
  int registrations = 0;
  final extraDevices = <Map<String, dynamic>>[];
  final recheckCodes = <String>[];
  final passwordErrors = <String>[];
  final passwordForms = <Map<String, String>>[];
  bool forceLoginCaptcha = false;
  int passwordFailures = 0;
  int authCaptchaRequests = 0;
  String deleteCode = '0';
  int deleteCalls = 0;
  String? deletedId;
  final requests = <RequestOptions>[];
  final assertionCounters = <int>[];
  final assertionFlags = <int>[];
  var finishedRegistration = false;
  var emptyLoginStarts = 0;
  var primedEams = false;
  var submittedBlackboardForm = false;
  var _sessions = 0;
  var _challenge = 0;
  @override
  void close({bool force = false}) {}

  ResponseBody _json(
    Map<String, dynamic> object, {
    List<String> cookies = const [],
    int status = 200,
  }) =>
      ResponseBody.fromString(
        jsonEncode(object),
        status,
        headers: {
          'content-type': ['application/json'],
          if (cookies.isNotEmpty) 'set-cookie': cookies,
        },
      );
  ResponseBody _redirect(String target) => ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': [target],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path;
    if (options.uri.host != IdsPasskey.rpId) {
      if (path == '/eams/home.action' && _cookie(options).contains('JSESSIONID=eams-local')) {
        primedEams = true;
        return ResponseBody.fromString('home', 200);
      }
      if (path == '/eams/home.action' || path.endsWith('/dqnxxqgrhz.do')) {
        return _redirect(
          '${SoftwarePasskey.origin}/authserver/login?service=${Uri.encodeQueryComponent('${options.uri.origin}/session')}',
        );
      }
      if (path == '/session') {
        final cookie = switch (options.uri.host) {
          'eams.shanghaitech.edu.cn' => 'JSESSIONID=eams-local; Path=/eams; Secure',
          'egate.shanghaitech.edu.cn' => 'MOD_AUTH_CAS=egate-local; Path=/xsfw; Secure',
          'oa.shanghaitech.edu.cn' => 'shkjdx_session=oa-local; Path=/; Secure',
          _ => '',
        };
        return ResponseBody.fromString(
          'authenticated',
          options.uri.host.startsWith('eams') ? 302 : 200,
          headers: {
            'set-cookie': [cookie],
            if (options.uri.host.startsWith('eams')) 'location': ['/eams/home.action'],
          },
        );
      }
      if (options.uri.host == 'elearning.shanghaitech.edu.cn') {
        if (path == '/sso') {
          return ResponseBody.fromString(
            '<form><input name="token" value="synthetic&amp;token"></form>',
            200,
          );
        }
        if (path.endsWith('/customLogin')) {
          expect(Uri.splitQueryString(options.data as String)['token'], 'synthetic&token');
          submittedBlackboardForm = true;
          return ResponseBody.fromString(
            'ok',
            200,
            headers: {
              'set-cookie': ['session_id=bb-local; Path=/; Secure'],
            },
          );
        }
        if (path.endsWith('/index.jsp')) return ResponseBody.fromString('portal', 200);
      }
      throw StateError('Unexpected downstream fixture request: $path');
    }
    if (path == '/authserver/login' && options.method == 'GET') {
      final service = options.uri.queryParameters['service'];
      if (service != null) {
        expect(_cookie(options), contains('CASTGC='));
        final target = Uri.parse(service);
        return _redirect(
          '${target.origin}/${target.host.startsWith('elearning') ? 'sso' : 'session'}',
        );
      }
      expect(_cookie(options), isEmpty);
      emptyLoginStarts++;
      return ResponseBody.fromString(
        '<input name="execution" value="e1s1"><input name="pwdEncryptSalt" value="0123456789abcdef">',
        200,
      );
    }
    if (path == '/authserver/checkNeedCaptcha.htl') {
      return _json({'isNeed': forceLoginCaptcha || passwordFailures >= 2});
    }
    if (path == '/authserver/getCaptcha.htl') {
      authCaptchaRequests++;
      return ResponseBody.fromBytes([137, 80, 78, 71], 200);
    }
    if (path == '/authserver/login' && options.method == 'POST') {
      final form = Uri.splitQueryString(options.data as String);
      if (form['cllt'] == 'fidoLogin') {
        final wire = jsonDecode(form['responseJson']!) as Map;
        final response = wire['credential']['response'] as Map;
        final auth = SoftwarePasskey.decode(response['authenticatorData'] as String);
        assertionCounters.add(ByteData.sublistView(auth).getUint32(33));
        assertionFlags.add(auth[32]);
      } else {
        expect(form['password'], isNot('synthetic-password'));
        passwordForms.add(form);
        if (passwordErrors.isNotEmpty) {
          final error = passwordErrors.removeAt(0);
          if (error != '验证码错误') passwordFailures++;
          return ResponseBody.fromString(
            '<span id="showErrorTip">$error</span>'
            '<input name="execution" value="e1s${passwordForms.length + 1}">'
            '<input name="pwdEncryptSalt" value="0123456789abcdef">',
            401,
          );
        }
      }
      return _json(
        {
          'ok': true,
        },
        cookies: [
          'CASTGC=session-${++_sessions}; Path=/authserver; Secure; HttpOnly',
          'WIS_PER_ENC=0123456789abcdef; Path=/personalInfo; Secure',
          'REFERERCE_TOKEN=ref; Path=/personalInfo; Secure',
        ],
      );
    }
    if (path == '/personalInfo/common/getUserConf') {
      return _json({
        'code': '0',
        'datas': {'uid': '20240001', 'cn': 'IDS Profile Name'},
      });
    }
    if (path == '/personalInfo/common/isUserRecheckNecessary') return _json({'code': '2106010001'});
    if (path == '/personalInfo/common/recheckApproach') {
      return _json({
        'code': '0',
        'datas': {'approachName': 'password'},
      });
    }
    if (path == '/personalInfo/captcha/checkCode') {
      return ResponseBody.fromString('synthetic-image', 200);
    }
    if (path == '/personalInfo/common/recheckUserInfo') {
      expect(_cookie(options), contains('WIS_PER_ENC='));
      final body = jsonDecode(options.data as String) as Map;
      expect(body['captcha'], 'manual-code');
      expect(options.headers['refererToken'], 'ref');
      expect(body['password'], isNot('synthetic-password'));
      final code = recheckCodes.isEmpty ? '0' : recheckCodes.removeAt(0);
      // Captured from IDS: a bad captcha is a business failure over HTTP 500;
      // a bad password is HTTP 200 with code 2106040000.
      return _json({'code': code}, status: code == '2106010003' ? 500 : 200);
    }
    if (path == '/personalInfo/accountSecurity/queryAllDevices') {
      expect(options.method, 'POST');
      expect(options.headers['refererToken'], 'ref');
      final body = jsonDecode(options.data as String) as Map;
      expect(body['pageNumber'], 1);
      expect(body['pageSize'], 1000);
      expect(body['n'], isA<String>());
      return _json({
        'code': deviceQueryCode,
        'datas': [
          for (final name in deviceNames)
            {
              'deviceName': name,
              'id': key?.anonBiometricsId ?? 'existing-$name',
              'userId': 'opaque-owner-id',
            },
          ...extraDevices,
        ],
      });
    }
    if (path == '/personalInfo/accountSecurity/deleteDevice') {
      final body = jsonDecode(options.data as String) as Map;
      expect(body['id'], key!.anonBiometricsId);
      expect(body['response'], 'opaque-owner-id');
      expect(options.headers['refererToken'], 'ref');
      deleteCalls++;
      if (deleteCode == '0') deletedId = body['id'] as String;
      return _json({'code': deleteCode});
    }
    if (path == '/personalInfo/accountSecurity/startRegister') {
      expect(requests.any((r) => r.uri.path.endsWith('/queryAllDevices')), true);
      return _json({
        'code': '0',
        'datas': {
          'request': {
            'requestId': 'registration-request',
            'publicKeyCredentialCreationOptions': {
              'challenge': SoftwarePasskey.encode(List.filled(32, 7)),
              'rp': {'id': IdsPasskey.rpId},
              'user': {'id': 'c3R1ZGVudA', 'name': '20240001'},
              'pubKeyCredParams': [
                {'alg': -7},
              ],
            },
          },
        },
      });
    }
    if (path == '/personalInfo/accountSecurity/finishRegister') {
      expect(key, isNotNull, reason: 'candidate saved before submitting to IDS');
      final body = jsonDecode(options.data as String) as Map;
      final name = body['deviceName'] as String;
      expect(name, matches(r'^Techpie-[a-zA-Z0-9]{6}$'));
      expect(deviceNames.contains(name), false);
      deviceNames.add(name);
      registeredDeviceName = name;
      registrations++;
      expect(body['anonbiometricsd'], key!.anonBiometricsId);
      expect((jsonDecode(body['response'] as String) as Map)['requestId'], 'registration-request');
      expect(options.data, isNot(contains(key!.privateKey)));
      finishedRegistration = true;
      return _json({'code': '0'});
    }
    if (path == '/authserver/startAssertion') {
      return _json({
        'result': {
          'request': {
            'requestId': 'assertion-${++_challenge}',
            'publicKeyCredentialRequestOptions': {
              'challenge': SoftwarePasskey.encode(List.filled(32, _challenge)),
              'rpId': IdsPasskey.rpId,
              'allowCredentials': [
                {'id': key!.credentialId},
              ],
            },
          },
        },
      });
    }
    throw StateError('Unexpected IDS fixture request: $path');
  }
}
