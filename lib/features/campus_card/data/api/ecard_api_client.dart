import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';

import '../../core/async_mutex.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/core_error_catalog.dart';
import '../../domain/models/auth_models.dart';
import '../../domain/models/payment_models.dart';
import 'decrypted_http_trace.dart';
import 'ecard_cipher.dart';

final class EcardVerifiedIdentity {
  const EcardVerifiedIdentity({
    required this.subjectId,
    required this.idSerial,
    required this.cardId,
  });

  final String subjectId;
  final String idSerial;
  final String cardId;

  @override
  bool operator ==(Object other) =>
      other is EcardVerifiedIdentity &&
      other.subjectId == subjectId &&
      other.idSerial == idSerial &&
      other.cardId == cardId;

  @override
  int get hashCode => Object.hash(subjectId, idSerial, cardId);
}

final class EcardSession {
  const EcardSession({
    required this.sessionCookie,
    required this.openId,
    required this.orgId,
    required this.subjectId,
    this.generation = 0,
    this.channel = EcardOpenIdChannel.wechat,
    this.identity,
  });

  final int generation;
  final EcardOpenIdChannel channel;
  final EcardVerifiedIdentity? identity;

  bool sameSession(EcardSession other) =>
      generation == other.generation && channel == other.channel &&
      sessionCookie == other.sessionCookie &&
      openId == other.openId &&
      orgId == other.orgId &&
      subjectId == other.subjectId &&
      identity == other.identity;

  final String sessionCookie;
  final String openId;
  final String orgId;
  final String subjectId;
}

typedef EcardSessionCommit = Future<void> Function(
    EcardSession session, Future<void> Function() action,);

typedef EcardSessionReader = Future<EcardSession?> Function();
typedef EcardIdentityGuard = Future<EcardVerifiedIdentity> Function();
typedef AuthenticationExpiredCallback = FutureOr<void> Function(int statusCode);
typedef IdentityMismatchCallback = FutureOr<void> Function();

abstract interface class EcardTransport {
  Future<Object?> get(
    String path,
    Map<String, Object?> data, {
    bool includeOpenId = true,
  });

  Future<Object?> post(
    String path,
    Map<String, Object?> data, {
    bool includeOpenId = true,
  });

  Future<List<int>> download(String path);

  Future<Object?> getPlain(
    String path,
    Map<String, Object?> query, {
    bool includeOpenId = false,
  });
}

