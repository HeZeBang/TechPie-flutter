import 'package:dio/dio.dart';
import 'package:html/parser.dart';

import '../models/student_allowance.dart';
import 'campus_user_agent.dart';
import 'debug_logger.dart';
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

enum _FinanceStage {
  portalLogin,
  casEntry,
  idsTicket,
  ticketCallback,
  ticketlessCallback,
  portalReturn,
  portalHome,
  queryPage,
  queryPost,
}

enum _FinanceDiagnostic {
  unexpectedStatus,
  invalidRedirect,
  missingAspNetSession,
  missingFormsAuth,
  missingVerification,
  idsRejected,
  invalidTicket,
  network,
  unavailable,
  invalidResponse,
}

enum _FinanceCookie {
  aspNetSession('ASP.NET_SessionId', _FinanceDiagnostic.missingAspNetSession),
  formsAuth('.ASPXAUTH', _FinanceDiagnostic.missingFormsAuth),
  verification('SFP_Verify_Cookie', _FinanceDiagnostic.missingVerification);

  const _FinanceCookie(this.key, this.missing);

  final String key;
  final _FinanceDiagnostic missing;
}

/// Performs the read-only query on device. Each query gets a separate finance
/// cookie jar; no results, credentials or cookies are logged or persisted.
class StudentAllowanceClient {
  StudentAllowanceClient({Dio? http, DebugLogger? logger})
      : _logger = logger,
        _ownsHttp = http == null,
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
  final DebugLogger? _logger;

  static const _financeHost = 'finance.shanghaitech.edu.cn';
  static const _portalOrigin = 'https://$_financeHost';
  static const _callbackOrigin = 'https://$_financeHost:8099';
  static const _queryOrigin = 'https://$_financeHost:8088';
  static const _financeOrigins = {_portalOrigin, _callbackOrigin, _queryOrigin};
  static const _configId = '22';
  static final _portalHome = Uri.parse('$_portalOrigin/Home/Index');
  static final _portalLogin = Uri.parse('$_portalOrigin/Home/IndexLogin');
  static final _callback = Uri.parse('$_callbackOrigin/ExternalLogin.aspx');
  static final _idsLogin = Uri.https(
    'ids.shanghaitech.edu.cn',
    '/authserver/login',
    {'service': _callback.toString()},
  );
  static final _queryPage =
      Uri.parse('$_queryOrigin/SalaryQuerySalary/SalayQuerySalary?ConfigID=$_configId');
  static final _query = Uri.parse('$_queryOrigin/SalaryQuerySalary/CtrlSQSalaryInfoSKD');
  static const _redirectCodes = {301, 302, 303, 307, 308};

