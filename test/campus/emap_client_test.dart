import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/emap_client.dart';

import 'campus_fixture.dart';

const origin = 'https://egate.shanghaitech.edu.cn';
const config = '/xsfw/sys/funauthapp/api/getAppConfig/demo-42.do';
const page = {
  'code': '0',
  'datas': {
    'rowsModel': {
      'totalSize': -1,
      'rows': [
        {'title': 'example'},
      ],
    },
  },
};
Future<EmapPageResult> query(EmapClient c) => c.queryModel(
      app: 'demo',
      appId: '42',
      module: 'list',
      model: 'rowsModel',
      querySetting: [
        {'name': 'year', 'value': 2026},
      ],
    );

void main() {
  test('shares bootstrap, retains scoped cookies and reads unknown totals', () async {
    final f = CampusFixture(
      origin,
      (r) => r.uri.path == config
          ? respond(
              {},
              headers: {
                'set-cookie': ['_WEU=fresh; Path=/xsfw; Secure'],
              },
            )
          : respond(page),
    );
    final c = EmapClient(f.session);
    final results = await Future.wait([query(c), query(c)]);
    expect(results.first.totalSize, -1);
    expect(results.first.rows.single, {'title': 'example'});
    expect(
      f.requests.map((r) => r.uri.path),
      [config, ...List.filled(2, '/xsfw/sys/demo/modules/list/rowsModel.do')],
    );
    expect(f.requests.first.headers['Referer'], '$origin/xsfw/sys/demo/*default/index.do');
    expect(f.requests.first.headers['X-Requested-With'], 'XMLHttpRequest');
    final last = f.requests.last;
    expect(last.method, 'POST');
    expect(last.headers['Cookie'], contains('_WEU=fresh'));
    expect(last.headers['Cookie'], isNot(contains('CASTGC')));
    expect(last.contentType, Headers.formUrlEncodedContentType);
    expect(last.data, {
      'pageSize': '20',
      'pageNumber': '1',
      'querySetting': jsonEncode([
        {'name': 'year', 'value': 2026},
      ]),
    });
    f.identity = (user: 'other', ids: 'other');
    await query(c);
    expect(f.requests.where((r) => r.uri.path == config), hasLength(2));
    expect(f.requests[3].headers['Cookie'], isNot(contains('_WEU')));
  });

  test('403 reboots app once and preserves the failure of a second action', () async {
    var count = 0;
    final f = CampusFixture(
      origin,
      (r) => r.uri.path == config ? respond({}) : respond(page, status: ++count <= 3 ? 403 : 200),
    );
    final c = EmapClient(f.session);
    await expectLater(query(c), fails(CampusErrorKind.forbidden));
    expect(f.renewals, 0);
    expect((await query(c)).totalSize, -1);
    expect(f.requests.where((r) => r.uri.path == config), hasLength(3));
  });

  test('200 login HTML renews the session and bootstraps with the new cookie', () async {
    final f = CampusFixture(
      origin,
      (r) => r.uri.path == config
          ? respond({})
          : (r.headers['Cookie'] as String).contains('v0')
              ? respond('  <!DOCTYPE html>sign in')
              : respond(page),
    );
    await query(EmapClient(f.session));
    expect(f.renewals, 1);
    expect(f.requests.map((r) => r.uri.path).where((p) => p == config), hasLength(2));
  });

  test('commonCall encodes action and batch routes; errors omit response data', () async {
    var accepted = true;
    final f = CampusFixture(
      origin,
      (r) => r.uri.path == config
          ? respond({})
          : respond({
              'resultCode': accepted ? '00000' : 'bad',
              'message': 'private fixture',
              'data': [1],
            }),
    );
    final c = EmapClient(f.session);
    Future<Map<String, dynamic>> run(bool batch) => c.commonCall(
          app: 'demo',
          appId: '42',
          actionName: 'records',
          actionType: 'model',
          dataModelAction: 'list',
          requestParams: {'key': 3},
          batch: batch,
        );
    expect((await run(false))['data'], [1]);
    expect(f.requests.last.uri.path, endsWith('/commoncall/call/records-model-list.do'));
    expect(f.requests.last.data, {'requestParams': '{"key":3}'});
    accepted = false;
    final lines = <String>[];
    await runZoned(
      () => expectLater(
        run(true),
        throwsA(
          isA<CampusRequestException>()
              .having((e) => e.message, 'message', isNot(contains('private fixture'))),
        ),
      ),
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => lines.add(line)),
    );
    expect(lines.join(), isNot(contains('private fixture')));
    expect(f.requests.last.uri.path, endsWith('/callBatch/records-model-list.do'));
  });

  test('uploads multipart and downloads the original bytes', () async {
    final f = CampusFixture(
      origin,
      (r) => r.method == 'POST' ? respond({'ok': true}) : respond([0, 128, 255]),
    );
    final c = EmapClient(f.session);
    await c.uploadTempFile(scope: 'demo', token: 'file', bytes: [2, 3], filename: 'test.pdf');
    final form = f.requests.single.data as FormData;
    expect(form.fields.single.value, 'imexport');
    expect(form.files.single.key, 'bhFile');
    expect(form.files.single.value.filename, 'test.pdf');
    expect(await c.downloadFileByToken('file'), [0, 128, 255]);
  });
}
