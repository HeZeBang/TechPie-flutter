import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;

import '../models/oa_gym.dart';
import 'campus_user_agent.dart';

class OaGymLocalException implements Exception {
  final String message;
  final bool sessionExpired;
  const OaGymLocalException(this.message, {this.sessionExpired = false});
}

/// OA business requests for an already authenticated, client-owned session.
/// Authentication and renewal remain in the existing IDS session tree.
class OaGymLocalClient {
  OaGymLocalClient(this._client);
  final http.Client _client;

  Future<Map<String, dynamic>> request(
    String path,
    Map<String, dynamic> parameters, {
    required String cookies,
    Map<String, String> venues = const {},
    Map<String, String> timeSlots = const {},
  }) async {
    final session = _OaSession(_client);
    await session.restore(cookies);
    try {
      final Object data;
      switch (path) {
        case 'oa/gym/metadata':
          data = await _metadata(session);
        case 'oa/gym/availability':
          data = await _availability(session, parameters);
        case 'oa/gym/search':
          data = await _search(session, parameters, venues, timeSlots);
        case 'oa/gym/book':
          data = await _book(session, (parameters['booking'] as Map).cast<String, dynamic>());
        case 'oa/gym/profile':
          data = await _profile(session);
        default:
          throw const OaGymLocalException('不支持的 OA 请求');
      }
      return {'success': true, 'data': data};
    } on TimeoutException {
      throw OaGymLocalException(
        path.endsWith('/book') ? '预约提交超时，请先查询预约记录确认结果，避免重复提交' : '学校 OA 查询超时，请稍后重试或缩小日期范围',
      );
    } on http.ClientException {
      throw OaGymLocalException(
        path.endsWith('/book') ? '预约连接中断，请先查询预约记录确认结果，避免重复提交' : '无法连接学校 OA，请检查网络后重试',
      );
    }
  }

  Future<Map<String, String>> _profile(_OaSession session) async {
    var userId = await session.cookie('loginidweaver');
    if (userId == null || userId.isEmpty) {
      await session.send('/workflow/request/AddRequest.jsp', query: {'workflowid': '14862'});
      userId = await session.cookie('loginidweaver');
    }
    if (userId == null || userId.isEmpty) {
      throw const OaGymLocalException('无法确认 OA 当前用户，请刷新登录态后重试');
    }
    // The public resource card masks phone numbers. Read the signed-in user's
    // own contact form, without submitting it or accepting a caller-supplied ID.
    final html = await session.send(
      '/hrm/resource/HrmResourceContactEdit.jsp',
      query: {'isfromtab': 'true', 'id': userId, 'isView': '1'},
    );
    final form = parse(html).querySelector('form#resource');
    if (form?.querySelector('input[name="id"]')?.attributes['value'] != userId) {
      throw const OaGymLocalException('OA 未返回当前用户的联系信息，请重试或手动填写');
    }
    String value(String name) =>
        form!.querySelector('input[name="$name"]')?.attributes['value']?.trim() ?? '';
    return {'phone': value('mobile'), 'email': value('email')};
  }

  Future<Map<String, dynamic>> _metadata(_OaSession session) async {
    final timestamp = '${DateTime.now().millisecondsSinceEpoch}';
    Future<String> browser(String id, String type) async {
      final html = await session.send(
        '/formmode/browser/CommonSingleBrowser.jsp',
        query: {
          'customid': id,
          'browsertype': type,
          'sqlwhere': '',
          'workflowid': '-1',
          'currenttime': timestamp,
          'sqlcondition': '',
        },
        headers: {'Origin': _OaSession.origin.origin},
      );
      return _tableString(html);
    }

    final timeTable = await browser('7102', 'browser.sysjd');
    final venueTable = await browser('7101', 'browser.tygcg');
    final timeRows = await _tableRows(session, timeTable);
    final venueRows = await _tableRows(session, venueTable);
    final times = <String, String>{
      for (final row in timeRows)
        if (row.length > 2) _timeRange(row[2]): row[0],
    };
    final all = <String, String>{
      for (final row in venueRows)
        if (row.length > 2) row[2]: row[0],
    };
    final venues = <String, String>{
      '所有场地': 'all',
      '室内羽毛球场': 'badminton_group',
      '室内乒乓球场': 'pingpong_group',
      '网球场': 'tennis_group',
      '匹克球场': 'pickleball_group',
      for (final entry in all.entries)
        if (entry.value != '44' &&
            !oaIsUnusedVenue(entry.key) &&
            OaSport.values.any((sport) => oaVenueMatchesSport(entry.key, sport)))
          entry.key: entry.value,
    };
    if (times.isEmpty || venues.length <= 5) {
      throw const OaGymLocalException('加载 OA 场馆数据失败，请稍后重试');
    }
    return {'venues': venues, 'allVenues': all, 'timeSlots': times};
  }