final class EcardApiClient implements EcardTransport {
  EcardApiClient({
    Dio? dio,
    DecryptedHttpTraceInterceptor? httpTrace,
    EcardCipher? cipher,
    required EcardSessionReader sessionReader,
    EcardSessionReader? sessionPreparer,
    Future<EcardVerifiedIdentity?> Function()? requestIdentityReader,
    int Function()? accountRevisionReader,
    Future<void> Function(EcardSession)? onSessionActivity,
    required EcardIdentityGuard identityGuard,
    int Function()? sessionGenerationReader,
    EcardSessionCommit? commitInSession,
    required AuthenticationExpiredCallback onAuthenticationExpired,
    required IdentityMismatchCallback onIdentityMismatch,
    String baseUrl = 'https://ecard.shanghaitech.edu.cn',
  })  : _cipher = cipher ?? EcardCipher(),
        _sessionReader = sessionReader,
        _sessionPreparer = sessionPreparer,
        _requestIdentityReader = requestIdentityReader,
        _accountRevisionReader = accountRevisionReader,
        _onSessionActivity = onSessionActivity,
        _identityGuard = identityGuard,
        _sessionGenerationReader = sessionGenerationReader,
        _commitInSession = commitInSession,
        _onAuthenticationExpired = onAuthenticationExpired,
        _onIdentityMismatch = onIdentityMismatch,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 6),
                sendTimeout: const Duration(seconds: 6),
                headers: const {
                  'content-type': 'application/json',
                  'x-requested-with': 'XMLHttpRequest',
                  'session-type': 'uniapp',
                  'isWechatApp': 'true',
                },
              ),
            ) {
    installDecryptedHttpTrace(_dio, trace: httpTrace);
  }

  final Dio _dio;
  final EcardCipher _cipher;
  final EcardSessionReader _sessionReader;
  final EcardSessionReader? _sessionPreparer;
  final Future<EcardVerifiedIdentity?> Function()? _requestIdentityReader;
  final int Function()? _accountRevisionReader;
  final Future<void> Function(EcardSession)? _onSessionActivity;
  final EcardIdentityGuard _identityGuard;
  final int Function()? _sessionGenerationReader;
  final EcardSessionCommit? _commitInSession;
  final AuthenticationExpiredCallback _onAuthenticationExpired;
  final IdentityMismatchCallback _onIdentityMismatch;
  final AsyncMutex _requestMutex = AsyncMutex();

  Dio get dioForTesting => _dio;

  void dispose() => _dio.close(force: true);

  Future<Object?> pollPaymentResult(
          String payCode, PaymentRequestContext? context,) =>
      _execute('POST', '/virtualcard/queryOrderStatus', {'paycode': payCode},
          permission: context,);

  Future<Object?> submitScanPayment(
          Map<String, Object?> data, PaymentRequestContext? context,) =>
      _execute('POST', '/scan/scanningResult', data, permission: context);

  int _responseSequence = 0;
  _CodeLease? _code;
  _CodeLease? _challenge;

  // Only these reads may be repeated automatically after authentication recovery.
  // HTTP method alone is insufficient: some upstream GET endpoints mutate data.
  static const _replayableReads = {
    '/myaccount/openMyAccountApp',
    '/home/userImageIsexists',
    '/repair/showImage',
    '/selftrade/queryCardSelfTradeList',
    '/virtualcard/openQrcodePwdModify',
    '/virtualcard/openQrcodeQuotaModify',
  };

  @override
  Future<Object?> get(
    String path,
    Map<String, Object?> data, {
    bool includeOpenId = true,
  }) =>
      _execute('GET', path, data, includeOpenId: includeOpenId);

  @override
  Future<Object?> post(
    String path,
    Map<String, Object?> data, {
    bool includeOpenId = true,
  }) =>
      _execute('POST', path, data, includeOpenId: includeOpenId);

  @override
  Future<Object?> getPlain(
    String path,
    Map<String, Object?> query, {
    bool includeOpenId = false,
  }) =>
      _execute('GET', path, query, includeOpenId: includeOpenId, plain: true);

  @override
  Future<List<int>> download(String path) async =>
      (await _execute('GET', path, const {}, bytes: true))! as List<int>;

  Future<void> _assertSession(EcardSession expected) async {
    final current = await _sessionReader();
    if (current == null || !current.sameSession(expected)) {
      throw _identityFailure('AUTH_SESSION_SUBJECT_CHANGED');
    }
  }

  Future<Object?> _execute(
    String method,
    String path,
    Map<String, Object?> data, {
    bool includeOpenId = true,
    bool plain = false,
    bool bytes = false,
    PaymentRequestContext? permission,
  }) async {
    final frozenData = Map<String, Object?>.unmodifiable(data);
    final accountRevision = _accountRevisionReader?.call();
    final scope = _RequestScope(_requestIdentityReader == null
        ? null
        : await _requestIdentityReader.call(),);
    final endpoint = Uri.parse(path).path;
    final readOrGenerate = _replayableReads.contains(endpoint) ||
        endpoint == '/offlineCode/openVirtualcard';
    for (var attempt = 0; attempt < 2; attempt++) {
      scope.sent = false;
      try {
        if (accountRevision != _accountRevisionReader?.call()) {
          throw _identityFailure('AUTH_REQUEST_ACCOUNT_CHANGED');
        }
        return await _executeOnce(method, path, frozenData,
            scope: scope,
            includeOpenId: includeOpenId,
            plain: plain,
            bytes: bytes,
            permission: permission,);
      } on AppFailure catch (failure) {
        if (accountRevision != _accountRevisionReader?.call()) {
          throw _identityFailure('AUTH_REQUEST_ACCOUNT_CHANGED');
        }
        final canRetry = attempt == 0 &&
            failure.isRecoverableSessionFailure &&
            failure.code != 'AUTH_PAYMENT_CONTEXT_EXPIRED' &&
            (failure.code != 'AUTH_SESSION_SUBJECT_CHANGED' ||
                accountRevision != null) &&
            accountRevision == _accountRevisionReader?.call() &&
            endpoint != '/virtualcard/queryOrderStatus' &&
            (readOrGenerate || !scope.sent) &&
            (scope.owner != null || scope.identity != null);
        if (canRetry) continue;
        throw AppFailure(failure.kind, failure.safeMessage,
            code: failure.code,
            retryable: failure.retryable,
            cause: failure.cause,
            requestNotSent: !scope.sent,);
      }
    }
    throw _identityFailure('AUTH_RECOVERY_FAILED');
  }

  Future<Object?> _executeOnce(
    String method,
    String path,
    Map<String, Object?> data, {
    required _RequestScope scope,
    bool includeOpenId = true,
    bool plain = false,
    bool bytes = false,
    PaymentRequestContext? permission,
  }) async {
    data = Map<String, Object?>.unmodifiable(data);
    // How long the request spends before a byte leaves the device — the session
    // reads and the identity check — is reported by the trace beside the wire
    // time, which is what tells a slow refresh apart from a slow server.
    final prepStartedAt = DateTime.now().microsecondsSinceEpoch;
    // Capture before queueing. Queued A requests must never run as account B.
    final invocationGeneration = _sessionGenerationReader?.call();
    final queuedSession = await (_sessionPreparer?.call() ?? _sessionReader());
    if (_sessionPreparer == null &&
        invocationGeneration != null &&
        queuedSession?.generation != invocationGeneration) {
      throw _identityFailure('AUTH_SESSION_SUBJECT_CHANGED');
    }
    if (queuedSession == null) {
      throw _identityFailure('AUTH_VERIFIED_SESSION_MISSING');
    }
    if ((scope.owner != null && !_sameAccount(scope.owner!, queuedSession)) ||
        (scope.identity != null && queuedSession.identity != scope.identity)) {
      throw _identityFailure('AUTH_REQUEST_ACCOUNT_CHANGED');
    }
    scope.owner ??= queuedSession;
    final endpoint = Uri.parse(path).path;
    final polling = endpoint == '/virtualcard/queryOrderStatus';
    final generating = endpoint == '/offlineCode/openVirtualcard';
    final scanning = endpoint == '/scan/scanningResult';
    final lease = polling
        ? _code
        : scanning && data['password'] != null
            ? _challenge
            : null;
    if (polling || (scanning && data['password'] != null)) {
      final supplied = polling ? data['paycode'] : data['qrcode'];
      if (lease == null ||
          !identical(permission, lease) ||
          !lease.session.sameSession(queuedSession) ||
          supplied != lease.code) {
        throw _identityFailure('AUTH_PAYMENT_CONTEXT_EXPIRED');
      }
    }
    return _requestMutex.protect(() async {
      await _assertSession(queuedSession);
      if (polling && !identical(_code, lease) ||
          scanning &&
              data['password'] != null &&
              !identical(_challenge, lease)) {
        throw _identityFailure('AUTH_PAYMENT_CONTEXT_EXPIRED');
      }
      if (generating) _code = null;
      if (scanning) _challenge = null;
      var session = queuedSession;
      final readsQuota = endpoint == '/virtualcard/openQrcodeQuotaModify';
      // The identity this request is checked against comes from the session the
      // request was prepared with, so nothing is fetched before the request is
      // sent — the response is validated against that pin instead. A mismatch is
      // therefore caught after the request, which is why a bad generation is
      // discarded rather than exposed: what it created cannot be taken back, but
      // it never reaches the payer.
      final identity = polling
          ? lease!.identity
          : session.identity ?? await _identityGuard();
      var verifiedSession = await _sessionReader();
      if (verifiedSession == null && _sessionPreparer != null) {
        verifiedSession = await _sessionPreparer.call();
      }
      if (verifiedSession == null || !_sameAccount(session, verifiedSession)) {
        throw _identityFailure('AUTH_SESSION_SUBJECT_CHANGED');
      }
      if (!session.sameSession(verifiedSession)) {
        if (lease != null) {
          throw _identityFailure('AUTH_PAYMENT_CONTEXT_EXPIRED');
        }
        // No business request has been sent yet. A verified replacement for
        // the same account can be used without replaying any payment.
        session = verifiedSession;
      }
      if (identity.subjectId != session.subjectId ||
          session.identity != null && identity != session.identity) {
        throw _identityFailure('AUTH_SESSION_SUBJECT_CHANGED');
      }
      final request = _requestData(data, session, includeOpenId: includeOpenId);
      _validateRequestIdentity(path, request, identity);
      try {
        // A request about to be sent is activity, including a slow payment.
        // Pure session/cache reads do not extend the inactivity deadline.
        await _onSessionActivity?.call(session);
        scope.sent = true;
        final responseOrder = ++_responseSequence;
        final response = await _dio.request<Object?>(
          path,
          data: method == 'POST'
              ? {'datajson': _cipher.encodeRequest(request)}
              : null,
          queryParameters: method != 'POST' && !bytes
              ? plain
                  ? request
                  : {'datajson': _cipher.encodeRequest(request)}
              : null,
          options: Options(
            method: method,
            responseType: bytes ? ResponseType.bytes : ResponseType.json,
            headers: {
              'cookie': session.sessionCookie,
              'orgid': session.orgId,
            },
            extra: {
              DecryptedHttpTraceInterceptor.prepMicrosKey:
                  DateTime.now().microsecondsSinceEpoch - prepStartedAt,
            },
          ),
        );
        await _assertSession(session);
        if (bytes) return response.data;
        final decoded = _decode(response.data);
        try {
          _validateIdentityFields(decoded, identity);
          if (readsQuota) {
            final map = requireObjectMap(decoded, context: 'IDENTITY_QUOTA');
            final fields = map['data'] is Map ? map['data'] as Map : map;
            if (apiRejected(map) ||
                fields['idserial']?.toString() != identity.idSerial ||
                fields['cardid']?.toString() != identity.cardId) {
              throw _identityFailure('AUTH_IDENTITY_MISMATCH');
            }
          }
        } on AppFailure {
          _code = null;
          _challenge = null;
          await _onIdentityMismatch();
          rethrow;
        }
        await _assertSession(session);
        if (polling && !identical(_code, lease)) {
          throw _identityFailure('AUTH_PAYMENT_CONTEXT_EXPIRED');
        }
        if (decoded is Map &&
            apiSuccess(requireObjectMap(decoded, context: 'RESPONSE'))) {
          if (generating && decoded['data'] is Map) {
            final code = (decoded['data'] as Map)['code']?.toString() ?? '';
            if (code.isNotEmpty) _code = _CodeLease(code, session, identity);
          }
          if (scanning &&
              (decoded['issuccess']?.toString() == '2004' ||
                  Uri.tryParse(decoded['url']?.toString() ?? '')?.path ==
                      '/pages/common/inputPass/inputPass')) {
            final nested = decoded['data'] is Map
                ? decoded['data'] as Map
                : const <String, Object?>{};
            final code =
                (nested['qrcode'] ?? decoded['qrcode'])?.toString() ?? '';
            if (code.isNotEmpty) {
              // Kept verbatim: the retry submits this exact string, and the
              // lease guard compares it against the outgoing payload.
              _challenge = _CodeLease(code, session, identity);
            }
          }
        }
        final responseSession = session;
        return _bindResponse(
          decoded,
          responseSession,
          () => _assertSession(responseSession),
          generating
              ? _code
              : scanning
                  ? _challenge
                  : null,
          _commitInSession,
          responseOrder,
        );
      } on DioException catch (error) {
        // Never expire or recover B due to a late failure from A.
        await _assertSession(session);
        final status = error.response?.statusCode;
        if (status == 401 || status == 403) {
          _code = null;
          _challenge = null;
          await _onAuthenticationExpired(status!);
        }
        throw await _mapDioFailure(error, notifyAuthentication: false);
      }
    });
  }

  bool _sameAccount(EcardSession before, EcardSession after) =>
      before.subjectId == after.subjectId &&
      before.openId == after.openId &&
      before.channel == after.channel &&
      before.orgId == after.orgId &&
      before.identity == after.identity;

  Map<String, Object?> _requestData(
    Map<String, Object?> data,
    EcardSession session, {
    required bool includeOpenId,
  }) {
    final request = Map<String, Object?>.from(data);
    if (request.containsKey('usertype')) request['usertype'] = session.channel.userType;
    if (includeOpenId && !request.containsKey('openid')) {
      request['openid'] = session.openId;
    }
    if (request.containsKey('devcode') && request['devcode'] != session.openId) {
      throw _identityFailure('AUTH_REQUEST_IDENTITY_MISMATCH');
    }
    if (request.containsKey('openid') && request['openid'] != session.openId) {
      throw _identityFailure('AUTH_REQUEST_IDENTITY_MISMATCH');
    }
    return request;
  }

  Object? _decode(Object? body) {
    try {
      return EcardCipher.decodeResponse(body);
    } on FormatException catch (error) {
      throw AppFailure(
        FailureKind.protocol,
        '服务返回了无法识别的数据。',
        code: 'ECARD_DECRYPT_FAILED',
        cause: error,
      );
    }
  }

  void _validateIdentityFields(Object? value, EcardVerifiedIdentity identity) {
    if (value is List) {
      for (final item in value) {
        _validateIdentityFields(item, identity);
      }
      return;
    }
    if (value is! Map) return;
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      final fieldValue = entry.value?.toString().trim() ?? '';
      if (key == 'idserial' &&
          fieldValue.isNotEmpty &&
          fieldValue != identity.idSerial) {
        throw _identityFailure('AUTH_RESPONSE_IDENTITY_MISMATCH');
      }
      if (key == 'cardid' &&
          fieldValue.isNotEmpty &&
          fieldValue != identity.cardId) {
        throw _identityFailure('AUTH_RESPONSE_IDENTITY_MISMATCH');
      }
      _validateIdentityFields(entry.value, identity);
    }
  }

  void _validateRequestIdentity(
    String path,
    Map<String, Object?> request,
    EcardVerifiedIdentity identity,
  ) {
    if (path == '/bind/wechatBind') return;
    final idSerial = request['idserial']?.toString().trim();
    final cardId = request['cardid']?.toString().trim();
    if ((idSerial != null &&
            idSerial.isNotEmpty &&
            idSerial != identity.idSerial) ||
        (cardId != null && cardId.isNotEmpty && cardId != identity.cardId)) {
      throw _identityFailure('AUTH_REQUEST_IDENTITY_MISMATCH');
    }
  }

  AppFailure _identityFailure(String code) => AppFailure(
        FailureKind.authenticationExpired,
        switch (code) {
          'AUTH_PAYMENT_CONTEXT_EXPIRED' => '付款码对应的会话已更新，请重新获取付款码或重新扫码。',
          'AUTH_REQUEST_ACCOUNT_CHANGED' => '校园卡账户已变化，本次操作已取消。',
          'AUTH_SESSION_SUBJECT_CHANGED' => '校园卡会话已变化，本次请求已停止，请重试。',
          'AUTH_VERIFIED_SESSION_MISSING' => '校园卡会话暂未就绪，请联网重试。',
          'AUTH_REQUEST_IDENTITY_MISMATCH' => '请求账户与当前校园卡账户不一致，已停止请求。',
          _ => '服务端返回的身份与已验证账户不一致，已丢弃本次响应。',
        },
        code: code,
      );

  Future<AppFailure> _mapDioFailure(
    DioException error, {
    bool notifyAuthentication = true,
  }) async {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      if (notifyAuthentication) await _onAuthenticationExpired(status!);
      return AppFailure(
        FailureKind.authenticationExpired,
        status == 403 ? '登录状态无权访问，请重新登录。' : '登录状态已过期，请重新登录。',
        code: 'HTTP_$status',
      );
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        const AppFailure(
          FailureKind.timeout,
          '连接校园支付服务超时，请重试。',
          code: 'NETWORK_TIMEOUT',
          retryable: true,
        ),
      DioExceptionType.connectionError => const AppFailure(
          FailureKind.network,
          '当前无法连接校园支付服务。',
          code: 'NETWORK_UNREACHABLE',
          retryable: true,
        ),
      DioExceptionType.cancel => const AppFailure(
          FailureKind.cancelled,
          '请求已取消。',
          code: 'REQUEST_CANCELLED',
        ),
      _ => AppFailure(
          FailureKind.server,
          '校园支付服务暂时不可用。',
          code: status == null ? 'HTTP_UNKNOWN' : 'HTTP_$status',
          retryable: status == null || status >= 500,
        ),
    };
  }
}

