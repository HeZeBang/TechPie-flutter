import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/student_allowance.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/student_allowance_client.dart';
import 'package:techpie/services/student_allowance_parser.dart';

import 'support/student_allowance_finance_fixture.dart';

typedef Finance = StudentAllowanceFinanceFixture;

void main() {
  final period = StudentAllowancePeriod(DateTime.utc(2026, 1, 9), DateTime.utc(2026, 2, 20));
  Future<StudentAllowanceReport> query(Finance finance, {DebugLogger? logger}) =>
      StudentAllowanceClient(http: finance.dio, logger: logger).query(
        idsCookies: 'CASTGC=synthetic-ids; IDS_SESSION=synthetic-ids-session',
        period: period,
        checkAccess: () {},
      );
  Matcher failsWith(StudentAllowanceFailure kind) => throwsA(
        isA<StudentAllowanceException>().having((e) => e.failure, 'failure', kind),
      );

  test('starts at portal login and keeps finance cookies scoped', () async {
    const expectedFlow = [
      (443, Finance.portalLogin),
      (8099, Finance.externalLogin),
      (443, Finance.idsLogin),
      (8099, Finance.externalLogin),
      (8099, Finance.externalLogin),
      (443, Finance.portalLogin),
      (443, Finance.portalHome),
      (8088, Finance.queryPage),
      (8088, Finance.queryPath),
    ];
    final finance = Finance();
    final client = StudentAllowanceClient(http: finance.dio);
    Future<StudentAllowanceReport> runQuery() => client.query(
          idsCookies: 'CASTGC=synthetic-ids; IDS_SESSION=synthetic-ids-session',
          period: period,
          checkAccess: () {},
        );
    await runQuery();
    final report = await runQuery();
    expect(finance.requests, hasLength(2 * expectedFlow.length));
    for (final requests in [
      finance.requests.take(expectedFlow.length).toList(),
      finance.requests.skip(expectedFlow.length).toList(),
    ]) {
      expect(requests.map((r) => (r.uri.port, r.uri.path)), expectedFlow);
      expect(requests.every((r) => !r.followRedirects && r.uri.scheme == 'https'), isTrue);
      expect(requests.first.headers['Cookie'], isEmpty); // Fresh jar on every query.
      final ids = requests[2];
      expect(ids.uri.host, Finance.idsHost);
      expect(ids.uri.queryParameters, {
        'service': '${Finance.callbackOrigin}${Finance.externalLogin}',
      });
      expect(ids.headers['Cookie'], 'CASTGC=synthetic-ids; IDS_SESSION=synthetic-ids-session');
      expect(requests[3].uri.queryParameters, {'ticket': Finance.ticket});
      expect(requests[3].headers['Cookie'], contains('ASP.NET_SessionId='));
      expect(requests[4].uri.hasQuery, isFalse);
      expect(requests[4].headers['Cookie'], contains('.ASPXAUTH='));
      expect(requests[4].headers['Cookie'], isNot(contains('SFP_Verify_Cookie=')));
      expect(requests[5].headers['Cookie'], contains('SFP_Verify_Cookie='));
      for (final request in requests.where((r) => r.uri.host == Finance.financeHost)) {
        expect(request.headers['Cookie'], isNot(contains('CASTGC')));
        expect(request.headers['Cookie'], isNot(contains('IDS_ONLY')));
        expect(request.headers['Cookie'], isNot(contains('IDS_SESSION')));
      }
      expect(requests[7].uri.queryParameters, {'ConfigID': '22'});
      final post = requests.last;
      expect(post.method, 'POST');
      expect(post.headers['Cookie'], contains('ASP.NET_SessionId='));
      expect(post.headers['Cookie'], contains('.ASPXAUTH='));
      expect(post.headers['Cookie'], contains('SFP_Verify_Cookie='));
      expect(post.headers['Cookie'], isNot(contains('CALLBACK_ONLY=')));
      expect(post.headers['Origin'], Finance.queryOrigin);
      expect(post.headers['Referer'], '${Finance.queryOrigin}${Finance.queryPage}?ConfigID=22');
      expect(post.headers['Content-Type'], 'application/x-www-form-urlencoded; charset=UTF-8');
      expect(post.headers['X-Requested-With'], 'XMLHttpRequest');
      expect(Uri.splitQueryString(post.data as String), {
        'SearchYearMonthB': '2026-01',
        'SearchYearMonthE': '2026-02',
        'ConfigID': '22',
      });
    }
    expect(report.months.map((e) => e.month), [DateTime.utc(2026, 2), DateTime.utc(2026, 1)]);
    expect(report.months.first.netFen, 123925);
    expect(report.total?.netFen, 142925);
  });

  test('accepts a session cookie issued after the initial portal redirect', () async {
    final finance = Finance(sessionAtCasEntry: true);
    expect((await query(finance)).months, isNotEmpty);
    final casEntry = finance.requests[1];
    expect(casEntry.uri.path, Finance.externalLogin);
    expect(casEntry.headers['Cookie'], isEmpty);
    expect(finance.requests[3].headers['Cookie'], contains('ASP.NET_SessionId='));
  });

  test('stops before POST if the finance session cookie is no longer usable', () async {
    final logger = DebugLogger()..enabled = true;
    final finance = Finance()
      ..intercept = (request) => request.uri.path == Finance.queryPage
          ? Finance.response(
              request,
              setCookie: ['ASP.NET_SessionId=; Path=/; Max-Age=0'],
            )
          : null;
    await expectLater(
      query(finance, logger: logger),
      failsWith(StudentAllowanceFailure.financeSession),
    );
    expect(finance.requests.last.uri.path, Finance.queryPage);
    expect(logger.entries.last.url, 'student-allowance/queryPost/missingAspNetSession');
  });

  test('rejects a redirect to the right host but the wrong role or port', () async {
    final finance = Finance()
      ..intercept = (request) => request.uri.path == Finance.portalLogin
          ? Finance.response(
              request,
              status: 302,
              location: '${Finance.queryOrigin}${Finance.externalLogin}',
            )
          : null;
    await expectLater(query(finance), failsWith(StudentAllowanceFailure.financeSession));
    expect(finance.requests, hasLength(1));
  });

  test('validates the CAS service before sending the IDS credential', () async {
    final finance = Finance()
      ..intercept = (request) => request.uri.path == Finance.externalLogin
          ? Finance.response(
              request,
              status: 302,
              location:
                  'https://${Finance.idsHost}${Finance.idsLogin}?service=${Finance.portalOrigin}${Finance.externalLogin}',
            )
          : null;
    await expectLater(query(finance), failsWith(StudentAllowanceFailure.financeSession));
    expect(finance.requests.map((r) => r.uri.host), everyElement(Finance.financeHost));
    expect(finance.requests, hasLength(2));
  });

  for (final location in [
    'https://untrusted.invalid:8099${Finance.externalLogin}?ticket=${Finance.ticket}',
    'http://${Finance.financeHost}:8099${Finance.externalLogin}?ticket=${Finance.ticket}',
    '${Finance.portalOrigin}${Finance.externalLogin}?ticket=${Finance.ticket}',
    '${Finance.queryOrigin}${Finance.externalLogin}?ticket=${Finance.ticket}',
    '${Finance.callbackOrigin}/different?ticket=${Finance.ticket}',
    '${Finance.callbackOrigin}${Finance.externalLogin}?ticket=${Finance.ticket}&ticket=ST-other',
    '${Finance.callbackOrigin}${Finance.externalLogin}?ticket=${Finance.ticket}&next=synthetic',
    '${Finance.callbackOrigin}${Finance.externalLogin}?ticket=${Finance.ticket}#synthetic',
    'javascript:synthetic()',
  ]) {
    test('rejects an unexpected CAS callback: $location', () async {
      final finance = Finance()
        ..intercept = (request) => request.uri.host == Finance.idsHost
            ? Finance.response(request, status: 302, location: location)
            : null;
      await expectLater(query(finance), failsWith(StudentAllowanceFailure.unexpectedResponse));
      expect(finance.requests, hasLength(3));
    });
  }

  test('a return to IDS at the finance callback does not transfer finance cookies', () async {
    final finance = Finance()
      ..intercept = (request) => request.uri.queryParameters.containsKey('ticket')
          ? Finance.response(
              request,
              status: 302,
              location: 'https://${Finance.idsHost}/authserver/login',
              setCookie: ['.ASPXAUTH=synthetic-auth; Domain=shanghaitech.edu.cn; Path=/'],
            )
          : null;
    await expectLater(query(finance), failsWith(StudentAllowanceFailure.financeSession));
    expect(finance.requests, hasLength(4));
  });

  test('requires forms authentication from the ticket callback', () async {
    final logger = DebugLogger()..enabled = true;
    final finance = Finance()
      ..intercept = (request) => request.uri.queryParameters.containsKey('ticket')
          ? Finance.response(request, status: 302, location: Finance.externalLogin)
          : null;
    await expectLater(
      query(finance, logger: logger),
      failsWith(StudentAllowanceFailure.financeSession),
    );
    expect(finance.requests, hasLength(4));
    expect(logger.entries.last.url, 'student-allowance/ticketCallback/missingFormsAuth');
  });

  test('requires the verification cookie from the ticketless redirect', () async {
    final logger = DebugLogger()..enabled = true;
    final finance = Finance()
      ..intercept = (request) => request.uri.path == Finance.externalLogin &&
              !request.uri.hasQuery &&
              (request.headers['Cookie'] as String).contains('.ASPXAUTH=')
          ? Finance.response(
              request,
              status: 302,
              location: '${Finance.portalOrigin}${Finance.portalLogin}',
            )
          : null;
    await expectLater(
      query(finance, logger: logger),
      failsWith(StudentAllowanceFailure.financeSession),
    );
    expect(finance.requests, hasLength(5));
    expect(logger.entries.last.url, 'student-allowance/ticketlessCallback/missingVerification');
  });

  test('a finance POST redirect is not followed or reported as an empty table', () async {
    final finance = Finance()
      ..intercept = (request) => request.uri.path == Finance.queryPath
          ? Finance.response(request, status: 302, location: Finance.externalLogin)
          : null;
    await expectLater(query(finance), failsWith(StudentAllowanceFailure.financeSession));
    expect(finance.requests, hasLength(9));
  });

  test('debug mode records only fixed stage labels and HTTP metadata', () async {
    final logger = DebugLogger();
    await query(Finance(), logger: logger);
    expect(logger.entries, isEmpty);

    logger.enabled = true;
    await query(Finance(), logger: logger);
    expect(logger.entries.map((entry) => (entry.url, entry.statusCode)), [
      ('student-allowance/portalLogin', 302),
      ('student-allowance/casEntry', 302),
      ('student-allowance/idsTicket', 302),
      ('student-allowance/ticketCallback', 302),
      ('student-allowance/ticketlessCallback', 302),
      ('student-allowance/portalReturn', 302),
      ('student-allowance/portalHome', 200),
      ('student-allowance/queryPage', 200),
      ('student-allowance/queryPost', 200),
    ]);
    for (final entry in logger.entries) {
      expect(entry.tag, 'StudentAllowance');
      expect(entry.requestBody, isNull);
      expect(entry.responseBody, isNull);
      expect(entry.error, isNull);
    }
    expect(logger.entries.last.method, 'POST');
  });

  test('transport diagnostics omit the exception and ticket URL', () async {
    final logger = DebugLogger()..enabled = true;
    final finance = Finance()
      ..intercept = (request) {
        if (request.uri.queryParameters['ticket'] == Finance.ticket) {
          throw DioException(
            requestOptions: request,
            message: 'SYNTHETIC-SENSITIVE TRANSPORT ERROR',
          );
        }
        return null;
      };
    await expectLater(query(finance, logger: logger), failsWith(StudentAllowanceFailure.network));
    final last = logger.entries.last;
    expect(last.url, 'student-allowance/ticketCallback/network');
    expect(last.method, 'CHECK');
    expect(last.statusCode, isNull);
    expect(last.error, isNull);
  });

  test('recognizes IDS login HTML while keeping the response out of the error', () async {
    final finance = Finance()
      ..intercept = (request) => request.uri.host == Finance.idsHost
          ? Finance.response(
              request,
              body: '<form><input name="execution" value="synthetic-secret"></form>',
            )
          : null;
    await expectLater(query(finance), failsWith(StudentAllowanceFailure.idsSession));
    expect(finance.requests, hasLength(3));
  });

  test('exact values, dynamic benefit columns and blank cells are preserved', () {
    final report = parseStudentAllowanceReport(allowanceTable);
    final latest = report.months.first;
    expect(latest.categories.map((c) => c.label), ['合成助研津贴', '合成奖学金']);
    expect(latest.categories.first.grossFen, 125025);
    expect(latest.categories.last.grossFen, -1000);
    expect(latest.categories.last.netFen, -1000);
    expect(latest.deductionsFen, 0);
    expect(report.months.last.categories.last.grossFen, isNull);
    expect(report.months.last.categories.last.netFen, isNull);
    expect(report.total?.month, isNull);
    expect(report.total?.grossFen, 144025);
    expect(report.total?.deductionsFen, 200);
    expect(report.total?.taxFen, 900);
  });

  test('explicitly empty reports are distinct from an unexpected layout', () async {
    final empty = await query(Finance()..html = '<div>没有符合条件的数据。</div>');
    expect(empty.months, isEmpty);
    expect(empty.total, isNull);
    await expectLater(
      query(Finance()..html = '<div>维护中 SYNTHETIC-STUDENT-NAME</div>'),
      failsWith(StudentAllowanceFailure.unexpectedResponse),
    );
    for (final invalid in [
      allowanceTable.replaceFirst('<th>扣款</th><th>扣税</th>', '<th>扣税</th><th>扣款</th>'),
      allowanceTable.replaceFirst('2026年02月', '2026年13月'),
      allowanceTable.replaceFirst('1,250.25', 'SYNTHETIC-STUDENT-ID'),
    ]) {
      expect(
        () => parseStudentAllowanceReport(invalid),
        throwsA(isA<FormatException>().having((e) => e.source, 'source', isNull)),
      );
    }
  });

  test('range rejects reversed months but permits the same month', () {
    expect(
      () => StudentAllowancePeriod(DateTime.utc(2026, 5), DateTime.utc(2026, 4)),
      throwsArgumentError,
    );
    final same = StudentAllowancePeriod(DateTime.utc(2026, 5, 31), DateTime.utc(2026, 5, 1));
    expect(same.startParameter, '2026-05');
    expect(same.endParameter, '2026-05');
  });
}