  Future<List<Map<String, dynamic>>> _availability(
    _OaSession session,
    Map<String, dynamic> parameters,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (final id in parameters['sports'] as List) {
      final sport = OaSport.values.byName(id as String);
      final config = oaSportConfigs[sport]!;
      for (var slot = parameters['startSlot'] as int;
          slot <= (parameters['endSlot'] as int);
          slot++) {
        final query = {
          'id': '63',
          'init': 'false',
          'showtype': '1',
          'isselsub': '0',
          'isonlyleaf': '1',
          'dataconditionParam': '_sfn_31901_sfv_${parameters['date']}'
              '_sfn_31902_sfv_${slot}_sfn_32340_sfv_${config.field32340}',
          'treerootnode': '',
          'selectedids': '',
          'time': '${DateTime.now().millisecondsSinceEpoch}',
        };
        Future<List<dynamic>> tree(String pid, String name) async {
          final body = await session.send(
            '/formmode/tree/treebrowser/CustomTreeBrowserAjax.jsp',
            query: query,
            form: [MapEntry('pid', pid), MapEntry('name', name)],
            headers: {
              'Accept': 'text/plain, */*; q=0.01',
              'Content-Type': 'application/x-www-form-urlencoded',
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': '${_OaSession.origin}wui/main.jsp?templateId=1',
            },
          );
          return jsonDecode(body.replaceFirst('\uFEFF', '')) as List;
        }

        final parents = await tree('63_1', '体育馆');
        final parent = parents
            .cast<Map<String, dynamic>>()
            .where((item) => item['name'] == config.parentName)
            .firstOrNull;
        final numbers = <int>{};
        if (parent != null && parent['isParent'].toString() != 'false') {
          for (final item in await tree(parent['id'].toString(), config.parentName)) {
            final name = (item['name'] as String?) ?? '';
            if (!name.startsWith(config.courtNamePrefix)) continue;
            final number = int.tryParse(RegExp(r'\d+').firstMatch(name)?.group(0) ?? '');
            if (number != null && number >= 1 && number <= config.courtCount) numbers.add(number);
          }
        }
        result.add({
          'sport': id,
          'date': parameters['date'],
          'timeSlot': slot,
          'availableCourts': numbers.toList()..sort(),
          'totalCourts': config.courtCount,
        });
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _search(
    _OaSession session,
    Map<String, dynamic> parameters,
    Map<String, String> venues,
    Map<String, String> timeSlots,
  ) async {
    final results = <Map<String, dynamic>>[];
    for (final venue in parameters['venueNames'] as List) {
      for (final range in parameters['timeRanges'] as List) {
        final fields = <MapEntry<String, String>>[
          const MapEntry('customid', '16201'),
          const MapEntry('viewtype', '0'),
          const MapEntry('issimple', 'true'),
          const MapEntry('formmodeid', '11684'),
          const MapEntry('formid', '-247'),
          const MapEntry('template', '-1'),
          const MapEntry('check_con', '31869'),
          const MapEntry('con31869_htmltype', '3'),
          const MapEntry('con31869_type', '161'),
          const MapEntry('con31869_colname', 'sycd'),
          const MapEntry('con31869_viewtype', '0'),
          const MapEntry('con31869_opt', '1'),
          MapEntry('con31869_value', venues[venue]!),
          MapEntry('con31869_name', venue as String),
          const MapEntry('check_con', '31870'),
          const MapEntry('con31870_htmltype', '3'),
          const MapEntry('con31870_type', '2'),
          const MapEntry('con31870_colname', 'syrq'),
          const MapEntry('con31870_viewtype', '0'),
          const MapEntry('datetype_31870_opt', '6'),
          const MapEntry('con31870_opt', '2'),
          MapEntry('con31870_value', parameters['startDate'] as String),
          const MapEntry('con31870_opt1', '4'),
          MapEntry('con31870_value1', parameters['endDate'] as String),
          const MapEntry('tableMax', '20'),
          if ((range as String).isNotEmpty) ...[
            const MapEntry('check_con', '31871'),
            const MapEntry('con31871_htmltype', '3'),
            const MapEntry('con31871_type', '161'),
            const MapEntry('con31871_colname', 'sysjd'),
            const MapEntry('con31871_viewtype', '0'),
            const MapEntry('con31871_opt', '1'),
            MapEntry('con31871_value', timeSlots[_timeRange(range)]!),
            MapEntry('con31871_name', _timeRange(range)),
          ],
        ];
        final html = await session.send(
          '/formmode/search/CustomSearchBySimpleIframe.jsp',
          query: {'customid': '16201', 'mainid': '0'},
          form: fields,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': _OaSession.origin.origin,
          },
        );
        // Let session-expiry errors reach SessionTree; never return partial
        // results after a login redirect or 401 during a multi-court query.
        results.add({
          'venue': venue,
          'timeRange': range,
          'rows': await _tableRows(session, _tableString(html)),
        });
      }
    }
    return results;
  }

  Future<Map<String, dynamic>> _book(_OaSession session, Map<String, dynamic> booking) async {
    final sport = OaSport.values.byName(booking['sport'] as String);
    final config = oaSportConfigs[sport]!;
    final slot = oaTimeSlots.firstWhere((slot) => slot.id == booking['timeSlot']);
    await session.send('/workflow/request/AddRequest.jsp', query: {'workflowid': '14862'});
    final userId = await session.cookie('loginidweaver');
    if (userId == null || userId.isEmpty) {
      throw const OaGymLocalException('无法确认 OA 当前用户，请刷新登录态后重试');
    }
    final today =
        DateTime.now().toUtc().add(const Duration(hours: 8)).toIso8601String().substring(0, 10);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final court = config.courtOffset + (booking['courtNumber'] as int);
    final fields = {
      'requestname': '学生和教工场馆借用申请-${booking['userName']}-$today',
      'field31876': userId,
      'field31877': '885',
      'field34283': booking['studentId'],
      'field31879': booking['phone'],
      'field31880': booking['email'] ?? '',
      'field32340': config.field32340,
      'field31901': booking['date'],
      'field31902': '${booking['timeSlot']}',
      'field31883': '63_$court',
      'field31884': '${booking['playersCount']}',
      'field31885': '0',
      'field31888': booking['userName'],
      'field31889': booking['phone'],
      'field31892': '1',
      'field31904': slot.start,
      'field31905': slot.end,
      'field31878': today,
      'mainId': '41',
      'subId': '11482',
      'secId': '11483',
      'workflowid': '14862',
      'workflowtype': '61',
      'nodeid': '16385',
      'nodetype': '0',
      'src': 'submit',
      'iscreate': '1',
      'formid': '-248',
      'isbill': '1',
      'needcheck': ',requestname,field31883,field31884,field31885,field31888,'
          'field31889,field31892,field31901,field31902,field32340,,,,',
      'requestid': '-1',
      'rand': '$timestamp',
      'needwfback': '1',
      'f_weaver_belongto_userid': 'null',
      'f_weaver_belongto_usertype': 'null',
      '${userId}_14862_addrequest_submit_token': '${timestamp + 1}',
      'freeNode': '0',
      'freeDuty': '1',
    };
    final html = await session.send(
      '/workflow/request/RequestOperation.jsp',
      form: fields.entries.map((e) => MapEntry(e.key, e.value as String)).toList(),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );
    final success = html.contains("wfforward('/workflow/request/WorkflowDirection.jsp?");
    final label = '${config.courtNamePrefix}${booking['courtNumber']}${config.courtNameSuffix}';
    return {
      'success': success,
      'message': '${sport.label} $label ${slot.range} '
          '${success ? '预约成功' : '提交失败，请检查 OA 系统状态'}',
    };
  }

  Future<List<List<String>>> _tableRows(_OaSession session, String table) async {
    final rows = <List<String>>[];
    for (var page = 0; page <= 20; page++) {
      final fields = {'tableString': table, 'pageIndex': '$page', 'mode': 'run'};
      const path = '/weaver/weaver.common.util.taglib.SplitPageXmlServlet';
      final headers = {'Origin': _OaSession.origin.origin};
      var body = await session.send(path, form: fields.entries.toList(), headers: headers);
      var next = _xmlRows(body);
      if (body.trim().isNotEmpty && next.isEmpty) {
        body = await session.send(path, query: fields, form: const [], headers: headers);
        next = _xmlRows(body);
      }
      rows.addAll(next);
      if (next.length < 10) break;
    }
    return rows;
  }
}

/// One operation owns its OA cookies. It cannot follow a redirect into IDS or
/// send cookies to another host. SessionTree supplies a fresh session on expiry.
class _OaSession {
  _OaSession(this.client);
  final http.Client client;
  final CookieJar jar = CookieJar();
  static final origin = Uri.parse('https://oa.shanghaitech.edu.cn/');

  Future<void> restore(String raw) async {
    await jar.saveFromResponse(origin, [
      for (final part in raw.split(';'))
        if (part.indexOf('=') > 0)
          Cookie(part.trim().split('=').first, part.substring(part.indexOf('=') + 1).trim())
            ..path = '/'
            ..secure = true,
    ]);
    if (await cookie('shkjdx_session') == null) _expired();
  }

  Future<String?> cookie(String name) async =>
      (await jar.loadForRequest(origin)).where((c) => c.name == name).firstOrNull?.value;

  Never _expired() => throw const OaGymLocalException(
        'OA 登录态已失效，请刷新登录态后重试',
        sessionExpired: true,
      );

  Future<String> send(
    String path, {
    Map<String, String>? query,
    List<MapEntry<String, String>>? form,
    Map<String, String>? headers,
  }) async {
    var uri = origin.resolve(path).replace(queryParameters: query);
    var body =
        form?.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
    for (var redirect = 0; redirect < 10; redirect++) {
      if (uri.scheme != 'https' ||
          uri.host != origin.host ||
          uri.userInfo.isNotEmpty ||
          uri.path.startsWith('/login/')) {
        _expired();
      }
      final request = http.Request(body == null ? 'GET' : 'POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent': CampusUserAgent.value,
          'Referer': origin.toString(),
          'Cookie': (await jar.loadForRequest(uri)).map((c) => '${c.name}=${c.value}').join('; '),
          if (body != null) 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          ...?headers,
        });
      if (body != null) request.bodyBytes = utf8.encode(body);
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null) {
        await jar.saveFromResponse(uri, [
          for (final value in setCookie.split(RegExp(r',(?=\s*[^;,=\s]+=[^;,]+)')))
            Cookie.fromSetCookieValue(value.trim()),
        ]);
      }
      final status = response.statusCode;
      if (status == 401 || status == 403) _expired();
      if ([301, 302, 303, 307, 308].contains(status) && response.headers['location'] != null) {
        uri = uri.resolve(response.headers['location']!);
        if ([301, 302, 303].contains(status)) body = null;
        continue;
      }
      if (status < 200 || status >= 400) {
        throw OaGymLocalException('学校 OA 请求失败（HTTP $status），请稍后重试');
      }
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (RegExp(r'''<input\b[^>]*type\s*=\s*["']?password\b''', caseSensitive: false)
              .hasMatch(text) ||
          RegExp(
            r'''(?:top|window|parent)\.location(?:\.href)?\s*=\s*["'][^"']*/login/''',
            caseSensitive: false,
          ).hasMatch(text)) {
        _expired();
      }
      return text;
    }
    _expired();
  }
}

