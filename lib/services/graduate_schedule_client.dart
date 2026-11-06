import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http_package;

import '../models/campus_identity.dart';
import 'http_client.dart';

/// A read-only school client. Identity comes from IDS, independently of access
/// to the graduate application. CASTGC is sent only to IDS.
class GraduateScheduleClient {
  GraduateScheduleClient(this.http, this.tgc);

  final LoggingHttpClient http;
  final String tgc;
  final List<_SchoolCookie> _cookies = [];
  Future<void>? _graduateSession;
  static const host = 'graduate-course.shanghaitech.edu.cn';
  static const idsHost = 'ids.shanghaitech.edu.cn';
  static const base = '/yjsxkapp/sys/xsxkapp/';

  // GET_USER_INFO in the official frontend. queryUserData is the editable
  // profile/form model and is not the authenticated principal.
  static final _idsProfile = Uri.https(idsHost, '/personalInfo/common/getUserConf');
  static final _idsAccounts = Uri.https(idsHost, '/personalInfo/accountRelation/bindingUserList');
  static final _idsPage = Uri.https(idsHost, '/personalInfo/personCenter/index.html');
  static final _graduatePage = Uri.https(host, '${base}course.html');
  // The university's student manual links this protected application entry.
  // Static .html pages and public configuration do not establish a CAS session.
  static final _graduateEntry = Uri.https(host, '$base*default/index.do');

  Future<CampusIdentity> identity(String expectedSid) async {
    // Follow the same personal-center entry as the official frontend so IDS can
    // establish its own session and reference-token cookie before its API call.
    final (pageUri, pageResponse) = await _get(_idsPage);
    if (pageUri.host == idsHost && pageUri.path == '/authserver/login') {
      throw const FormatException('IDS 登录会话已失效，请更新 CpDaily / IDS 绑定');
    }
    if (pageResponse.statusCode != 200) {
      throw FormatException('IDS 个人中心返回 HTTP ${pageResponse.statusCode}');
    }
    final profile = await _jsonUri(_idsProfile, idsQuery: true);
    var identity = CampusIdentity.fromIds(profile, expectedSid);
    if (identity.categoryName.isEmpty) {
      final (uri, response) = await _get(_idsAccounts, idsQuery: true);
      final value = _decodeJson(uri, response, 'IDS 身份分类');
      identity = CampusIdentity.fromIds(profile, expectedSid, associatedAccounts: value);
    }
    return identity;
  }

  Future<Map<String, dynamic>> publicInfo() => _json('xsxkHome/loadPublicInfo_course.do');
  Future<Map<String, dynamic>> timetable() => _json('xsxkCourse/loadKbxx.do');

  Future<Map<String, dynamic>> _json(String path) async {
    // Share both success and failure within a refresh. A broken entry must not
    // be requested again when optional metadata fails before the timetable read.
    await (_graduateSession ??= _openGraduateSession());
    return _jsonUri(
      Uri.https(host, '$base$path', {
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      }),
    );
  }

  Future<void> _openGraduateSession() async {
    final (entryUri, entryResponse) = await _get(_graduateEntry);
    if (entryUri.host == idsHost && entryUri.path == '/authserver/login') {
      throw const FormatException('研究生系统的 IDS 登录会话已失效，请更新 CpDaily / IDS 绑定');
    }
    if (entryResponse.statusCode != 200) {
      throw FormatException('研究生系统认证入口返回 HTTP ${entryResponse.statusCode}');
    }
  }

  Future<Map<String, dynamic>> _jsonUri(Uri uri, {bool idsQuery = false}) async {
    final label = uri.host == idsHost
        ? 'IDS 用户信息'
        : uri.path.endsWith('loadKbxx.do')
            ? '研究生课表（loadKbxx.do）'
            : '研究生学期配置（loadPublicInfo_course.do）';
    for (var attempt = 0; attempt < 2; attempt++) {
      final (lastUri, response) = await _get(uri, idsQuery: idsQuery);
      if (attempt == 0 &&
          uri.host == host &&
          response.statusCode == 200 &&
          lastUri.host == host &&
          lastUri.path.endsWith('.html') &&
          lastUri.path != uri.path) {
        // An actual SSO redirect can finish on the application's HTML landing
        // page. Read the requested API once with the newly established cookies.
        continue;
      }
      // EMAP can return its CAS entry in JSON rather than an HTTP redirect.
      // Follow only that explicit login signal, once; never retry a 404.
      String? loginUrl;
      if (uri.host == host && [200, 401, 403].contains(response.statusCode)) {
        try {
          final value = jsonDecode(response.body);
          if (value is Map<String, dynamic> && value['loginURL'] is String) {
            loginUrl = value['loginURL'] as String;
          }
        } on FormatException {
          // _decodeJson below reports a non-JSON response with its stage.
        }
      }
      if (loginUrl != null && loginUrl.isNotEmpty && attempt == 0) {
        final (loginUri, loginResponse) = await _get(uri.resolve(loginUrl));
        if (loginUri.host == idsHost && loginUri.path == '/authserver/login') {
          throw FormatException('$label的学校登录会话已失效');
        }
        if (loginResponse.statusCode != 200) {
          throw FormatException('$label登录入口返回 HTTP ${loginResponse.statusCode}');
        }
        continue;
      }
      if (loginUrl != null && loginUrl.isNotEmpty) {
        throw FormatException('$label登录后仍返回登录入口，学校会话未建立');
      }
      return _decodeJson(lastUri, response, label);
    }
    throw FormatException('$label登录后仍未取得数据');
  }

