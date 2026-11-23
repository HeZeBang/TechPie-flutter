import 'package:dio/dio.dart';
import 'package:html/parser.dart';

import '../models/student_allowance.dart';
import 'campus_user_agent.dart';
import 'ids/campus_http.dart';
import 'student_allowance_parser.dart';

/// All failures use fixed messages. Raw HTML, cookie headers, redirect URLs and
/// underlying transport exceptions may contain private finance or CAS data.
enum StudentAllowanceFailure {
  signIn,
  bindIds,
  idsSession,
  accessChanged,
  network,
  unavailable,
  financeSession,
  unexpectedResponse,
}

class StudentAllowanceException implements Exception {
  const StudentAllowanceException(this.failure);

  final StudentAllowanceFailure failure;

  String get message => switch (failure) {
        StudentAllowanceFailure.signIn => '请先登录 TechPie',
        StudentAllowanceFailure.bindIds => '请先在「第三方账号」中绑定 IDS',
        StudentAllowanceFailure.idsSession => '无法使用 IDS 登录财务系统，请检查 IDS 绑定后重试',
        StudentAllowanceFailure.accessChanged => '账号已变更，请重新查询',
        StudentAllowanceFailure.network => '无法连接学校财务或 IDS，请检查网络；校外可尝试连接学校 VPN',
        StudentAllowanceFailure.unavailable => '学校财务或 IDS 暂时不可用，请稍后重试',
        StudentAllowanceFailure.financeSession => '未能建立学生津贴查询会话，请稍后重试',
        StudentAllowanceFailure.unexpectedResponse => '无法识别学校财务返回的数据，请稍后重试',
      };

  @override
  String toString() => message;
}

