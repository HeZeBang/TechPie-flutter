import 'package:dio/dio.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/auth_models.dart';

final class IssuedEcardSession {
  const IssuedEcardSession({required this.cookie, required this.orgId,
    required this.idSerial, required this.cardId,});
  final String cookie;
  final String orgId;
  final String idSerial;
  final String cardId;
}

abstract interface class EcardSessionIssuer {
  Future<IssuedEcardSession> issue(String openId, {EcardOpenIdChannel channel = EcardOpenIdChannel.wechat});
}

/// Only GeekPie may acquire/bind a new eCard cookie. There is no direct fallback.
final class GeekPieEcardSessionIssuer implements EcardSessionIssuer {
  GeekPieEcardSessionIssuer({required Uri Function() endpoint, Dio? dio})
      : _endpoint = endpoint,
        _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 25), sendTimeout: const Duration(seconds: 6),),);
  final Uri Function() _endpoint;
  final Dio _dio;

  @override
  Future<IssuedEcardSession> issue(String openId, {EcardOpenIdChannel channel = EcardOpenIdChannel.wechat}) async {
    final endpoint = _endpoint();
    try {
      final response = await _dio.postUri<Object?>(endpoint,
        data: {'method': channel.method, 'openid': openId},
        options: Options(followRedirects: false, headers: {'content-type': 'application/json'}),);
      if (_endpoint() != endpoint) {
        throw const AppFailure(FailureKind.cancelled, '测试服务器设置已变化，请重试。', code: 'ECARD_ISSUER_CHANGED');
      }
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) throw const FormatException();
      final data = body['data'] as Map;
      final raw = data['raw'];
      if (raw is! Map) throw const FormatException();
      final cookie = data['token'];
      final sid = data['sid'];
      final cardId = raw['cardid'];
      if (cookie is! String || !RegExp(r'^JSESSIONID=[\x21-\x7e]+$').hasMatch(cookie) ||
          cookie.contains(RegExp(r'[",;\\]')) || raw['cookies'] != cookie ||
          sid is! String || sid.trim().isEmpty || raw['idserial'] != sid ||
          cardId is! String || cardId.trim().isEmpty || raw['orgid'] != '2') {
        throw const FormatException();
      }
      return IssuedEcardSession(cookie: cookie, orgId: '2', idSerial: sid, cardId: cardId);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const AppFailure(FailureKind.authenticationExpired,
          'eCard 登录被拒绝，请检查 OPENID。', code: 'ECARD_AUTH_REJECTED',);
      }
      if (status == 400) {
        throw const AppFailure(FailureKind.invalidInput,
          'eCard 登录参数无效，请检查 OPENID。', code: 'ECARD_LOGIN_INPUT_INVALID',);
      }
      final timeout = error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionTimeout || error.type == DioExceptionType.sendTimeout;
      throw AppFailure(timeout ? FailureKind.timeout : FailureKind.network,
        timeout ? 'eCard 会话服务响应超时，请重试。' : '无法连接 eCard 会话服务，请检查网络或测试服务器设置。',
        code: 'ECARD_SESSION_SERVICE_UNAVAILABLE', retryable: true,);
    } on FormatException {
      throw const AppFailure(FailureKind.protocol, 'eCard 会话服务返回的数据不完整。', code: 'ECARD_SESSION_RESPONSE_INVALID');
    }
  }
}
