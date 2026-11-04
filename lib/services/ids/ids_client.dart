// Protocol port from Geekpie Auth Portal; see licenses/shanghaitech-ids-passkey.txt.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:pointycastle/export.dart';

import '../../models/ids_passkey.dart';
import 'campus_http.dart';
import 'software_passkey.dart';

export 'campus_http.dart' show IdsException;

typedef IdsCaptchaRefresh = Future<Uint8List> Function();
typedef IdsCaptchaPrompt = Future<String?> Function(
  Uint8List image,
  String? error, {
  required IdsCaptchaRefresh refresh,
});
typedef IdsVerificationAnswer = ({String password, String captcha});
typedef IdsVerificationPrompt = Future<IdsVerificationAnswer?> Function(
  Uint8List image,
  String? error, {
  required IdsCaptchaRefresh refresh,
});

enum _PasswordFailure { password, captcha, locked, unknown }

// Same known IDS error messages as the Auth Portal; never display raw HTML.
const _passwordMessages = {
  'accountlogin_account_pwd_error': _PasswordFailure.password,
  '该账号非常用账号或用户名密码有误': _PasswordFailure.password,
  '用户名或密码错误': _PasswordFailure.password,
  '账号或密码错误': _PasswordFailure.password,
  '您提供的用户名或者密码有误': _PasswordFailure.password,
  'invalid username or password': _PasswordFailure.password,
  'incorrect username or password': _PasswordFailure.password,
  '验证码错误': _PasswordFailure.captcha,
  '验证码不正确': _PasswordFailure.captcha,
  '验证码不能为空': _PasswordFailure.captcha,
  'verification code error': _PasswordFailure.captcha,
  'invalid captcha': _PasswordFailure.captcha,
  '账号已锁定': _PasswordFailure.locked,
  '账户已锁定': _PasswordFailure.locked,
  '账号被锁定': _PasswordFailure.locked,
  'account locked': _PasswordFailure.locked,
  'account is locked': _PasswordFailure.locked,
};

class IdsSession {
  final String username;
  final Map<String, dynamic> raw;
  final String? name;
  const IdsSession(this.username, this.raw, {this.name});
}