  Map<String, dynamic> _decodeJson(Uri lastUri, http_package.Response response, String label) {
    if (lastUri.host == idsHost && lastUri.path == '/authserver/login') {
      throw FormatException('$label被重定向到登录页，学校会话已失效');
    }
    if (response.statusCode != 200) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw FormatException('$label返回 HTTP ${response.statusCode}，学校会话未认证或没有访问权限');
      }
      throw FormatException('$label返回 HTTP ${response.statusCode}；请稍后重试，不会自动反复访问');
    }
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      throw FormatException('$label返回 HTTP 200，但内容是网页而非 JSON（可能登录已过期）');
    }
    throw FormatException('$label返回数据格式变化');
  }

  Future<(Uri, http_package.Response)> _get(Uri uri, {bool idsQuery = false}) async {
    if (tgc.isEmpty || tgc.contains(RegExp(r'[\r\n;]'))) {
      throw const FormatException('学校绑定缺少有效的 CASTGC，请更新 CpDaily / IDS 绑定');
    }
    for (var hop = 0; hop < 12; hop++) {
      if (!_allowed(uri)) throw const FormatException('学校登录跳转地址不受支持');
      final applicable = _cookies
          .where((c) => c.matches(uri) && (c.cookie.name != 'CASTGC' || uri.host == idsHost));
      final cookies = [
        ...applicable.map((c) => '${c.cookie.name}=${c.cookie.value}'),
        if (uri.host == idsHost && !applicable.any((c) => c.cookie.name == 'CASTGC')) 'CASTGC=$tgc',
      ].join('; ');
      final headers = {
        if (cookies.isNotEmpty) 'Cookie': cookies,
        'Accept': 'application/json, text/html;q=0.9',
        if (uri.host == host && uri.path.endsWith('.do')) ...{
          // The official initial public-info request uses plain XMLHttpRequest;
          // only the later jQuery timetable request marks itself as AJAX.
          if (uri.path.endsWith('loadKbxx.do')) 'X-Requested-With': 'XMLHttpRequest',
          'Referer': _graduatePage.toString(),
          'Cache-Control': 'no-cache',
        },
        if (uri.host == idsHost && uri.path.startsWith('/personalInfo/')) ...{
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': _idsPage.toString(),
          for (final c in applicable)
            if (c.cookie.name == 'REFERERCE_TOKEN') 'refererToken': c.cookie.value,
          for (final c in applicable)
            if (c.cookie.name == 'XSRF-TOKEN') 'X-XSRF-TOKEN': Uri.decodeComponent(c.cookie.value),
        },
      };
      final response = idsQuery && (uri == _idsAccounts || uri == _idsProfile)
          ? await http.readIdsQuery(uri, headers: headers)
          : await http.readOnlyGet(uri, headers: headers);
      for (final raw
          in (response.headers['set-cookie'] ?? '').split(RegExp(r',(?=\s*[^\s;,=]+=)'))) {
        if (raw.trim().isEmpty) continue;
        try {
          final cookie = Cookie.fromSetCookieValue(raw.trim());
          if (cookie.name == 'CASTGC' && uri.host != idsHost) continue;
          final domain = (cookie.domain ?? uri.host).replaceFirst(RegExp(r'^\.'), '').toLowerCase();
          // Never accept a cookie for a sibling or unrelated host.
          if (domain != uri.host && !uri.host.endsWith('.$domain')) continue;
          final directory = uri.path.substring(0, uri.path.lastIndexOf('/'));
          final defaultPath = directory.isEmpty ? '/' : directory;
          final stored = _SchoolCookie(
            cookie,
            domain,
            cookie.domain == null,
            cookie.path?.startsWith('/') == true ? cookie.path! : defaultPath,
          );
          _cookies.removeWhere(
            (c) => c.cookie.name == cookie.name && c.domain == domain && c.path == stored.path,
          );
          if (cookie.maxAge != 0 &&
              (cookie.expires == null || cookie.expires!.isAfter(DateTime.now()))) {
            _cookies.add(stored);
          }
        } on HttpException {
          // Ignore malformed optional cookie headers.
        } on FormatException {
          // Empty Set-Cookie or an unrelated malformed cookie.
        }
      }
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) break;
        uri = uri.resolve(location);
        continue;
      }
      return (uri, response);
    }
    throw const FormatException('学校登录跳转次数过多，请更新 CpDaily / IDS 绑定');
  }

  bool _allowed(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.port != 443) return false;
    if (uri.host == idsHost) {
      return {
        '/authserver/login',
        _idsProfile.path,
        _idsAccounts.path,
        _idsPage.path,
        '/personalInfo/',
      }.contains(uri.path);
    }
    if (uri.host != host) return false;
    return {
      '${base}index.html',
      _graduateEntry.path,
      _graduatePage.path,
      '${base}xsxkHome/loadPublicInfo_course.do',
      '${base}xsxkCourse/loadKbxx.do',
      '/yjsxkapp/login',
      '/yjsxkapp/login/',
      '/yjsxkapp/',
    }.contains(uri.path);
  }
}

class _SchoolCookie {
  const _SchoolCookie(this.cookie, this.domain, this.hostOnly, this.path);
  final Cookie cookie;
  final String domain;
  final bool hostOnly;
  final String path;

  bool matches(Uri uri) =>
      (uri.host == domain || (!hostOnly && uri.host.endsWith('.$domain'))) &&
      (uri.path == path ||
          (uri.path.startsWith(path) &&
              (path.endsWith('/') || uri.path.substring(path.length).startsWith('/')))) &&
      (cookie.expires == null || cookie.expires!.isAfter(DateTime.now()));
}