final class _RequestScope {
  _RequestScope(this.identity);
  final EcardVerifiedIdentity? identity;
  EcardSession? owner;
  bool sent = false;
}

Map<String, Object?> requireObjectMap(
  Object? value, {
  required String context,
}) {
  if (value is EcardResponseMap) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  if (value is String && CoreErrorCatalog.isCoreCode(value)) {
    final code = value.trim();
    if (code == 'CORE10007' || code == 'CORE10008') {
      return {'success': true, 'message': code};
    }
    throw AppFailure(
      FailureKind.server,
      CoreErrorCatalog.resolve(code),
      code: code,
    );
  }
  throw AppFailure(
    FailureKind.protocol,
    '服务返回了无法识别的数据。',
    code: 'INVALID_$context',
  );
}

List<Object?> requireList(Object? value, {required String context}) {
  if (value is List) return List<Object?>.from(value);
  if (value is String && CoreErrorCatalog.isCoreCode(value)) {
    final code = value.trim();
    if (code == 'CORE10007' || code == 'CORE10008') return const [];
    throw AppFailure(
      FailureKind.server,
      CoreErrorCatalog.resolve(code),
      code: code,
    );
  }
  throw AppFailure(
    FailureKind.protocol,
    '服务返回了无法识别的数据。',
    code: 'INVALID_$context',
  );
}

