import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/campus_user_agent.dart';
import 'package:techpie/services/oa_gym_local_client.dart';

import 'support/oa_school_client.dart';

const _cookies = 'shkjdx_session=synthetic-oa';
const _venue = '羽毛球场地 １ 号（东馆）';

void main() {
  test('reads the current user contact form with GET and never submits an edit', () async {
    final school = OaSchoolClient();
    final result = await OaGymLocalClient(school).request(
      'oa/gym/profile',
      {'id': 'caller-must-not-select-another-user'},
      cookies: '$_cookies; loginidweaver=fixture-current-user',
    );
    expect(result['data'], {'phone': '13900000000', 'email': 'student@shanghaitech.edu.cn'});
    expect(school.requests, hasLength(1));
    final request = school.requests.single;
    expect(request.method, 'GET');
    expect(request.url.host, 'oa.shanghaitech.edu.cn');
    expect(request.url.path, '/hrm/resource/HrmResourceContactEdit.jsp');
    expect(
      request.url.queryParameters,
      {'isfromtab': 'true', 'id': 'fixture-current-user', 'isView': '1'},
    );
    expect(request.body, isEmpty);
  });

  test('initializes the OA current user when only the session cookie is available', () async {
    final school = OaSchoolClient();
    final result = await OaGymLocalClient(school).request('oa/gym/profile', {}, cookies: _cookies);
    expect(result['data']['phone'], '13900000000');
    expect(school.requests, hasLength(2));
    expect(school.requests.first.url.path, '/workflow/request/AddRequest.jsp');
    expect(school.requests.every((r) => r.method == 'GET'), true);
    expect(school.requests.last.headers['Cookie'], contains('loginidweaver=fixture-current-user'));
  });

  test('does not read contacts from a form for a different OA user', () async {
    final school = OaSchoolClient()
      ..intercept = (_) async => OaSchoolClient.text(
            '<form id="resource"><input name="id" value="other-user">'
            '<input name="mobile" value="13900000000"></form>',
          );
    await expectLater(
      OaGymLocalClient(school).request(
        'oa/gym/profile',
        {},
        cookies: '$_cookies; loginidweaver=fixture-current-user',
      ),
      throwsA(isA<OaGymLocalException>().having((e) => e.message, 'message', contains('当前用户'))),
    );
    expect(school.requests, hasLength(1));
  });

  test('loads OA metadata locally and parses encoded XML without sending IDS credentials',
      () async {
    final school = OaSchoolClient();
    final result = await OaGymLocalClient(school).request('oa/gym/metadata', {}, cookies: _cookies);
    expect(result['data']['venues'][_venue], '13');
    expect(result['data']['venues'].containsKey('匹克球2号场地'), false);
    expect(result['data']['timeSlots'], {'18:00-19:00': '8'});
    expect(school.requests, hasLength(4));
    expect(school.requests.map((r) => r.url.path), [
      '/formmode/browser/CommonSingleBrowser.jsp',
      '/formmode/browser/CommonSingleBrowser.jsp',
      '/weaver/weaver.common.util.taglib.SplitPageXmlServlet',
      '/weaver/weaver.common.util.taglib.SplitPageXmlServlet',
    ]);
    expect(
      school.requests[0].url.queryParameters['currenttime'],
      school.requests[1].url.queryParameters['currenttime'],
    );
    for (final request in school.requests) {
      expect(request.url.host, 'oa.shanghaitech.edu.cn');
      expect(request.followRedirects, false);
      expect(request.headers['User-Agent'], CampusUserAgent.value);
      expect(request.headers['Cookie'], _cookies);
      expect(request.headers['Cookie'], isNot(contains('CASTGC')));
      expect(request.headers['Origin'], 'https://oa.shanghaitech.edu.cn');
    }
  });

  test('uses the OA tree picker and excludes the unused pickleball court', () async {
    final school = OaSchoolClient();
    final result = await OaGymLocalClient(school).request(
      'oa/gym/availability',
      {
        'sports': ['badminton', 'pickleball'],
        'date': '2026-11-03',
        'startSlot': 8,
        'endSlot': 8,
      },
      cookies: _cookies,
    );
    expect(result['data'][0]['availableCourts'], [1, 2]);
    expect(result['data'][1]['availableCourts'], [1]);
    expect(school.requests, hasLength(4));
    for (final request in school.requests) {
      expect(request.headers['Accept'], 'text/plain, */*; q=0.01');
      expect(request.headers['Content-Type'], 'application/x-www-form-urlencoded');
      expect(
          request.headers['Referer'], 'https://oa.shanghaitech.edu.cn/wui/main.jsp?templateId=1',);
      expect(request.headers.containsKey('Origin'), false);
    }
    expect(
      school.requests.last.url.queryParameters['dataconditionParam'],
      '_sfn_31901_sfv_2026-11-03_sfn_31902_sfv_8_sfn_32340_sfv_11',
    );
  });

  test('search preserves repeated condition fields and decodes the result rows', () async {
    final school = OaSchoolClient();
    final result = await _search(OaGymLocalClient(school));
    final form = Uri(query: school.requests.first.body).queryParametersAll;
    expect(school.requests.first.headers['Content-Type'], 'application/x-www-form-urlencoded');
    expect(school.requests.first.body, contains('%20'));
    expect(school.requests.first.body, isNot(contains('+')));
    expect(form['check_con'], ['31869', '31870', '31871']);
    expect(form['con31869_value'], ['13']);
    expect(form['con31871_value'], ['8']);
    expect(
      result['data'][0]['rows'],
      [
        ['2026-11-03', '已通过'],
      ],
    );
  });

  test('a mid-search 401 propagates even when an earlier time range succeeded', () async {
    final school = OaSchoolClient();
    var queries = 0;
    school.intercept = (request) async {
      if (request.url.path.contains('CustomSearch') && ++queries == 2) {
        return OaSchoolClient.text('expired', status: 401);
      }
      return null;
    };
    await expectLater(
      _search(OaGymLocalClient(school), ranges: ['', '18:00-19:00']),
      throwsA(isA<OaGymLocalException>().having((e) => e.sessionExpired, 'sessionExpired', true)),
    );
    expect(queries, 2);
  });

  for (final location in ['https://ids.shanghaitech.edu.cn/authserver/login', '/login/Login.jsp']) {
    test('does not follow an OA expiry redirect to $location', () async {
      final school = OaSchoolClient()
        ..intercept =
            (_) async => OaSchoolClient.text('', status: 302, headers: {'location': location});
      await expectLater(
        OaGymLocalClient(school).request('oa/gym/metadata', {}, cookies: _cookies),
        throwsA(isA<OaGymLocalException>().having((e) => e.sessionExpired, 'sessionExpired', true)),
      );
      expect(school.requests, hasLength(1));
    });
  }

  test('submits the physical court and actual OA user in a mocked booking only', () async {
    final school = OaSchoolClient();
    final result = await _book(OaGymLocalClient(school));
    expect(result['data']['success'], true);
    final form = Uri.splitQueryString(school.requests.last.body);
    expect(school.requests.last.headers['Content-Type'], 'application/x-www-form-urlencoded');
    expect(school.requests.last.headers.containsKey('Origin'), false);
    expect(school.requests.last.body, contains('field31888=Fixture%20User'));
    expect(form['field31876'], 'fixture-current-user');
    expect(form['field34283'], '20240001');
    expect(form['field31883'], '63_43');
    expect(form['field32340'], '11');
    expect(form['field31904'], '18:00');
    expect(form['field31905'], '19:00');
    expect(form['workflowid'], '14862');
    expect(form.containsKey('fixture-current-user_14862_addrequest_submit_token'), true);
    expect(school.requests.last.headers['Cookie'], contains('loginidweaver=fixture-current-user'));
  });

  test('does not substitute a hardcoded user or submit when OA omits the user cookie', () async {
    final school = OaSchoolClient()
      ..intercept = (_) async => OaSchoolClient.text('<html>workflow</html>');
    await expectLater(
      _book(OaGymLocalClient(school)),
      throwsA(
        isA<OaGymLocalException>().having((e) => e.message, 'message', contains('无法确认 OA 当前用户')),
      ),
    );
    expect(school.requests, hasLength(1));
    expect(school.requests.single.method, 'GET');
  });

  test('a booking timeout is not retried and asks the user to check existing reservations',
      () async {
    final school = OaSchoolClient()
      ..intercept = (request) async {
        if (request.url.path.endsWith('RequestOperation.jsp')) throw TimeoutException('synthetic');
        return null;
      };
    await expectLater(
      _book(OaGymLocalClient(school)),
      throwsA(
        isA<OaGymLocalException>()
            .having((e) => e.sessionExpired, 'sessionExpired', false)
            .having((e) => e.message, 'message', contains('确认结果，避免重复提交')),
      ),
    );
    expect(school.requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  test('follows OA table pagination instead of dropping records after the first ten', () async {
    final school = OaSchoolClient()
      ..intercept = (request) async {
        if (request.url.path.endsWith('SplitPageXmlServlet')) {
          final fields = Uri.splitQueryString(request.body);
          if (fields['tableString'] == 'AA') {
            final page = int.parse(fields['pageIndex']!);
            final count = page == 0 ? 10 : 1;
            return OaSchoolClient.text(
              '<rows>${List.generate(count, (i) => '<row><col>${page * 10 + i + 1}</col><col/><col showvalue="${page * 10 + i}:00-23:00"/></row>').join()}</rows>',
            );
          }
        }
        return null;
      };
    final result = await OaGymLocalClient(school).request('oa/gym/metadata', {}, cookies: _cookies);
    expect(result['data']['timeSlots'], hasLength(11));
    expect(
      school.requests
          .where((r) => r.body.contains('tableString=AA'))
          .map((r) => Uri.splitQueryString(r.body)['pageIndex']),
      ['0', '1'],
    );
  });
}

Future<Map<String, dynamic>> _search(
  OaGymLocalClient client, {
  List<String> ranges = const ['18:00-19:00'],
}) =>
    client.request(
      'oa/gym/search',
      {
        'startDate': '2026-11-03',
        'endDate': '2026-11-03',
        'venueNames': [_venue],
        'timeRanges': ranges,
      },
      cookies: _cookies,
      venues: {_venue: '13'},
      timeSlots: {'18:00-19:00': '8'},
    );

Future<Map<String, dynamic>> _book(OaGymLocalClient client) => client.request(
      'oa/gym/book',
      {
        'booking': {
          'sport': 'pickleball',
          'date': '2026-11-03',
          'timeSlot': 8,
          'courtNumber': 1,
          'playersCount': 2,
          'studentId': '20240001',
          'userName': 'Fixture User',
          'phone': '13800000000',
          'email': '',
        },
      },
      cookies: _cookies,
    );
