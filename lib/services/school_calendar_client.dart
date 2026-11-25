import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http_package;

import '../models/course_table.dart';
import 'campus_user_agent.dart';
import 'http_client.dart';

typedef SchoolCalendarResult = ({TermCalendar? calendar, bool sessionExpired});

/// Read-only on-device client for ShanghaiTech's eGate school calendar API
/// (`getSchoolCalendar.do`).
///
/// The calendar lives on `egate.shanghaitech.edu.cn` (`/publicapp/sys/mykbxt`),
/// NOT on `eams.shanghaitech.edu.cn`, so EAMS session cookies cannot authorize
/// it. Authenticating locally keeps `CASTGC` strictly isolated to
/// `ids.shanghaitech.edu.cn` and avoids sending root IDS credentials to the
/// TechPie backend.
class SchoolCalendarClient {
  SchoolCalendarClient(this.http, this.tgc);

  final LoggingHttpClient http;
  final String tgc;
  final Map<String, List<_CalendarCookie>> _cookieJars = {};

  static const host = 'egate.shanghaitech.edu.cn';
  static const idsHost = 'ids.shanghaitech.edu.cn';
  static const calendarPath = '/publicapp/sys/mykbxt/api/getSchoolCalendar.do';

  static Uri buildCalendarUri({
    required String schoolYearTerm,
    required String termJump,
  }) =>
      Uri.https(host, calendarPath, {
        'termJump': termJump,
        'schoolYearTerm': schoolYearTerm,
      });

  Future<SchoolCalendarResult> fetchTermCalendar({
    required String year,
    required String semester,
  }) async {
    final yearNum = int.tryParse(year);
    final semesterNum = int.tryParse(semester);
    if (yearNum == null || semesterNum == null) {
      throw const FormatException('学年或学期参数无效');
    }
    if (tgc.isEmpty || tgc.contains(RegExp(r'[\r\n;]'))) {
      return (calendar: null, sessionExpired: true);
    }

    // The eGate calendar endpoint resolves terms relative to an adjacent anchor
    // term via termJump=prev/next (a bare schoolYearTerm returns "查询不到当前学年学期信息"):
    //   semester >= 2: anchor on same-year (semester - 1), jump next
    //   semester == 1: anchor on same-year 2, jump prev
    final anchorSemester = semesterNum >= 2 ? semesterNum - 1 : 2;
    final termJump = semesterNum >= 2 ? 'next' : 'prev';
    final anchorTerm = '$yearNum-${yearNum + 1}-$anchorSemester';
    final targetTerm = '$yearNum-${yearNum + 1}-$semesterNum';

    final primary = await _queryAnchor(
      anchorTerm: anchorTerm,
      termJump: termJump,
      fallbackTerm: targetTerm,
    );
    if (primary.sessionExpired || primary.calendar != null) {
      return primary;
    }

    // Fallback for fall terms if same-year spring hasn't been published yet:
    // anchor on the preceding academic year's summer term and jump next.
    if (semesterNum == 1) {
      final fallback = await _queryAnchor(
        anchorTerm: '${yearNum - 1}-$yearNum-3',
        termJump: 'next',
        fallbackTerm: targetTerm,
      );
      if (fallback.sessionExpired || fallback.calendar != null) {
        return fallback;
      }
    }

    throw const FormatException('校历接口未返回该学期的开学日期');
  }

  Future<SchoolCalendarResult> _queryAnchor({
    required String anchorTerm,
    required String termJump,
    required String fallbackTerm,
  }) async {
    final uri = buildCalendarUri(
      schoolYearTerm: anchorTerm,
      termJump: termJump,
    );
    final (lastUri, response) = await _get(uri);

    if (_isIdsLoginUri(lastUri) ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      return (calendar: null, sessionExpired: true);
    }
    if (response.statusCode != 200) {
      throw FormatException('校历接口返回 HTTP ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      if (response.body.contains('统一身份认证') ||
          response.body.contains('name="execution"')) {
        return (calendar: null, sessionExpired: true);
      }
      throw const FormatException('校历接口未返回有效 JSON，请稍后重试');
    }

    if (decoded is! Map) {
      throw const FormatException('校历接口返回数据格式异常');
    }
    final map = decoded.cast<String, dynamic>();
    final termBeginRaw = map['termBegin'];
    if (termBeginRaw is! String ||
        termBeginRaw.trim().isEmpty ||
        DateTime.tryParse(termBeginRaw) == null) {
      return (calendar: null, sessionExpired: false);
    }

    final normalized = <String, dynamic>{
      ...map,
      if ((map['schoolYearTerm']?.toString() ?? '').trim().isEmpty)
        'schoolYearTerm': fallbackTerm,
    };
    return (
      calendar: TermCalendar.fromJson(normalized),
      sessionExpired: false,
    );
  }

