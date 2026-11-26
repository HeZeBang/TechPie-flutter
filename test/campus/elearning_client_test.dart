import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/feature.dart';
import 'package:techpie/pages/campus_session_handle.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/elearning_client.dart';
import 'package:techpie/services/session/cookie_provider.dart';
import 'package:techpie/services/session/session_node.dart';
import 'package:techpie/services/third_party_auth_service.dart';

import 'campus_fixture.dart';

const origin = 'https://elearning.shanghaitech.edu.cn:8443';

class _Node extends Fake implements SessionNode {
  @override
  CookieProvider get cookieProvider => const CookieProvider(
        cookies: 's=sample==; CASTGC=ids-only',
        domain: 'elearning.shanghaitech.edu.cn',
      );
}

class _Bindings extends Fake implements ThirdPartyAuthService {
  @override
  final SessionNode elearningNode = _Node();
}

void main() {
  test('selects course membership fields and preserves pagination', () async {
    final f = CampusFixture(
      origin,
      (r) => respond({
        'results': [
          {
            'courseId': 'c1',
            'privateField': 'omit',
            'availability': {'available': 'Yes', 'internal': 'omit'},
          }
        ],
        'paging': {'nextPage': '/next', 'extra': 'omit'},
      }),
    );
    final client = ElearningClient(f.session);
    expect(await client.getMyCourses('me', limit: 10, offset: 20), {
      'results': [
        {
          'courseId': 'c1',
          'availability': {'available': 'Yes'},
        }
      ],
      'paging': {'nextPage': '/next'},
    });
    expect(f.requests.single.uri.path, '/learn/api/public/v1/users/me/courses');
    expect(f.requests.single.uri.queryParameters, {'limit': '10', 'offset': '20'});
    expect(f.requests.single.headers['Cookie'], 'SESSION=v0');
  });

  test('401 renews once; 403 and 404 return distinct terminal errors', () async {
    var code = 401;
    final f = CampusFixture(
      origin,
      (r) => respond(
        {'id': 'me', 'email': 'omit'},
        status: code == 401 && r.headers['Cookie'] == 'SESSION=v1' ? 200 : code,
      ),
    );
    final c = ElearningClient(f.session);
    expect(await c.getMe(), {'id': 'me'});
    code = 403;
    await expectLater(c.getMe(), fails(CampusErrorKind.forbidden));
    code = 404;
    await expectLater(c.getCourse('missing'), fails(CampusErrorKind.notFound));
    expect(f.renewals, 1);
    expect(f.requests, hasLength(4));
  });

  test('downloads same-origin signed bytes and blocks cross-origin redirects', () async {
    String location = '/bbcswebdav/course/file?sig=test';
    final f = CampusFixture(
      origin,
      (r) => r.uri.path.endsWith('/download')
          ? respond(
              '',
              status: 302,
              headers: {
                'location': [location],
              },
            )
          : respond([0, 255, 8]),
    );
    final c = ElearningClient(f.session);
    expect(await c.downloadAttachment('c', 'item', 'file'), [0, 255, 8]);
    expect(
      f.requests.first.uri.path,
      '/learn/api/public/v1/courses/c/contents/item/attachments/file/download',
    );
    expect(f.requests.last.uri.queryParameters, {'sig': 'test'});
    location = 'https://elearning.shanghaitech.edu.cn/bbcswebdav/file';
    await expectLater(c.downloadAttachment('c', 'item', 'file'), fails(CampusErrorKind.rejected));
    expect(f.requests, hasLength(3));
    expect(f.requests.every((r) => r.uri.origin == origin), isTrue);
  });

  test('dispatches content, gradebook, group, term and HTML requests', () async {
    final f = CampusFixture(
      origin,
      (r) => r.uri.path.startsWith('/webapps/')
          ? respond('<p>Fine</p>')
          : respond({'results': <Object>[]}),
    );
    final c = ElearningClient(f.session);
    await c.getCourseContents('c', recursive: true);
    expect(f.requests.last.uri.queryParameters, {'limit': '100', 'recursive': 'true'});
    await c.getContentChildren('c', 'i');
    await c.getAttachments('c', 'i');
    await c.getGradebookColumns('c');
    await c.getMyGrades('c', 'u');
    await c.getCourseGroups('c');
    await c.getTerms();
    expect(
      await c.getWebHtml('/webapps/announcement', query: {'context': 'course'}),
      '<p>Fine</p>',
    );
    expect(f.requests.map((r) => r.uri.path.replaceFirst('/learn/api/public/v1/', '')), [
      'courses/c/contents',
      'courses/c/contents/i/children',
      'courses/c/contents/i/attachments',
      'courses/c/gradebook/columns',
      'courses/c/gradebook/users/u',
      'courses/c/groups',
      'terms',
      '/webapps/announcement',
    ]);
  });

  test('checks login and IDS binding before making any request', () async {
    final f = CampusFixture(origin, (r) => respond({}));
    final c = ElearningClient(f.session);
    f.identity = (user: null, ids: 'old');
    await expectLater(c.getMe(), fails(CampusErrorKind.notLoggedIn));
    f.identity = (user: 'me', ids: null);
    await expectLater(c.getMe(), fails(CampusErrorKind.idsNotBound));
    expect(f.requests, isEmpty);
  });

  test('WebView injects the elearning node cookie at its campus host', () {
    final handle = CampusSessionHandle.forFeature(_Bindings(), CookieType.elearning);
    final cookie = handle.cookies.single;
    expect(
      (cookie.name, cookie.value, cookie.domain, cookie.path),
      ('s', 'sample==', 'elearning.shanghaitech.edu.cn', '/'),
    );
  });

  test('allPages follows safe nextPage links and halts on loops or off-path URLs', () async {
    var mode = 'paged';
    final f = CampusFixture(origin, (r) {
      if (mode == 'offpath') {
        return respond({
          'results': [
            {'id': 't1'},
          ],
          'paging': {'nextPage': '/learn/api/public/v1/other'},
        });
      }
      if (mode == 'loop') {
        return respond({
          'results': [
            {'id': 't1'},
          ],
          'paging': {'nextPage': '/learn/api/public/v1/terms?offset=1&limit=1'},
        });
      }
      final offset = r.uri.queryParameters['offset'] ?? '0';
      if (offset == '0' || r.uri.queryParameters.isEmpty) {
        return respond({
          'results': [
            {'id': 't1', 'name': 'Autumn'},
          ],
          'paging': {'nextPage': '/learn/api/public/v1/terms?offset=1&limit=1'},
        });
      }
      return respond({
        'results': [
          {'id': 't2', 'name': 'Spring'},
        ],
      });
    });
    final c = ElearningClient(f.session);
    final all = await c.getTerms(limit: 1, allPages: true);
    expect(all['results'], [
      {'id': 't1', 'name': 'Autumn'},
      {'id': 't2', 'name': 'Spring'},
    ]);
    mode = 'loop';
    final looped = await c.getTerms(limit: 1, allPages: true);
    expect(looped['results'], hasLength(2));
    mode = 'offpath';
    await expectLater(c.getTerms(limit: 1, allPages: true), fails(CampusErrorKind.rejected));
  });
}