/// Performs the read-only query on device. Each query gets a separate finance
/// cookie jar; no results, credentials or cookies are logged or persisted.
class StudentAllowanceClient {
  StudentAllowanceClient({Dio? http})
      : _ownsHttp = http == null,
        _http = http ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
              ),
            );

  final Dio _http;
  final bool _ownsHttp;

  static const _financeHost = 'finance.shanghaitech.edu.cn';
  static const _financeOrigin = 'https://$_financeHost';
  static const _configId = '22';
  static final _callback = Uri.parse('$_financeOrigin/ExternalLogin.aspx');
  static final _idsLogin = Uri.https(
    'ids.shanghaitech.edu.cn',
    '/authserver/login',
    {'service': _callback.toString()},
  );
  static final _queryPage = Uri.https(
    _financeHost,
    '/SalaryQuerySalary/SalayQuerySalary',
    {'ConfigID': _configId},
  );
  static final _query = Uri.parse('$_financeOrigin/SalaryQuerySalary/CtrlSQSalaryInfoSKD');
  static const _redirectCodes = {301, 302, 303, 307, 308};

  Future<StudentAllowanceReport> query({
    required String idsCookies,
    required StudentAllowancePeriod period,
    required void Function() checkAccess,
  }) async {
    final finance = CampusHttp(_http, onlyOrigin: _financeOrigin);
    try {
      // Let ASP.NET establish its own session before the CAS handoff. Do not
      // follow a finance-provided login URL with the IDS cookie header.
      checkAccess();
      final entry = await finance.request(
        _callback,
        allowErrorResponse: true,
        followRedirects: false,
      );
      _checkUnavailable(entry);

      checkAccess();
      final ticket = await _requestTicket(idsCookies);
      await _getFinance(finance, ticket, checkAccess);
      if (await finance.cookie(_query, '.ASPXAUTH') == null) {
        throw const StudentAllowanceException(StudentAllowanceFailure.financeSession);
      }

      // Load the query page first, so any finance verification cookies are
      // obtained from the server in addition to the forms-auth session.
      await _getFinance(finance, _queryPage, checkAccess);
      checkAccess();
      final result = await finance.request(
        _query,
        method: 'POST',
        data: Uri(
          queryParameters: {
            'SearchYearMonthB': period.startParameter,
            'SearchYearMonthE': period.endParameter,
            'ConfigID': _configId,
          },
        ).query,
        headers: {
          'Accept': 'text/html, */*; q=0.01',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Origin': _financeOrigin,
          'Referer': _queryPage.toString(),
          'X-Requested-With': 'XMLHttpRequest',
        },
        allowErrorResponse: true,
        followRedirects: false,
      );
      checkAccess();
      _requireFinanceSuccess(result);
      return parseStudentAllowanceReport(CampusHttp.text(result));
    } on DioException {
      throw const StudentAllowanceException(StudentAllowanceFailure.network);
    } on IdsException {
      // CampusHttp (used only for the finance origin here) sanitizes transport
      // errors; it does not expose a raw response or URL to this caller.
      throw const StudentAllowanceException(StudentAllowanceFailure.network);
    } on FormatException {
      throw const StudentAllowanceException(StudentAllowanceFailure.unexpectedResponse);
    }
  }

  Future<Uri> _requestTicket(String idsCookies) async {
    if (idsCookies.isEmpty) {
      throw const StudentAllowanceException(StudentAllowanceFailure.idsSession);
    }
    final result = await _http.getUri<List<int>>(
      _idsLogin,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        validateStatus: (_) => true,
        headers: {'Cookie': idsCookies, 'User-Agent': CampusUserAgent.value},
      ),
    );
    _checkUnavailable(result);
    final status = result.statusCode;
    final destination = _redirectCodes.contains(status) ? _location(result) : null;
    if (status == 401 ||
        status == 403 ||
        (destination != null &&
            destination.scheme == _idsLogin.scheme &&
            destination.host == _idsLogin.host &&
            destination.port == _idsLogin.port &&
            destination.path == _idsLogin.path) ||
        (status == 200 &&
            parse(CampusHttp.text(result)).querySelector('[name="execution"]') != null)) {
      throw const StudentAllowanceException(StudentAllowanceFailure.idsSession);
    }
    if (destination == null ||
        !_isFinance(destination) ||
        destination.path != _callback.path ||
        destination.queryParametersAll.length != 1) {
      throw const StudentAllowanceException(StudentAllowanceFailure.unexpectedResponse);
    }
    final tickets = destination.queryParametersAll['ticket'];
    if (tickets == null || tickets.length != 1 || !tickets.single.startsWith('ST-')) {
      throw const StudentAllowanceException(StudentAllowanceFailure.unexpectedResponse);
    }
    return destination;
  }

  Future<void> _getFinance(
    CampusHttp finance,
    Uri uri,
    void Function() checkAccess,
  ) async {
    for (var hop = 0; hop < 6; hop++) {
      checkAccess();
      final response = await finance.request(
        uri,
        allowErrorResponse: true,
        followRedirects: false,
      );
      if (!_redirectCodes.contains(response.statusCode)) {
        _requireFinanceSuccess(response);
        return;
      }
      final next = _location(response);
      if (next == null || !_isFinance(next) || next.queryParameters.containsKey('ticket')) {
        throw const StudentAllowanceException(StudentAllowanceFailure.financeSession);
      }
      uri = next;
    }
    throw const StudentAllowanceException(StudentAllowanceFailure.financeSession);
  }

  static bool _isFinance(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == _financeHost &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment;

  static Uri? _location(Response<List<int>> response) {
    final values = response.headers['location'];
    if (values == null || values.length != 1 || values.single.trim().isEmpty) return null;
    final location = Uri.tryParse(values.single);
    return location == null ? null : response.requestOptions.uri.resolveUri(location);
  }

  static void _checkUnavailable(Response<List<int>> response) {
    if ((response.statusCode ?? 0) >= 500 || response.statusCode == 429) {
      throw const StudentAllowanceException(StudentAllowanceFailure.unavailable);
    }
  }

  static void _requireFinanceSuccess(Response<List<int>> response) {
    _checkUnavailable(response);
    if (response.statusCode != 200) {
      throw const StudentAllowanceException(StudentAllowanceFailure.financeSession);
    }
  }

  void close() {
    if (_ownsHttp) _http.close(force: true);
  }
}