  Future<(Uri, http_package.Response)> _get(Uri uri) async {
    for (var hop = 0; hop < 12; hop++) {
      if (!_allowed(uri)) {
        throw const FormatException('校历登录跳转地址不受支持');
      }
      final jar = _cookieJars.putIfAbsent(uri.origin, () => []);
      final applicable = jar.where(
        (c) => c.matches(uri) && (c.cookie.name != 'CASTGC' || uri.host == idsHost),
      );
      final cookies = [
        ...applicable.map((c) => '${c.cookie.name}=${c.cookie.value}'),
        if (uri.host == idsHost && !applicable.any((c) => c.cookie.name == 'CASTGC'))
          'CASTGC=$tgc',
      ].join('; ');
      final headers = {
        'User-Agent': CampusUserAgent.value,
        'Accept': 'application/json, text/html;q=0.9',
        if (cookies.isNotEmpty) 'Cookie': cookies,
      };
      final response = await http.readOnlyGet(uri, headers: headers);
      _storeCookies(uri, jar, response.headers['set-cookie']);

      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) break;
        uri = uri.resolve(location);
        continue;
      }
      return (uri, response);
    }
    throw const FormatException('校历登录跳转次数过多，请更新 IDS 绑定');
  }

  void _storeCookies(Uri uri, List<_CalendarCookie> jar, String? rawHeader) {
    if (rawHeader == null || rawHeader.isEmpty) return;
    final nowUtc = DateTime.now().toUtc();
    for (final raw in rawHeader.split(RegExp(r',(?=\s*[^\s;,=]+=)'))) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      try {
        final cookie = Cookie.fromSetCookieValue(trimmed);
        if (cookie.name == 'CASTGC' && uri.host != idsHost) continue;
        final domain =
            (cookie.domain ?? uri.host).replaceFirst(RegExp(r'^\.'), '').toLowerCase();
        if (domain != uri.host && !uri.host.endsWith('.$domain')) continue;
        final slash = uri.path.lastIndexOf('/');
        final defaultPath = slash <= 0 ? '/' : uri.path.substring(0, slash);
        final path = cookie.path?.startsWith('/') == true ? cookie.path! : defaultPath;
        DateTime? expires = cookie.expires?.toUtc();
        if (cookie.maxAge != null) {
          expires = nowUtc.add(Duration(seconds: cookie.maxAge!));
        }
        jar.removeWhere(
          (c) => c.cookie.name == cookie.name && c.domain == domain && c.path == path,
        );
        if (cookie.maxAge != 0 && (expires == null || expires.isAfter(nowUtc))) {
          jar.add(
            _CalendarCookie(
              cookie,
              domain,
              cookie.domain == null,
              path,
              expires,
            ),
          );
        }
      } on HttpException {
        // Ignore malformed optional cookie headers.
      } on FormatException {
        // Ignore empty or malformed cookie headers.
      }
    }
  }

  bool _isIdsLoginUri(Uri uri) =>
      uri.host == idsHost &&
      (uri.path == '/authserver/login' || uri.path == '/authserver/login/');

  bool _allowed(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.port != 443) {
      return false;
    }
    if (uri.host == idsHost) {
      return uri.path == '/authserver/login' || uri.path == '/authserver/login/';
    }
    if (uri.host != host) return false;
    return uri.path == calendarPath || uri.path.startsWith('/publicapp/');
  }
}

class _CalendarCookie {
  const _CalendarCookie(
    this.cookie,
    this.domain,
    this.hostOnly,
    this.path,
    this.expiresUtc,
  );

  final Cookie cookie;
  final String domain;
  final bool hostOnly;
  final String path;
  final DateTime? expiresUtc;

  bool matches(Uri uri) =>
      (uri.host == domain || (!hostOnly && uri.host.endsWith('.$domain'))) &&
      (uri.path == path ||
          (uri.path.startsWith(path) &&
              (path.endsWith('/') || uri.path.substring(path.length).startsWith('/')))) &&
      (expiresUtc == null || expiresUtc!.isAfter(DateTime.now().toUtc()));
}
