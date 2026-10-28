// Adapted from GenAI2OpenAI's CAS login. See third_party/GenAI2OpenAI/LICENSE.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class GenaiLogin {
  GenaiLogin({HttpClient Function()? clientFactory, Uri? genaiBase, Uri? idsBase})
      : _clientFactory = clientFactory ?? HttpClient.new,
        _genaiBase = genaiBase ?? Uri.parse('https://genai.shanghaitech.edu.cn'),
        _idsBase = idsBase ?? Uri.parse('https://ids.shanghaitech.edu.cn');

  final HttpClient Function() _clientFactory;
  final Uri _genaiBase;
  final Uri _idsBase;

  static String encryptPassword(String password, String salt) {
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters(
          ParametersWithIV(
            KeyParameter(Uint8List.fromList(utf8.encode(salt))),
            Uint8List.fromList(utf8.encode('Nu1LNu1LNu1LNu1L')),
          ),
          null,
        ),
      );
    return base64Encode(
      cipher.process(Uint8List.fromList(utf8.encode('${List.filled(16, 'Nu1L').join()}$password'))),
    );
  }

  static String field(String html, String name) {
    final input = RegExp(r'<input\b[^>]*>', caseSensitive: false)
        .allMatches(html)
        .map((m) => m.group(0)!)
        .where(
          (tag) => RegExp('(?:name|id)=["\u0027]${RegExp.escape(name)}["\u0027]').hasMatch(tag),
        );
    if (input.isEmpty) return '';
    return RegExp('value=["\u0027]([^"\u0027]*)["\u0027]').firstMatch(input.first)?.group(1) ?? '';
  }

  Future<String> login(String account, String password) async {
    final client = _clientFactory()..connectionTimeout = const Duration(seconds: 15);
    final cookies = <String, Map<String, Cookie>>{};
    Future<({HttpClientResponse response, String body})> request(Uri uri, {String? form}) async {
      final req = await client.openUrl(form == null ? 'GET' : 'POST', uri);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 TechPie');
      req.cookies.addAll(cookies[uri.host]?.values ?? <Cookie>[]);
      if (form != null) {
        req.headers.contentType =
            ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
        req.write(form);
      }
      final res = await req.close().timeout(const Duration(seconds: 30));
      for (final cookie in res.cookies) {
        (cookies[uri.host] ??= {})[cookie.name] = cookie;
      }
      return (
        response: res,
        body: await utf8.decoder.bind(res).join().timeout(const Duration(seconds: 30))
      );
    }

    try {
      var uri = _genaiBase.resolve('/htk/user/login');
      var result = await request(uri);
      for (var i = 0; i < 12; i++) {
        final token = uri.queryParameters['token'];
        if (token != null && token.isNotEmpty) return token;
        final location = result.response.headers.value(HttpHeaders.locationHeader);
        if (result.response.statusCode >= 300 &&
            result.response.statusCode < 400 &&
            location != null) {
          uri = uri.resolve(location);
          final redirectedToken = uri.queryParameters['token'];
          if (redirectedToken != null && redirectedToken.isNotEmpty) return redirectedToken;
          result = await request(uri);
          continue;
        }
        final salt = field(result.body, 'pwdEncryptSalt');
        final execution = field(result.body, 'execution');
        if (salt.isNotEmpty && execution.isNotEmpty) {
          final form = Uri(
            queryParameters: {
              'username': account.trim(),
              'password': encryptPassword(password, salt),
              'lt': field(result.body, 'lt'),
              'dllt': 'generalLogin',
              'execution': execution,
              '_eventId': 'submit',
              'rmShown': '1',
            },
          ).query;
          result = await request(uri, form: form);
          if (result.response.statusCode < 300 || result.response.statusCode >= 400) {
            if (result.body.contains('captcha') || result.body.contains('验证码')) {
              throw const FormatException('请在网页登录后重试');
            }
            throw const FormatException('学号或密码不对');
          }
          continue;
        }
        final service = RegExp(r'var service = \["(.*?)"').firstMatch(result.body)?.group(1);
        if (service == null) throw const FormatException('登录失败，请重试');
        uri = _idsBase.resolve('/authserver/login?service=$service');
        result = await request(uri);
      }
      throw const FormatException('登录失败，请重试');
    } finally {
      client.close(force: true);
    }
  }
}
