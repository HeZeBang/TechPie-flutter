import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../ids/campus_http.dart';
import '../session/cookie_provider.dart';
import '../session/session_tree.dart';
import 'campus_errors.dart';

typedef WithCampusCookie = Future<T?> Function<T>(
  Future<CookieAction<T>> Function(CookieProvider) action,
);
typedef CampusIdentity = ({String? user, String? ids});
typedef CampusResponse = Response<List<int>>;
typedef SendRequest = Future<CampusResponse> Function();
typedef ScheduleRequest = Future<CampusResponse> Function(SendRequest send);

/// One originating service and its current derived session. A renewed cookie
/// gets a fresh jar; requests already in flight keep their original jar.
class CampusSession {
  CampusSession(this.origin, this.dio, this.withCookie, this.identity);
  final Uri origin;
  final Dio dio;
  final WithCampusCookie withCookie;
  final CampusIdentity Function() identity;
  CampusIdentity? _owner;
  int _generation = 0;
  String? _cookie;
  CampusWire? _wire;

  void accountChanged() {
    if (_owner == identity()) return;
    reset();
  }

  void reset() {
    _generation++;
    _owner = identity();
    _cookie = null;
    _wire = null;
  }

  void _check(int generation) {
    accountChanged();
    if (_owner?.user == null) {
      throw const CampusRequestException(CampusErrorKind.notLoggedIn, '请先登录 TechPie');
    }
    if (_owner?.ids == null) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请先绑定 IDS');
    }
    if (_generation != generation) throw CampusRequestException.expired;
  }

  Future<T> run<T extends Object>(Future<T> Function(CampusWire wire) action) async {
    accountChanged();
    final generation = _generation;
    _check(generation);
    final value = await withCookie<T?>((provider) async {
      _check(generation);
      if (provider.domain != origin.host || provider.isEmpty) throw CampusRequestException.expired;
      if (_cookie != provider.cookies || _wire == null) {
        _cookie = provider.cookies;
        final http = CampusHttp(dio, allowedOrigins: {origin.origin});
        final cookies = provider.cookies
            .split(';')
            .map((p) => p.trim())
            .where((p) => p.contains('=') && p.split('=').first.toUpperCase() != 'CASTGC');
        final ready = http.restore([
          for (final pair in cookies) {'url': origin.toString(), 'cookie': '$pair; Path=/; Secure'},
        ]);
        _wire = CampusWire._(http, origin, ready, () => _check(generation));
      }
      final wire = _wire!;
      try {
        final result = await action(wire);
        _check(generation);
        return CookieAction(result, expired: false);
      } on CampusRequestException catch (e) {
        _check(generation);
        if (e.kind != CampusErrorKind.sessionExpired) rethrow;
        if (identical(_wire, wire)) _wire = null;
        return const CookieAction(null, expired: true);
      }
    });
    _check(generation);
    if (value == null) throw CampusRequestException.expired;
    return value;
  }
}

class CampusWire {
  CampusWire._(this._http, this.origin, this._ready, this._check);
  final CampusHttp _http;
  final Uri origin;
  final Future<void> _ready;
  final void Function() _check;

  Future<CampusResponse> request(
    String path, {
    String method = 'GET',
    Map<String, String>? query,
    Object? data,
    Map<String, String>? headers,
    ScheduleRequest? schedule,
  }) async {
    await _ready;
    var uri = origin.resolve(path);
    if (query != null) uri = uri.replace(queryParameters: query);
    for (var hop = 0; hop < 10; hop++) {
      if (!uri.isScheme('https') ||
          !uri.hasAuthority ||
          uri.userInfo.isNotEmpty ||
          uri.origin != origin.origin) {
        throw const CampusRequestException(CampusErrorKind.rejected, '不支持的校园服务地址');
      }
      Future<CampusResponse> send() {
        _check();
        return _http.request(
          uri,
          method: method,
          data: data,
          headers: headers,
          followRedirects: false,
          allowErrorResponse: true,
        );
      }

      late final CampusResponse response;
      try {
        response = await (schedule == null ? send() : schedule(send));
      } on IdsException {
        throw const CampusRequestException(CampusErrorKind.network, '无法连接校园服务');
      }
      _check();
      final status = response.statusCode ?? 0;
      if (status == 401) throw CampusRequestException.expired;
      if (![301, 302, 303, 307, 308].contains(status)) return response;
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null) throw CampusRequestException.invalid;
      uri = uri.resolve(location);
      if (uri.host == 'ids.shanghaitech.edu.cn') throw CampusRequestException.expired;
      if (status == 303 || ((status == 301 || status == 302) && method == 'POST')) {
        method = 'GET';
        data = null;
        headers = null;
      } else if (data is FormData) {
        data = data.clone();
      }
    }
    throw CampusRequestException.invalid;
  }
}

void checkStatus(CampusResponse response) {
  final code = response.statusCode ?? 0;
  if (code >= 200 && code < 300) return;
  if (code == 403) throw const CampusRequestException(CampusErrorKind.forbidden, '没有访问此服务的权限');
  if (code == 404) throw const CampusRequestException(CampusErrorKind.notFound, '当前系统未提供此资源');
  if (code == 429) throw const CampusRequestException(CampusErrorKind.rateLimited, '请求过于频繁，请稍后再试');
  throw CampusRequestException(
    code >= 500 || code == 0 ? CampusErrorKind.network : CampusErrorKind.rejected,
    '校园服务返回 HTTP $code',
  );
}

Map<String, dynamic> jsonObject(CampusResponse response) {
  checkStatus(response);
  try {
    final v = jsonDecode(CampusHttp.text(response));
    if (v is Map<String, dynamic>) return v;
  } on FormatException {
    throw CampusRequestException.invalid;
  }
  throw CampusRequestException.invalid;
}

String segment(String value) {
  if (value.isEmpty || value == '.' || value == '..' || value.contains('/')) {
    throw ArgumentError('Invalid campus path segment');
  }
  return Uri.encodeComponent(value);
}

const formHeaders = {'Content-Type': 'application/x-www-form-urlencoded'};
