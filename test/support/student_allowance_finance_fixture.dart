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
  StudentAllowanceFinanceFixture({this.sessionAtCasEntry = false}) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add(options);
          try {
            final override = await intercept?.call(options);
            handler.resolve(override ?? _respond(options));
          } on DioException catch (error) {
            handler.reject(error);
          }
        },
      ),
    );
  }

  static const idsHost = 'ids.shanghaitech.edu.cn';
  static const financeHost = 'finance.shanghaitech.edu.cn';
  static const portalOrigin = 'https://$financeHost';
  static const callbackOrigin = '$portalOrigin:8099';
  static const queryOrigin = '$portalOrigin:8088';
  static const portalHome = '/Home/Index';
  static const portalLogin = '/Home/IndexLogin';
  static const idsLogin = '/authserver/login';
  static const externalLogin = '/ExternalLogin.aspx';
  static const queryPage = '/SalaryQuerySalary/SalayQuerySalary';
  static const queryPath = '/SalaryQuerySalary/CtrlSQSalaryInfoSKD';
  static const ticket = 'ST-synthetic-ticket';
  static const _sessionCookie = 'ASP.NET_SessionId=synthetic-finance-session; Path=/; HttpOnly';

  final bool sessionAtCasEntry;
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
    const callback = '$callbackOrigin$externalLogin';
    final ids = Uri.https(idsHost, idsLogin, {'service': callback});
    if (url == ids) {
      if (!cookie.contains('CASTGC=')) {
        return response(request, body: '<form><input name="execution"></form>');
      }
      return response(
        request,
        status: 302,
        location: '$callback?ticket=$ticket',
        setCookie: ['IDS_ONLY=never-finance; Domain=shanghaitech.edu.cn; Path=/'],
      );
    }
    if (url.host == financeHost) {
      final hasSession = cookie.contains('ASP.NET_SessionId=');
      final hasAuth = cookie.contains('.ASPXAUTH=');
      final hasVerification = cookie.contains('SFP_Verify_Cookie=');
      final loggedIn = hasSession && hasAuth && hasVerification;
      switch ((url.port, url.path)) {
        case (443, portalLogin) when cookie.isEmpty:
          return response(
            request,
            status: 302,
            location: callback,
            setCookie: [if (!sessionAtCasEntry) _sessionCookie],
          );
        case (443, portalLogin) when loggedIn:
          return response(request, status: 302, location: portalHome);
        case (8099, externalLogin) when hasSession && url.queryParameters['ticket'] == ticket:
          return response(
            request,
            status: 302,
            location: callback,
            setCookie: ['.ASPXAUTH=synthetic-forms-auth; Path=/; HttpOnly'],
          );
        case (8099, externalLogin) when hasSession && hasAuth:
          return response(
            request,
            status: 302,
            location: '$portalOrigin$portalLogin',
            setCookie: [
              'SFP_Verify_Cookie=synthetic-verification; Domain=shanghaitech.edu.cn; Path=/',
            ],
          );
        case (8099, externalLogin) when !url.hasQuery && (hasSession || sessionAtCasEntry):
          return response(
            request,
            status: 302,
            location: ids.toString(),
            setCookie: [
              if (!hasSession) _sessionCookie,
              'CALLBACK_ONLY=synthetic; Path=$externalLogin',
            ],
          );
        case (443, portalHome) when loggedIn:
        case (8088, queryPage) when loggedIn:
          return response(request);
        case (8088, queryPath) when loggedIn:
          return response(request, body: html);
      }
    }
    return response(request, status: 404);
  }
}