bool apiSuccess(Map<String, Object?> map) {
  final value = map['success'];
  return value == true ||
      value == 1 ||
      value?.toString().toLowerCase() == 'true';
}

bool apiRejected(Map<String, Object?> map) =>
    map.containsKey('success') && !apiSuccess(map);

String apiMessage(Map<String, Object?> map, {String fallback = '请求失败'}) {
  final raw = map['message']?.toString().trim();
  if (raw == null || raw.isEmpty) return fallback;
  return CoreErrorCatalog.resolve(raw);
}

final class _CodeLease implements PaymentRequestContext {
  const _CodeLease(this.code, this.session, this.identity);
  final String code;
  final EcardSession session;
  final EcardVerifiedIdentity identity;
}

/// Carries local provenance through repository parsing, never over the network.
final class EcardResponseMap extends MapBase<String, Object?> {
  EcardResponseMap(
    this._values,
    this.session,
    this.validateContext,
    this.requestContext,
    this.commitInSession, [
    this.responseOrder = 0,
  ]);
  final int responseOrder;
  final EcardSessionCommit? commitInSession;
  final PaymentRequestContext? requestContext;
  final Map<String, Object?> _values;
  final EcardSession session;
  final Future<void> Function() validateContext;
  @override
  Object? operator [](Object? key) => _values[key];
  @override
  void operator []=(String key, Object? value) => _values[key] = value;
  @override
  Iterable<String> get keys => _values.keys;
  @override
  void clear() => _values.clear();
  @override
  Object? remove(Object? key) => _values.remove(key);
}

Object? _bindResponse(
  Object? value,
  EcardSession session,
  Future<void> Function() validate, [
  PaymentRequestContext? context,
  EcardSessionCommit? commit,
  int responseOrder = 0,
]) {
  if (value is Map) {
    return EcardResponseMap(
      value.map(
        (key, item) => MapEntry(
          key.toString(),
          _bindResponse(item, session, validate, context, commit, responseOrder),
        ),
      ),
      session,
      validate,
      context,
      commit,
      responseOrder,
    );
  }
  if (value is List) {
    return value
        .map((item) => _bindResponse(item, session, validate, context, commit, responseOrder))
        .toList();
  }
  return value;
}

Future<void> validateEcardResponse(Object? response) async {
  if (response is EcardResponseMap) await response.validateContext();
}

Future<void> commitEcardResponse(
  Object? response,
  Future<void> Function() action,
) async {
  if (response is EcardResponseMap && response.commitInSession != null) {
    await response.commitInSession!(response.session, action);
  } else {
    await validateEcardResponse(response);
    await action();
    await validateEcardResponse(response);
  }
}
