import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

// Entirely synthetic. The layout mirrors the two-level header, metadata row,
// detail-link cells and the mismatched colspan of the captured report.
const allowanceTable = '''
<div><table>
<tr><td colspan="2">编号：SYNTHETIC-STUDENT-ID</td>
<td colspan="2">姓名：SYNTHETIC-STUDENT-NAME</td><td colspan="5">合成账号</td></tr>
<tr><th rowspan="2">发放月份</th><th colspan="3">合成助研津贴</th>
<th colspan="3">合成奖学金</th><th colspan="3">合计</th></tr>
<tr><th>应发</th><th>实发</th><th>&nbsp;</th><th>应发</th><th>实发</th><th></th>
<th>应发</th><th>扣款</th><th>扣税</th><th>实发</th></tr>
<tr><td>2026年01月</td><td>200.00</td><td>190.00</td>
<td><a href="#" onclick="syntheticDetail('SYNTHETIC-STUDENT-ID')">明细</a></td>
<td></td><td>—</td><td></td><td>200.00</td><td>2.00</td><td>8.00</td><td>190.00</td></tr>
<tr><td>2026年02月</td><td>1,250.25</td><td>1,249.25</td><td>明细</td>
<td>−10.00</td><td>-10.0</td><td>明细</td><td>1240.25</td><td>0</td><td>1.00</td><td>1239.25</td></tr>
<tr><th>合计</th><td>1450.25</td><td>1439.25</td><td>明细</td><td>-10.00</td>
<td>-10.00</td><td>明细</td><td>1440.25</td><td>2.00</td><td>9.00</td><td>1429.25</td></tr>
</table></div><script>syntheticDetail('SYNTHETIC-STUDENT-ID');</script>
''';

class StudentAllowanceFinanceFixture {
  StudentAllowanceFinanceFixture() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add(options);
          final override = await intercept?.call(options);
          handler.resolve(override ?? _respond(options));
        },
      ),
    );
  }

  static const idsHost = 'ids.shanghaitech.edu.cn';
  static const financeHost = 'finance.shanghaitech.edu.cn';
  static const externalLogin = '/ExternalLogin.aspx';
  static const queryPage = '/SalaryQuerySalary/SalayQuerySalary';
  static const queryPath = '/SalaryQuerySalary/CtrlSQSalaryInfoSKD';
  static const ticket = 'ST-synthetic-ticket';

  final dio = Dio();
  final requests = <RequestOptions>[];
  FutureOr<Response<List<int>>?> Function(RequestOptions)? intercept;
  String html = allowanceTable;

  static Response<List<int>> response(
    RequestOptions request, {
    int status = 200,
    String body = '',
    String? location,
    List<String> setCookie = const [],
  }) =>
      Response(
        requestOptions: request,
        statusCode: status,
        data: utf8.encode(body),
        headers: Headers.fromMap({
          'content-type': ['text/html; charset=utf-8'],
          if (location != null) 'location': [location],
          if (setCookie.isNotEmpty) 'set-cookie': setCookie,
        }),
      );

  Response<List<int>> _respond(RequestOptions request) {
    final url = request.uri;
    final cookie = request.headers['cookie']?.toString() ?? '';
    if (url.host == idsHost && url.path == '/authserver/login') {
      if (!cookie.contains('CASTGC=')) {
        return response(request, body: '<form><input name="execution"></form>');
      }
      return response(
        request,
        status: 302,
        location: 'https://$financeHost$externalLogin?ticket=$ticket',
        setCookie: ['IDS_ONLY=never-finance; Domain=shanghaitech.edu.cn; Path=/'],
      );
    }
    if (url.host == financeHost) {
      switch (url.path) {
        case externalLogin when url.queryParameters['ticket'] == ticket:
          if (!cookie.contains('ASP.NET_SessionId=synthetic-finance-session')) {
            return response(request, status: 401);
          }
          return response(
            request,
            status: 302,
            location: 'https://$financeHost$externalLogin',
            setCookie: ['.ASPXAUTH=synthetic-forms-auth; Path=/; HttpOnly'],
          );
        case externalLogin when cookie.contains('.ASPXAUTH='):
          return response(request);
        case externalLogin:
          return response(
            request,
            status: 302,
            location: 'https://$idsHost/authserver/login',
            setCookie: [
              'ASP.NET_SessionId=synthetic-finance-session; Path=/; HttpOnly',
              'CALLBACK_ONLY=synthetic; Path=$externalLogin',
            ],
          );
        case queryPage when cookie.contains('.ASPXAUTH='):
          return response(
            request,
            setCookie: ['SFP_Verify_Cookie=synthetic-verification; Path=/SalaryQuerySalary'],
          );
        case queryPath when cookie.contains('.ASPXAUTH=') && cookie.contains('SFP_Verify_Cookie='):
          return response(request, body: html);
      }
    }
    return response(request, status: 404);
  }
}
