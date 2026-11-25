import 'dart:convert';

import 'package:http/http.dart' as http;

import 'campus_user_agent.dart';
import 'debug_logger.dart';
import 'http_proxy_stub.dart'
    if (dart.library.io) 'http_proxy_io.dart' as proxy_impl;

final _appProxyPattern = RegExp(r'^(?:\[[0-9a-fA-F:]+\]|[^\s:/;@]+):(\d{1,5})$');

/// Normalizes user input such as `http://127.0.0.1:7890/` into `127.0.0.1:7890`.
String normalizeAppProxy(String value) {
  var normalized = value.trim();
  if (normalized.isEmpty) return '';
  if (normalized.toLowerCase().startsWith('http://')) {
    normalized = normalized.substring(7);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized.trim();
}

/// Returns true when [value] is a valid `host:port` (port 1..65535) HTTP proxy.
bool isValidAppProxy(String value) {
  final normalized = normalizeAppProxy(value);
  final match = _appProxyPattern.firstMatch(normalized);
  if (match == null) return false;
  final port = int.tryParse(match.group(1)!);
  return port != null && port >= 1 && port <= 65535;
}

/// Resolves the active proxy directive for [uri] (`PROXY host:port` or
/// environment fallback when app proxy is disabled).
String resolveAppProxy(Uri uri, {Map<String, String>? environment}) =>
    proxy_impl.resolveAppProxyImpl(uri, environment: environment);

/// Configures the app-wide HTTP proxy for native platforms. Empty or invalid
/// values disable the override and fall back to environment defaults.
void configureAppProxy(String value) {
  final normalized = normalizeAppProxy(value);
  proxy_impl.configureAppProxyImpl(
    isValidAppProxy(normalized) ? normalized : '',
  );
}

class LoggingHttpClient {
  final http.Client _inner;
  final DebugLogger _logger;

  LoggingHttpClient(this._logger, {http.Client? inner})
      : _inner = inner ?? http.Client();

  /// School SSO redirects can carry tickets and personal records. Log only
  /// the origin, status and structural summary, never credentials or raw bodies.
  Future<http.Response> readOnlyGet(Uri uri, {Map<String, String>? headers}) async {
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll(headers ?? const {});
    return _readSchoolRequest(request);
  }

  /// The official IDS client uses POST for these two identity reads. This exact
  /// allowlist deliberately excludes editing, binding and account switching.
  Future<http.Response> readIdsQuery(Uri uri, {Map<String, String>? headers}) {
    if (uri.scheme != 'https' ||
        uri.host != 'ids.shanghaitech.edu.cn' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !const {
          '/personalInfo/common/getUserConf',
          '/personalInfo/accountRelation/bindingUserList',
        }.contains(uri.path)) {
      throw const FormatException('不支持的 IDS 查询接口');
    }
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers.addAll(headers ?? const {})
      ..headers['Content-Type'] = 'application/json'
      ..body = '{}';
    return _readSchoolRequest(request);
  }

  Future<http.Response> _readSchoolRequest(http.Request request) async {
    final uri = request.url;
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _inner.send(request).timeout(const Duration(seconds: 15)),
      ).timeout(const Duration(seconds: 15));
    } catch (error) {
      _logger.log(
        method: request.method,
        uri: uri,
        error: '网络请求未完成（${error.runtimeType}）',
        tag: 'schoolSchedule:readOnly',
      );
      rethrow;
    }
    final summary = <String, dynamic>{
      'bytes': response.bodyBytes.length,
    };
    try {
      final value = jsonDecode(response.body);
      summary['format'] = 'JSON';
      if (value is Map<String, dynamic>) {
        final code = value['code'];
        if ((code is String || code is num) && RegExp(r'^-?\d{1,8}$').hasMatch('$code')) {
          summary['code'] = code;
        }
        if (value['success'] is bool) summary['success'] = value['success'];
        for (final key in ['results', 'bindingUserList', 'xkjgList', 'ntkmdList', 'rqpkjgallList']) {
          if (value[key] is List) summary['${key}Count'] = (value[key] as List<dynamic>).length;
        }
        final data = value['datas'];
        summary['datasType'] = data == null
            ? 'null'
            : data is Map
                ? 'object'
                : data is List
                    ? 'list'
                    : 'other';
        if (data is Map) {
          summary['currentUidPresent'] = data['uid']?.toString().trim().isNotEmpty == true;
          summary['categoryPresent'] = data['categoryName']?.toString().trim().isNotEmpty == true;
        }
      }
    } on FormatException {
      summary['format'] = RegExp(r'^\s*<', caseSensitive: false).hasMatch(response.body)
          ? 'HTML（可能为登录页面）'
          : '非 JSON';
    }
    _logger.log(
      method: request.method,
      uri: uri,
      statusCode: response.statusCode,
      responseSummary: summary,
      tag: 'schoolSchedule:readOnly',
    );
    return response;
  }

  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    String? tag,
  }) async {
    _logger.log(method: 'GET', uri: url, tag: tag);
    try {
      final response = await _inner.get(url, headers: {'User-Agent': CampusUserAgent.value, ...?headers});
      _logger.log(
        method: 'GET',
        uri: url,
        statusCode: response.statusCode,
        responseSummary: {'bytes': response.bodyBytes.length},
        tag: tag,
      );
      return response;
    } catch (e) {
      _logger.log(
        method: 'GET',
        uri: url,
        error: e.runtimeType.toString(),
        tag: tag,
      );
      rethrow;
    }
  }

  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    String? tag,
  }) async {
    final bodyStr =
        body is String ? body : (body != null ? jsonEncode(body) : null);
    _logger.log(
      method: 'POST',
      uri: url,
      tag: tag,
    );
    try {
      final response = await _inner.post(
        url,
        headers: {'User-Agent': CampusUserAgent.value, ...?headers},
        body: bodyStr,
        encoding: encoding,
      );
      _logger.log(
        method: 'POST',
        uri: url,
        statusCode: response.statusCode,
        responseSummary: {'bytes': response.bodyBytes.length},
        tag: tag,
      );
      return response;
    } catch (e) {
      _logger.log(
        method: 'POST',
        uri: url,
        error: e.runtimeType.toString(),
        tag: tag,
      );
      rethrow;
    }
  }

  Future<http.Response> head(
    Uri url, {
    Map<String, String>? headers,
    String? tag,
  }) async {
    _logger.log(method: 'HEAD', uri: url, tag: tag);
    try {
      final response = await _inner.head(url, headers: {'User-Agent': CampusUserAgent.value, ...?headers});
      _logger.log(
        method: 'HEAD',
        uri: url,
        statusCode: response.statusCode,
        tag: tag,
      );
      return response;
    } catch (e) {
      _logger.log(
        method: 'HEAD',
        uri: url,
        error: e.runtimeType.toString(),
        tag: tag,
      );
      rethrow;
    }
  }

  void close() => _inner.close();
}