class IdsClient {
  IdsClient({Dio? http, Random? nameRandom})
      : _http = http ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
              ),
            ),
        _nameRandom = nameRandom ?? Random.secure();
  final Dio _http;
  final Random _nameRandom;
  static final _login = Uri.parse('${SoftwarePasskey.origin}/authserver/login');

  Map<String, String> _fields(String html) {
    final document = parse(html);
    final result = <String, String>{};
    for (final name in ['execution', 'lt', 'pwdEncryptSalt']) {
      result[name] = document.querySelector('[name="$name"],#$name')?.attributes['value'] ?? '';
    }
    if (result['execution']!.isEmpty) throw const IdsException('IDS 登录页面已变化或要求修改密码，请先到学校网站处理');
    return result;
  }

  String _encryptPassword(String password, String salt) {
    if (utf8.encode(salt).length != 16) throw const IdsException('IDS 密码加密参数无效');
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters(
          ParametersWithIV(
            KeyParameter(Uint8List.fromList(utf8.encode(salt))),
            Uint8List.fromList(utf8.encode('Nu1L' * 4)),
          ),
          null,
        ),
      );
    return base64.encode(
      cipher.process(
        Uint8List.fromList(
          utf8.encode('${base64.encode(SoftwarePasskey.randomBytes(48))}$password'),
        ),
      ),
    );
  }

  Future<String> _captcha(
    CampusHttp client,
    String path,
    IdsCaptchaPrompt prompt, {
    String? error,
  }) async {
    final refresh = _captchaLoader(client, path);
    final answer = await prompt(await refresh(), error, refresh: refresh);
    if (answer == null) throw const IdsException('已取消绑定');
    return answer.trim();
  }

  IdsCaptchaRefresh _captchaLoader(CampusHttp client, String path) => () async {
        final base = Uri.parse('${SoftwarePasskey.origin}$path');
        final nonce = '${DateTime.now().millisecondsSinceEpoch}';
        final uri =
            base.replace(query: base.path.startsWith('/personalInfo/') ? 'data=$nonce' : nonce);
        final response = await client.request(uri);
        return Uint8List.fromList(response.data ?? []);
      };

  _PasswordFailure _passwordFailure(String html) {
    final document = parse(html);
    for (final node in document.querySelectorAll('script,style,input,textarea,template,noscript')) {
      node.remove();
    }
    final failures = <_PasswordFailure>{};
    for (final node in document
        .querySelectorAll('#showErrorTip,#formErrorTip,#msg,.errors,.login-error,[role=alert]')) {
      final message = node.text.trim().replaceAll(RegExp(r'[。.!！]$'), '').toLowerCase();
      final failure = _passwordMessages[message];
      if (failure != null) failures.add(failure);
    }
    return failures.length == 1 ? failures.single : _PasswordFailure.unknown;
  }

  Future<List<dynamic>> _devices(CampusHttp client) async {
    final response = await client.object('/personalInfo/accountSecurity/queryAllDevices', {
      'pageNumber': 1,
      'pageSize': 1000,
    });
    final devices = response['datas'];
    if (response['code'].toString() != '0' || devices is! List) {
      throw const IdsException('无法读取 IDS 已绑定的 Passkey 名称，请重试');
    }
    return devices;
  }

  Future<String> _newDeviceName(CampusHttp client) async {
    final devices = await _devices(client);
    final existing = {for (final device in devices) device['deviceName'] as String};
    const characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    String name;
    do {
      final suffix =
          List.generate(6, (_) => characters[_nameRandom.nextInt(characters.length)]).join();
      name = 'Techpie-$suffix';
    } while (existing.contains(name));
    return name;
  }

  Future<void> revoke(IdsPasskey key, {required IdsVerificationPrompt promptVerification}) async {
    final session = await login(key);
    final client = CampusHttp(_http);
    await client.restore(session.raw['cookieJar'] as List);
    final devices = await _devices(client);
    // IDS's device ID is the anonbiometricsd registered alongside this key.
    // Never select a device by its name or delete another credential.
    final device = devices.where((d) => d['id'] == key.anonBiometricsId).firstOrNull;
    if (device == null) return;
    final ownerId = device['userId'];
    if (ownerId is! String || ownerId.isEmpty) throw const IdsException('IDS 未返回此 Passkey 的解绑信息');
    final recheck = await client.object(
      '/personalInfo/common/isUserRecheckNecessary?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    if (recheck['code'].toString() != '0') {
      final approach = await client.object('/personalInfo/common/recheckApproach', {});
      if (!((approach['datas'] as Map?)?['approachName']?.toString().split(',') ?? [])
          .contains('password')) {
        throw const IdsException('请在 IDS 账号安全页面完成额外验证后解绑');
      }
      String? error;
      final refresh = _captchaLoader(client, '/personalInfo/captcha/checkCode');
      while (true) {
        final answer = await promptVerification(await refresh(), error, refresh: refresh);
        if (answer == null) throw const IdsException('已取消 IDS 验证，本地绑定已删除');
        final salt = await client.cookie(
          Uri.parse('${SoftwarePasskey.origin}/personalInfo/'),
          'WIS_PER_ENC',
        );
        if (salt == null) throw const IdsException('IDS 二次验证会话已失效');
        final checked = await client.object('/personalInfo/common/recheckUserInfo', {
          'reauthType': 'password',
          'password': _encryptPassword(answer.password, salt),
          'captcha': answer.captcha,
        });
        final code = checked['code'].toString();
        if (code == '0') break;
        if (code != '2106010003' && code != '2106040000') throw const IdsException('IDS 二次验证失败');
        error = code == '2106040000' ? '密码错误，请重试' : '验证码错误，请重试';
      }
    }
    // Same payload as the IDS account-security device management page.
    final removed = await client.object('/personalInfo/accountSecurity/deleteDevice', {
      'id': key.anonBiometricsId,
      'response': ownerId,
    });
    if (removed['code'].toString() != '0') throw const IdsException('IDS 未接受解绑，请在账号安全页面手动删除');
  }

  Future<({IdsPasskey credential, IdsSession session})> register(
    String username,
    String password, {
    required IdsCaptchaPrompt promptCaptcha,
    required Future<void> Function(IdsPasskey credential) saveCandidate,
  }) async {
    final client = CampusHttp(_http);
    var fields = _fields(CampusHttp.text(await client.request(_login)));
    final needed = await client
        .object('/authserver/checkNeedCaptcha.htl?username=${Uri.encodeQueryComponent(username)}');
    var needsCaptcha = needed['isNeed'] == true;
    String? captchaError;
    while (true) {
      final captcha = needsCaptcha
          ? await _captcha(
              client,
              '/authserver/getCaptcha.htl?${DateTime.now().millisecondsSinceEpoch}',
              promptCaptcha,
              error: captchaError,
            )
          : '';
      final response = await client.request(
        _login,
        method: 'POST',
        // A rejected password/captcha returns a login HTML page with HTTP 401.
        allowErrorResponse: true,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        data: Uri(
          queryParameters: {
            'username': username,
            'password': _encryptPassword(password, fields['pwdEncryptSalt']!),
            'captcha': captcha,
            'execution': fields['execution']!,
            'lt': fields['lt']!,
            '_eventId': 'submit',
            'cllt': 'userNameLogin',
            'dllt': 'generalLogin',
          },
        ).query,
      );
      if (await client.cookie(_login, 'CASTGC') != null) break;
      final html = CampusHttp.text(response);
      final failure = _passwordFailure(html);
      if (failure == _PasswordFailure.captcha) {
        fields = _fields(html);
        needsCaptcha = true;
        captchaError = '验证码错误，请重试';
        continue;
      }
      throw IdsException(
        switch (failure) {
          _PasswordFailure.password => 'IDS 账号或密码错误，请重新输入',
          _PasswordFailure.locked => 'IDS 账号已锁定，请在学校 IDS 处理后重试',
          _ => 'IDS 登录失败，请检查学校账号状态后重试',
        },
      );
    }
    final profile = await client.object('/personalInfo/common/getUserConf', {});
    final canonical = (profile['datas'] as Map?)?['uid'] as String?;
    if (profile['code'].toString() != '0' || canonical == null || canonical.isEmpty) {
      throw const IdsException('无法确认 IDS 账号身份');
    }
    final recheck = await client.object(
      '/personalInfo/common/isUserRecheckNecessary?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    if (recheck['code'].toString() != '0') {
      final approach = await client.object('/personalInfo/common/recheckApproach', {});
      if (!((approach['datas'] as Map?)?['approachName']?.toString().split(',') ?? [])
          .contains('password')) {
        throw const IdsException('IDS 要求额外身份验证，请先在学校账号安全页面处理');
      }
      String? captchaError;
      while (true) {
        final code = await _captcha(
          client,
          '/personalInfo/captcha/checkCode?data=${DateTime.now().millisecondsSinceEpoch}',
          promptCaptcha,
          error: captchaError,
        );
        final salt = await client.cookie(
          Uri.parse('${SoftwarePasskey.origin}/personalInfo/'),
          'WIS_PER_ENC',
        );
        if (salt == null) throw const IdsException('IDS 二次验证会话已失效，请重试');
        final checked = await client.object('/personalInfo/common/recheckUserInfo', {
          'reauthType': 'password',
          'password': _encryptPassword(password, salt),
          'captcha': code,
        });
        if (checked['code'].toString() == '0') break;
        if (checked['code'].toString() == '2106040000') {
          throw const IdsException('IDS 密码错误，请重新输入');
        }
        if (checked['code'].toString() != '2106010003') {
          throw const IdsException('IDS 二次验证失败，请检查密码后重试');
        }
        captchaError = '验证码错误，请重试';
      }
    }
    final deviceName = await _newDeviceName(client);
    final started = await client.object('/personalInfo/accountSecurity/startRegister', {});
    final request = ((started['datas'] as Map?)?['request'] as Map?)?.cast<String, dynamic>();
    if (request?['requestId'] == null || request?['publicKeyCredentialCreationOptions'] == null) {
      throw const IdsException('IDS 无法开始 Passkey 注册');
    }
    final candidate = SoftwarePasskey.registration(
      (request!['publicKeyCredentialCreationOptions'] as Map).cast<String, dynamic>(),
      canonical,
    );
    // Retain the candidate locally before submitting its public key. A lost
    // finishRegister response can then be recovered by logging in with it.
    await saveCandidate(candidate.secret);
    final finished = await client.object('/personalInfo/accountSecurity/finishRegister', {
      'deviceName': deviceName,
      'anonbiometricsd': candidate.secret.anonBiometricsId,
      'response': jsonEncode({
        'requestId': request['requestId'],
        'credential': candidate.credential,
        'sessionToken': null,
      }),
    });
    if (finished['code'].toString() != '0') throw const IdsException('IDS 未接受 Passkey 注册');
    return (credential: candidate.secret, session: await login(candidate.secret));
  }

  Future<IdsSession> login(IdsPasskey secret, {bool backedUp = false}) async {
    final client = CampusHttp(_http);
    final fields = _fields(CampusHttp.text(await client.request(_login)));
    final started = await client.object(
      '/authserver/startAssertion',
      {'userId': base64.encode(utf8.encode(secret.username)), 'id': secret.anonBiometricsId},
    );
    final request = ((started['result'] as Map?)?['request'] as Map?)?.cast<String, dynamic>();
    if (request?['requestId'] == null || request?['publicKeyCredentialRequestOptions'] == null) {
      throw const IdsException('IDS Passkey 已被解绑或不可用，请在 TechPie 重新绑定', credentialRejected: true);
    }
    final credential = SoftwarePasskey.authentication(
      (request!['publicKeyCredentialRequestOptions'] as Map).cast<String, dynamic>(),
      secret,
      backedUp: backedUp,
    );
    await client.request(
      _login,
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      data: Uri(
        queryParameters: {
          '_eventId': 'submit',
          'responseJson': jsonEncode(
            {'requestId': request['requestId'], 'credential': credential, 'sessionToken': null},
          ),
          'username': base64.encode(utf8.encode(secret.username)),
          'cllt': 'fidoLogin',
          'dllt': 'generalLogin',
          'lt': '',
          'execution': fields['execution']!,
        },
      ).query,
    );
    final tgc = await client.cookie(_login, 'CASTGC');
    if (tgc == null) throw const IdsException('IDS Passkey 登录失败，请重新绑定', credentialRejected: true);
    final profile = await client.object('/personalInfo/common/getUserConf', {});
    if (profile['code'].toString() != '0' ||
        (profile['datas'] as Map?)?['uid'] != secret.username) {
      throw const IdsException('IDS 登录身份不匹配', credentialRejected: true);
    }
    final name = (profile['datas'] as Map?)?['cn'] as String?;
    return IdsSession(
      secret.username,
      {'tgc': tgc, 'cookies': await client.cookieHeader(_login), 'cookieJar': client.snapshot},
      name: name?.trim().isNotEmpty == true ? name!.trim() : null,
    );
  }

  Future<String> mintCookie(String nodeId, Map<String, dynamic> root) async {
    final client = CampusHttp(_http);
    await client.restore(
      (root['cookieJar'] as List?) ??
          [
            {
              'url': _login.toString(),
              'cookie': 'CASTGC=${root['tgc']}; Path=/authserver; Secure; HttpOnly',
            },
          ],
    );
    final entry = switch (nodeId) {
      'eams' => 'https://eams.shanghaitech.edu.cn/eams/home.action',
      'elearning' =>
        '${SoftwarePasskey.origin}/authserver/login?service=${Uri.encodeQueryComponent('https://elearning.shanghaitech.edu.cn:8443/webapps/bb-BB-BBLEARN/index.jsp')}',
      'egateApp' => 'https://egate.shanghaitech.edu.cn/xsfw/sys/xshdapp/xshdApply/dqnxxqgrhz.do',
      'oa' =>
        '${SoftwarePasskey.origin}/authserver/login?service=${Uri.encodeQueryComponent('https://oa.shanghaitech.edu.cn/workflow/request/AddRequest.jsp?workflowid=14862')}',
      _ => throw ArgumentError.value(nodeId),
    };
    final response = await client.request(Uri.parse(entry));
    final html = CampusHttp.text(response);
    if (parse(html).querySelector('[name="execution"]') != null) {
      throw const IdsException('IDS 登录态已失效', credentialRejected: true);
    }
    if (nodeId == 'elearning') {
      final fields = <String, String>{};
      for (final input in parse(html).querySelectorAll('input[name]')) {
        fields[input.attributes['name']!] = input.attributes['value'] ?? '';
      }
      if (fields.isEmpty) throw const IdsException('Blackboard 未返回 SSO 登录表单');
      await client.request(
        Uri.parse(
          'https://elearning.shanghaitech.edu.cn:8443/webapps/bb-sso-BBLEARN/execute/authValidate/customLogin',
        ),
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        data: Uri(queryParameters: fields).query,
      );
      await client.request(
        Uri.parse('https://elearning.shanghaitech.edu.cn:8443/webapps/bb-BB-BBLEARN/index.jsp'),
      );
    }
    final target = Uri.parse(
      switch (nodeId) {
        'eams' => 'https://eams.shanghaitech.edu.cn/eams/',
        'elearning' => 'https://elearning.shanghaitech.edu.cn:8443/webapps/',
        'egateApp' => 'https://egate.shanghaitech.edu.cn/xsfw/sys/xshdapp/xshdApply/dqnxxqgrhz.do',
        _ => 'https://oa.shanghaitech.edu.cn/',
      },
    );
    final required = switch (nodeId) {
      'eams' => 'JSESSIONID',
      'egateApp' => 'MOD_AUTH_CAS',
      'oa' => 'shkjdx_session',
      _ => 'session_id'
    };
    var cookies = await client.cookieHeader(target);
    if (nodeId == 'elearning' &&
        await client.cookie(target, 'session_id') == null &&
        await client.cookie(target, 's_session_id') == null) {
      final jsession = await client.cookie(target, 'JSESSIONID');
      if (jsession != null) cookies = '$cookies; session_id=$jsession';
    }
    if (!cookies.contains('$required=') &&
        !(nodeId == 'elearning' && cookies.contains('s_session_id='))) {
      throw const IdsException('未能建立学校业务系统会话');
    }
    return cookies;
  }
}
