import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

import '../campus_user_agent.dart';
import '../debug_logger.dart';

class IdsException implements Exception {
  final String message;
  final bool credentialRejected;
  const IdsException(this.message, {this.credentialRejected = false});
  @override
  String toString() => message;
}

/// App-owned HTTP session with host, path, expiry and Secure cookie scoping.
/// Authentication logs contain diagnostics only, never payloads or cookies.
class CampusHttp {
  CampusHttp(this.http, {DebugLogger? logger}) : _logger = logger;
  final Dio http;
  final DebugLogger? _logger;
  final CookieJar jar = CookieJar();
  final Map<String, Map<String, String>> _stored = {};
  static const hosts = {
    'ids.shanghaitech.edu.cn',
    'eams.shanghaitech.edu.cn',
    'elearning.shanghaitech.edu.cn',
    'egate.shanghaitech.edu.cn',
    'oa.shanghaitech.edu.cn',
  };

  List<Map<String, String>> get snapshot => _stored.values.toList();

  Future<void> restore(List<dynamic> records) async {
    for (final record in records) {
      final uri = Uri.parse(record['url'] as String);
      await _save(uri, [record['cookie'] as String]);
    }
  }

  Future<void> _save(Uri uri, List<String> values) async {
    for (final value in values) {
      Cookie cookie;
      try {
        cookie = Cookie.fromSetCookieValue(value);
      } on HttpException {
        continue;
      }
      final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '') ?? uri.host;
      if (uri.host != domain && !uri.host.endsWith('.$domain')) continue;
      if (cookie.path == null) {
        final slash = uri.path.lastIndexOf('/');
        cookie.path = slash <= 0 ? '/' : uri.path.substring(0, slash);
      }
      if (cookie.maxAge != null) {
        cookie.expires = DateTime.now().toUtc().add(Duration(seconds: cookie.maxAge!));
        cookie.maxAge = null;
      }
      final key = '${cookie.name}|$domain|${cookie.path ?? '/'}';
      _stored[key] = {
        'url': uri.replace(query: '', fragment: '').toString(),
        'cookie': cookie.toString(),
      };
      await jar.saveFromResponse(uri, [cookie]);
    }
  }

  Future<String> cookieHeader(Uri uri) async =>
      (await jar.loadForRequest(uri)).map((c) => '${c.name}=${c.value}').join('; ');
  Future<String?> cookie(Uri uri, String name) async {
    for (final value in await jar.loadForRequest(uri)) {
      if (value.name == name) return value.value;
    }
    return null;
  }

  Future<Response<List<int>>> request(
    Uri uri, {
    String method = 'GET',
    Object? data,
    Map<String, String>? headers,
    bool allowErrorResponse = false,
  }) async {
    for (var hop = 0; hop < 10; hop++) {
      if (uri.scheme != 'https' || !hosts.contains(uri.host) || uri.userInfo.isNotEmpty) {
        throw const IdsException('学校登录跳转到了不支持的地址');
      }
      Response<List<int>> response;
      // Query parameters can contain a username or CAS ticket. Request bodies,
      // headers and HTML can contain passwords, captcha or assertion material.
      final logUrl = '${uri.origin}${uri.path}';
      final timer = Stopwatch()..start();
      _logger?.log(method: method, url: logUrl, tag: 'IDS');
      try {
        response = await http.request<List<int>>(
          uri.toString(),
          data: data,
          options: Options(
            method: method,
            responseType: ResponseType.bytes,
            followRedirects: false,
            validateStatus: (_) => true,
            headers: {
              'User-Agent': CampusUserAgent.value,
              ...?headers,
              'Cookie': await cookieHeader(uri),
            },
          ),
        );
      } on DioException {
        _logger?.log(
          method: method,
          url: logUrl,
          error: '无法连接学校认证服务，请检查网络后重试',
          durationMicros: timer.elapsedMicroseconds,
          tag: 'IDS',
        );
        throw const IdsException('无法连接学校认证服务，请检查网络后重试');
      }
      if (_logger?.enabled == true) {
        _logger!.log(
          method: method,
          url: logUrl,
          statusCode: response.statusCode,
          responseBody: _responseCode(response),
          durationMicros: timer.elapsedMicroseconds,
          tag: 'IDS',
        );
      }
      await _save(uri, response.headers['set-cookie'] ?? []);
      final status = response.statusCode ?? 0;
      final location = response.headers.value('location');
      if ([301, 302, 303, 307, 308].contains(status) && location != null) {
        uri = uri.resolve(location);
        if (status == 303 || ((status == 301 || status == 302) && method == 'POST')) {
          method = 'GET';
          data = null;
          headers = null;
        }
        continue;
      }
      if (allowErrorResponse) return response;
      if (status >= 500) throw const IdsException('学校认证服务暂时不可用');
      if (status == 401 || status == 403) {
        throw const IdsException('学校登录态已失效，请重新绑定 IDS Passkey', credentialRejected: true);
      }
      if (status < 200 || status >= 400) throw const IdsException('学校认证请求失败');
      return response;
    }
    throw const IdsException('学校登录跳转次数过多');
  }

  static String text(Response<List<int>> response) =>
      utf8.decode(response.data ?? [], allowMalformed: true);

  String? _responseCode(Response<List<int>> response) {
    if (!(response.headers.value('content-type') ?? '').contains('application/json')) return null;
    try {
      final data = jsonDecode(text(response));
      final code = data is Map ? int.tryParse('${data['code']}') : null;
      return code == null ? null : jsonEncode({'code': code});
    } on FormatException {
      return null;
    }
  }

  Future<Map<String, dynamic>> object(String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('https://ids.shanghaitech.edu.cn$path');
    final personal = uri.path.startsWith('/personalInfo/');
    final reference = personal ? await cookie(uri, 'REFERERCE_TOKEN') : null;
    final response = await request(
      uri,
      method: body == null ? 'GET' : 'POST',
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        if (body != null) 'Content-Type': 'application/json',
        if (personal) 'Origin': 'https://ids.shanghaitech.edu.cn',
        if (personal)
          'Referer': 'https://ids.shanghaitech.edu.cn/personalInfo/personCenter/index.html',
        if (reference != null) 'refererToken': reference,
      },
      // IDS reports rejected password/captcha verification as JSON with HTTP
      // 500. Its business code must reach the verification flow unchanged.
      allowErrorResponse: uri.path == '/personalInfo/common/recheckUserInfo',
      data: body == null
          ? null
          : jsonEncode({...body, if (personal) 'n': '0.${DateTime.now().microsecondsSinceEpoch}'}),
    );
    try {
      return (jsonDecode(text(response)) as Map).cast<String, dynamic>();
    } on FormatException {
      if ((response.statusCode ?? 0) >= 500) {
        throw const IdsException('学校认证服务暂时不可用');
      }
      throw const IdsException('IDS 未返回有效登录结果，请重新绑定', credentialRejected: true);
    }
  }
}
