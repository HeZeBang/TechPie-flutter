import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:techpie/models/campus_identity.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/graduate_schedule_client.dart';
import 'package:techpie/services/http_client.dart';

void main() {
  test('IDS categories distinguish current students and reject ambiguous or former identities', () {
    for (final role in ['学生/硕士生', '学生/博士生', '学生/研究生']) {
      expect(CampusIdentity.fromCategory(role).kind, CampusStudentKind.graduate);
    }
    expect(CampusIdentity.fromCategory('学生/本科生').kind, CampusStudentKind.undergraduate);
    for (final role in ['', '学生', '本科/硕士', '硕士校友', '毕业研究生', '教职工/博士']) {
      expect(CampusIdentity.fromCategory(role).kind, CampusStudentKind.unknown);
    }
  });

  test('associated-account roles never identify a different or disabled principal', () {
    const profile = <String, dynamic>{
      'code': '0',
      'datas': {'uid': '20260001'},
    };
    final identity = CampusIdentity.fromIds(
      profile,
      '20260001',
      associatedAccounts: {
        'bindingUserList': [
          {'userId': '20260002', 'categoryName': '学生/硕士生', 'accountStatus': '账号正常'},
          {'userId': '20260001', 'categoryName': '学生/本科生', 'accountStatus': '账号正常'},
        ],
      },
    );
    expect(identity.kind, CampusStudentKind.undergraduate);
    final disabled = CampusIdentity.fromIds(
      profile,
      '20260001',
      associatedAccounts: {
        'bindingUserList': [
          {'userId': '20260001', 'categoryName': '学生/硕士生', 'accountStatus': '已禁用'},
        ],
      },
    );
    expect(disabled.kind, CampusStudentKind.unknown);
    expect(
      () => CampusIdentity.fromIds(profile, '20260002'),
      throwsA(isA<CampusIdentityConflict>()),
    );
  });

  test('editable profile data without uid is a schema failure, not an account mismatch', () {
    expect(
      () => CampusIdentity.fromIds(
        {
          'code': '0',
          'datas': {'nickName': 'example', 'userAttributes': <Object>[]},
        },
        '20260001',
      ),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('缺少 uid'))),
    );
    expect(
      CampusIdentity.fromIds(
        {
          'code': '0',
          'datas': {'uid': '20260001', 'categoryName': '学生/硕士生'},
        },
        '',
      ).kind,
      CampusStudentKind.graduate,
    );
  });

  test('IDS uses its official read-only POST list with reference cookies and redacted diagnostics',
      () async {
    final requests = <http.Request>[];
    final logger = DebugLogger()..enabled = true;
    final client = GraduateScheduleClient(
      LoggingHttpClient(
        logger,
        inner: MockClient((request) async {
          requests.add(request);
          expect(request.url.host, GraduateScheduleClient.idsHost);
          expect(request.headers['cookie'], contains('CASTGC=private-tgc'));
          if (request.url.path.endsWith('index.html')) {
            return http.Response(
              '<html>IDS</html>',
              200,
              headers: {
                'set-cookie': 'REFERERCE_TOKEN=private-reference; Path=/personalInfo; Secure, '
                    'XSRF-TOKEN=private%3Acsrf; Path=/personalInfo; Secure',
              },
            );
          }
          expect(request.headers['refererToken'], 'private-reference');
          expect(request.headers['X-XSRF-TOKEN'], 'private:csrf');
          expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
          if (request.url.path.endsWith('getUserConf')) {
            expect(request.method, 'POST');
            return http.Response(
              jsonEncode({
                'code': '0',
                'datas': {'uid': '20260001', 'cn': 'PRIVATE-NAME'},
              }),
              200,
            );
          }
          expect(request.url.path, '/personalInfo/accountRelation/bindingUserList');
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), isEmpty);
          return http.Response(
            jsonEncode({
              'bindingUserList': [
                {'userId': '20260002', 'categoryName': '学生/本科生', 'accountStatus': '账号正常'},
                {'userId': '20260001', 'categoryName': '学生/硕士生', 'accountStatus': '账号正常'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
      'private-tgc',
    );
    expect((await client.identity('20260001')).kind, CampusStudentKind.graduate);
    expect(requests, hasLength(3));
    expect(jsonDecode(logger.entries.last.responseBody!)['bindingUserListCount'], 2);
    final logs =
        logger.entries.map((e) => '${e.url} ${e.requestBody} ${e.responseBody} ${e.error}').join();
    for (final private in [
      '20260001',
      '20260002',
      'PRIVATE-NAME',
      'private-tgc',
      'private-reference',
      'private:csrf',
    ]) {
      expect(logs, isNot(contains(private)));
    }
  });

  test('the IDS POST entry rejects settings endpoints before any request is sent', () async {
    var sent = 0;
    final client = LoggingHttpClient(
      DebugLogger(),
      inner: MockClient((request) async {
        sent++;
        return http.Response('', 200);
      }),
    );
    for (final target in [
      'https://ids.shanghaitech.edu.cn/personalInfo/accountRelation/setDefaultAccount',
      'https://ids.shanghaitech.edu.cn:444/personalInfo/accountRelation/bindingUserList',
      'https://unrelated.example/personalInfo/accountRelation/bindingUserList',
    ]) {
      expect(() => client.readIdsQuery(Uri.parse(target)), throwsFormatException);
    }
    expect(sent, 0);
  });
}
