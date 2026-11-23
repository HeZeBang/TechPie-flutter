import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/student_allowance.dart';
import 'package:techpie/services/student_allowance_client.dart';
import 'package:techpie/services/student_allowance_parser.dart';

import 'support/student_allowance_finance_fixture.dart';

typedef Finance = StudentAllowanceFinanceFixture;

void main() {
  final period = StudentAllowancePeriod(DateTime.utc(2026, 1, 9), DateTime.utc(2026, 2, 20));
  Future<StudentAllowanceReport> query(Finance finance) =>
      StudentAllowanceClient(http: finance.dio).query(
        idsCookies: 'CASTGC=synthetic-ids; IDS_SESSION=synthetic-ids-session',
        period: period,
        checkAccess: () {},
      );
  Matcher failsWith(StudentAllowanceFailure kind) => throwsA(
        isA<StudentAllowanceException>().having((e) => e.failure, 'failure', kind),
      );

  test('CAS hands off only the ticket; finance cookies and form are scoped', () async {
    final finance = Finance();
    await query(finance);
    final report = await query(finance);
    for (final requests in [finance.requests.take(6).toList(), finance.requests.skip(6).toList()]) {
      expect(requests.map((r) => r.uri.path), [
        Finance.externalLogin,
        '/authserver/login',
        Finance.externalLogin,
        Finance.externalLogin,
        Finance.queryPage,
        Finance.queryPath,
      ]);
      expect(requests.every((r) => !r.followRedirects && r.uri.scheme == 'https'), isTrue);
      expect(requests.first.headers['Cookie'], isEmpty); // Fresh jar on every query.
      expect(requests[1].uri.host, Finance.idsHost);
      expect(requests[1].uri.queryParameters, {
        'service': 'https://${Finance.financeHost}${Finance.externalLogin}',
      });
      expect(
        requests[1].headers['Cookie'],
        'CASTGC=synthetic-ids; IDS_SESSION=synthetic-ids-session',
      );
      expect(requests[2].uri.queryParameters, {'ticket': Finance.ticket});
      expect(requests[2].headers['Cookie'], contains('ASP.NET_SessionId='));
      expect(requests[3].uri.hasQuery, isFalse);
      expect(requests[3].headers['Cookie'], contains('.ASPXAUTH='));
      for (final request in requests.where((r) => r.uri.host == Finance.financeHost)) {
        expect(request.headers['Cookie'], isNot(contains('CASTGC')));
        expect(request.headers['Cookie'], isNot(contains('IDS_ONLY')));
        expect(request.headers['Cookie'], isNot(contains('IDS_SESSION')));
      }
      final post = requests.last;
      expect(post.method, 'POST');
      expect(post.headers['Cookie'], contains('SFP_Verify_Cookie='));
      expect(post.headers['Cookie'], isNot(contains('CALLBACK_ONLY=')));
      expect(post.headers['Origin'], 'https://${Finance.financeHost}');
      expect(
        post.headers['Referer'],
        'https://${Finance.financeHost}${Finance.queryPage}?ConfigID=22',
      );
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

  for (final location in [
    'https://untrusted.invalid${Finance.externalLogin}?ticket=${Finance.ticket}',
    'http://${Finance.financeHost}${Finance.externalLogin}?ticket=${Finance.ticket}',
    'https://${Finance.financeHost}:8443${Finance.externalLogin}?ticket=${Finance.ticket}',
    'https://${Finance.financeHost}/different?ticket=${Finance.ticket}',
    'https://${Finance.financeHost}${Finance.externalLogin}?ticket=${Finance.ticket}&ticket=ST-other',
    'javascript:synthetic()',
  ]) {
    test('rejects an unexpected CAS callback: $location', () async {
      final finance = Finance()
        ..intercept = (request) => request.uri.host == Finance.idsHost
            ? Finance.response(request, status: 302, location: location)
            : null;
      await expectLater(query(finance), failsWith(StudentAllowanceFailure.unexpectedResponse));
      expect(finance.requests, hasLength(2));
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
    expect(finance.requests, hasLength(3));
  });

  test('does not POST after ticket handoff if forms authentication was not set', () async {
    final finance = Finance()
      ..intercept = (request) => request.uri.queryParameters.containsKey('ticket')
          ? Finance.response(request, status: 302, location: Finance.externalLogin)
          : request.uri.path == Finance.externalLogin && request.headers['Cookie'] != ''
              ? Finance.response(request)
              : null;
    await expectLater(query(finance), failsWith(StudentAllowanceFailure.financeSession));
    expect(finance.requests.map((r) => r.uri.path), isNot(contains(Finance.queryPath)));
  });

  test('a finance POST redirect is not followed or reported as an empty table', () async {
    final finance = Finance()
      ..intercept = (request) => request.uri.path == Finance.queryPath
          ? Finance.response(request, status: 302, location: Finance.externalLogin)
          : null;
    await expectLater(query(finance), failsWith(StudentAllowanceFailure.financeSession));
    expect(finance.requests, hasLength(6));
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
    expect(finance.requests, hasLength(2));
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