String _tableString(String html) {
  for (final pattern in [
    r'''var\s+__tableStringKey__\s*=\s*['"]([0-9A-F]+)['"]''',
    r'''name=["']?tableString["']?\s+value=["']?([0-9A-F]+)["']?''',
    r'''tableString\s*=\s*["']?([0-9A-F]+)["']?''',
  ]) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(html);
    if (match != null) return match.group(1)!;
  }
  throw const OaGymLocalException('OA 未返回场馆查询数据，请刷新后重试');
}

List<List<String>> _xmlRows(String xml) => [
      for (final row
          in RegExp(r'<row\b[^>]*>([\s\S]*?)</row>', caseSensitive: false).allMatches(xml))
        [
          for (final col in RegExp(r'<col\b([^>]*?)(?:/>|>([\s\S]*?)</col>)', caseSensitive: false)
              .allMatches(row.group(1)!))
            _cleanHtml(
              RegExp(r'''showvalue\s*=\s*(['"])(.*?)\1''', caseSensitive: false, dotAll: true)
                      .firstMatch(col.group(1)!)
                      ?.group(2) ??
                  col.group(2) ??
                  '',
            ),
        ],
    ];

String _cleanHtml(String value) {
  final decoded = parseFragment(value.replaceAll('<![CDATA[', '').replaceAll(']]>', '')).text ?? '';
  return (parseFragment(decoded).text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _timeRange(String value) =>
    _cleanHtml(value).replaceAll(RegExp('[–—－]'), '-').replaceAll(RegExp(r'\s+'), '');