  Future<StudentAllowanceReport> query({
    required String idsCookies,
    required StudentAllowancePeriod period,
    required void Function() checkAccess,
  }) async {
    // One finance jar spans the three approved origins on the same host.
    // The IDS request is separate and never sees this jar.
    final finance = CampusHttp(_http, allowedOrigins: _financeOrigins);

    await _visitRedirect(finance, _FinanceStage.portalLogin, _portalLogin, _callback, checkAccess);
    await _visitRedirect(finance, _FinanceStage.casEntry, _callback, _idsLogin, checkAccess);
    final ticket = await _requestTicket(idsCookies, checkAccess);

    await _visitRedirect(finance, _FinanceStage.ticketCallback, ticket, _callback, checkAccess);
    await _requireCookie(
      finance,
      _callback,
      _FinanceCookie.formsAuth,
      _FinanceStage.ticketCallback,
    );

    // This second callback sets the verification cookie on the 302 itself.
    await _visitRedirect(
      finance,
      _FinanceStage.ticketlessCallback,
      _callback,
      _portalLogin,
      checkAccess,
    );
    await _requireCookie(
      finance,
      _portalLogin,
      _FinanceCookie.verification,
      _FinanceStage.ticketlessCallback,
    );
    await _visitRedirect(
      finance,
      _FinanceStage.portalReturn,
      _portalLogin,
      _portalHome,
      checkAccess,
    );
    _requireOk(
      await _get(finance, _FinanceStage.portalHome, _portalHome, checkAccess),
      _FinanceStage.portalHome,
    );
    _requireOk(
      await _get(finance, _FinanceStage.queryPage, _queryPage, checkAccess),
      _FinanceStage.queryPage,
    );
    for (final cookie in _FinanceCookie.values) {
      await _requireCookie(finance, _query, cookie, _FinanceStage.queryPost);
    }
    final result = await _fetch(
      _FinanceStage.queryPost,
      checkAccess,
      () => finance.request(
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
          'Origin': _queryOrigin,
          'Referer': _queryPage.toString(),
          'X-Requested-With': 'XMLHttpRequest',
        },
        allowErrorResponse: true,
        followRedirects: false,
      ),
    );
    _requireOk(result, _FinanceStage.queryPost);
    try {
      return parseStudentAllowanceReport(CampusHttp.text(result));
    } on FormatException {
      _fail(
        _FinanceStage.queryPost,
        _FinanceDiagnostic.invalidResponse,
        failure: StudentAllowanceFailure.unexpectedResponse,
      );
    }
  }

  Future<Uri> _requestTicket(String idsCookies, void Function() checkAccess) async {
    const stage = _FinanceStage.idsTicket;
    if (idsCookies.isEmpty) {
      _fail(stage, _FinanceDiagnostic.idsRejected, failure: StudentAllowanceFailure.idsSession);
    }
    final result = await _fetch(
      stage,
      checkAccess,
      () => _http.getUri<List<int>>(
        _idsLogin,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {'Cookie': idsCookies, 'User-Agent': CampusUserAgent.value},
        ),
      ),
    );
    final status = result.statusCode;
    final destination = _location(result);
    if (status == 401 ||
        status == 403 ||
        (destination != null && _sameEndpoint(destination, _idsLogin)) ||
        (status == 200 &&
            parse(CampusHttp.text(result)).querySelector('[name="execution"]') != null)) {
      _fail(stage, _FinanceDiagnostic.idsRejected, failure: StudentAllowanceFailure.idsSession);
    }
    final params = destination != null && _sameEndpoint(destination, _callback)
        ? _queryParameters(destination)
        : null;
    final tickets = params?['ticket'];
    if (params?.length != 1 ||
        tickets == null ||
        tickets.length != 1 ||
        !tickets.single.startsWith('ST-')) {
      _fail(
        stage,
        _FinanceDiagnostic.invalidTicket,
        failure: StudentAllowanceFailure.unexpectedResponse,
      );
    }
    return _callback.replace(queryParameters: {'ticket': tickets.single});
  }

  Future<Response<List<int>>> _get(
    CampusHttp finance,
    _FinanceStage stage,
    Uri uri,
    void Function() checkAccess,
  ) =>
      _fetch(
        stage,
        checkAccess,
        () => finance.request(uri, allowErrorResponse: true, followRedirects: false),
      );

  Future<void> _visitRedirect(
    CampusHttp finance,
    _FinanceStage stage,
    Uri from,
    Uri to,
    void Function() checkAccess,
  ) async {
    final response = await _get(finance, stage, from, checkAccess);
    _requireRedirect(response, stage, to);
  }

  Future<Response<List<int>>> _fetch(
    _FinanceStage stage,
    void Function() checkAccess,
    Future<Response<List<int>>> Function() request,
  ) async {
    checkAccess();
    final timer = Stopwatch()..start();
    try {
      final response = await request();
      final status = response.statusCode;
      _log(stage, status: status, elapsedMicros: timer.elapsedMicroseconds);
      checkAccess();
      if ((status ?? 0) >= 500 || status == 429) {
        _fail(stage, _FinanceDiagnostic.unavailable, failure: StudentAllowanceFailure.unavailable);
      }
      return response;
    } on DioException {
      _fail(stage, _FinanceDiagnostic.network, failure: StudentAllowanceFailure.network);
    } on IdsException {
      _fail(stage, _FinanceDiagnostic.network, failure: StudentAllowanceFailure.network);
    } on FormatException {
      _fail(
        stage,
        _FinanceDiagnostic.invalidResponse,
        failure: StudentAllowanceFailure.unexpectedResponse,
      );
    }
  }

  Future<void> _requireCookie(
    CampusHttp finance,
    Uri uri,
    _FinanceCookie cookie,
    _FinanceStage stage,
  ) async {
    if ((await finance.cookie(uri, cookie.key))?.isNotEmpty != true) {
      _fail(stage, cookie.missing);
    }
  }

  void _requireOk(Response<List<int>> response, _FinanceStage stage) {
    if (response.statusCode != 200) _fail(stage, _FinanceDiagnostic.unexpectedStatus);
  }

  void _requireRedirect(Response<List<int>> response, _FinanceStage stage, Uri expected) {
    if (!_redirectCodes.contains(response.statusCode)) {
      _fail(stage, _FinanceDiagnostic.unexpectedStatus);
    }
    final destination = _location(response);
    if (destination == null || !_sameEndpoint(destination, expected)) {
      _fail(stage, _FinanceDiagnostic.invalidRedirect);
    }
    if (expected == _idsLogin) {
      // Validate the service after decoding; never forward IDS credentials to
      // the URL supplied in the finance response.
      final params = _queryParameters(destination);
      final services = params?['service'];
      if (params?.length != 1 ||
          services?.length != 1 ||
          services!.single != _callback.toString()) {
        _fail(stage, _FinanceDiagnostic.invalidRedirect);
      }
    } else if (destination.hasQuery) {
      _fail(stage, _FinanceDiagnostic.invalidRedirect);
    }
  }

  static bool _sameEndpoint(Uri uri, Uri expected) =>
      uri.scheme == expected.scheme &&
      uri.host == expected.host &&
      uri.port == expected.port &&
      uri.userInfo.isEmpty &&
      uri.path == expected.path &&
      !uri.hasFragment;

  static Uri? _location(Response<List<int>> response) {
    if (!_redirectCodes.contains(response.statusCode)) return null;
    final values = response.headers['location'];
    if (values == null || values.length != 1) return null;
    final value = values.single.trim();
    if (value.isEmpty) return null;
    final location = Uri.tryParse(value);
    return location == null ? null : response.requestOptions.uri.resolveUri(location);
  }

  static Map<String, List<String>>? _queryParameters(Uri uri) {
    try {
      return uri.queryParametersAll;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Only an allowlisted stage and diagnostic enter either debug-log sink.
  /// In particular, no request URL, raw error, header, or body is passed in.
  void _log(
    _FinanceStage stage, {
    _FinanceDiagnostic? diagnostic,
    int? status,
    int? elapsedMicros,
  }) {
    final path = 'student-allowance/${stage.name}';
    _logger?.log(
      method: diagnostic != null ? 'CHECK' : (stage == _FinanceStage.queryPost ? 'POST' : 'GET'),
      operation: diagnostic == null ? path : '$path/${diagnostic.name}',
      statusCode: status,
      durationMicros: elapsedMicros,
      tag: 'StudentAllowance',
    );
  }

  Never _fail(
    _FinanceStage stage,
    _FinanceDiagnostic diagnostic, {
    StudentAllowanceFailure failure = StudentAllowanceFailure.financeSession,
  }) {
    _log(stage, diagnostic: diagnostic);
    throw StudentAllowanceException(failure);
  }

  void close() {
    if (_ownsHttp) _http.close(force: true);
  }
}
