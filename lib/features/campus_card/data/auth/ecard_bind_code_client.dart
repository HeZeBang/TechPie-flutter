import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/errors/app_failure.dart';
import '../../domain/models/auth_models.dart';

/// An OPENID redeemed from a bind code, with the channel it was issued for.
final class EcardBindCodeResult {
  const EcardBindCodeResult({required this.openId, this.userType, this.orgId});

  final String openId;
  final String? userType;
  final String? orgId;

  /// The mini program reports the channel as a usertype; anything it does not
  /// name is the WeChat channel the manual form defaults to.
  EcardOpenIdChannel get channel => EcardOpenIdChannel.values.firstWhere(
    (channel) => channel.userType == userType,
    orElse: () => EcardOpenIdChannel.wechat,
  );
}

typedef EcardBindSend =
    Future<(int, String)> Function(
      String method,
      String url,
      Map<String, String> headers,
      String body,
    );

/// The bind service's own status page: no token, no code, just a liveness line.
typedef EcardBindHealth = ({int status, String body});

/// Redeems the one-shot code the mini program shows for the freshly resolved
/// OPENID.
///
/// The request names the campus host on purpose: the Android tunnel points that
/// name at the mirror, and TLS stays pinned to the campus certificate, so the
/// hijack never requires relaxing certificate validation.
final class EcardBindCodeClient {
  EcardBindCodeClient({
    EcardBindSend? send,
    Duration timeout = const Duration(seconds: 15),
  }) : _send = send ?? _sendOverHttp,
       _timeout = timeout;

  static const bindHost = 'ecard.shanghaitech.edu.cn';
  static const exchangePath = '/__ecard_bind/exchange';
  static const exchangeUrl = 'https://$bindHost$exchangePath';
  static const healthUrl = 'https://$bindHost/__ecard_bind/health';

  /// Shared secret of the exchange endpoint. Rotating it means updating the
  /// `ecard-tls` secret, restarting the deployment, and shipping this value
  /// again.
  static const bindToken = '0075dd8c7cc6f97ec5deb3079d65a49f';

  final EcardBindSend _send;
  final Duration _timeout;

  Future<EcardBindCodeResult> exchange(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw const AppFailure(FailureKind.invalidInput, '请输入绑定码');
    }

    final (status, body) = await _deliver(normalized);
    final payload = _decodeEnvelope(body);
    if (payload == null) {
      // Something other than the bind service answered (a captive portal, or the
      // campus host without the mirror in front of it): the code never landed.
      throw const AppFailure(FailureKind.server, '绑定服务暂时不可用，请稍后重试');
    }

    switch (status) {
      case 200:
        final openId = payload['openid'];
        if (openId is! String || openId.trim().isEmpty) {
          throw const AppFailure(FailureKind.protocol, '绑定服务返回异常，请重试');
        }
        return EcardBindCodeResult(
          openId: openId.trim(),
          userType: payload['usertype']?.toString(),
          orgId: payload['orgid']?.toString(),
        );
      case 400:
        throw const AppFailure(FailureKind.invalidInput, '绑定码格式不正确');
      case 401:
        throw const AppFailure(
          FailureKind.permissionDenied,
          '绑定服务未授权，请联系管理员',
        );
      case 404:
      case 410:
        throw const AppFailure(
          FailureKind.authenticationExpired,
          '绑定码无效或已过期，请在小程序重新获取',
        );
      default:
        throw const AppFailure(FailureKind.server, '绑定服务暂时不可用，请稍后重试');
    }
  }

  Future<(int, String)> _deliver(String code) async {
    try {
      return await _send(
        'POST',
        exchangeUrl,
        const {'content-type': 'application/json', 'X-Bind-Token': bindToken},
        jsonEncode({'code': code}),
      ).timeout(_timeout);
    } on TimeoutException {
      throw const AppFailure(FailureKind.timeout, '网络异常，请检查劫持是否开启后重试');
    } on IOException {
      // Unreachable host, refused connection, rejected certificate: all of it
      // means the request never reached the bind service.
      throw const AppFailure(FailureKind.network, '网络异常，请检查劫持是否开启后重试');
    }
  }

  /// Asks the bind service whether it is there at all — the answer that tells a
  /// working tunnel apart from one that is only configured.
  Future<EcardBindHealth> fetchHealth() async {
    final (status, body) = await _deliverHealth();
    return (status: status, body: body);
  }

  Future<(int, String)> _deliverHealth() async {
    try {
      return await _send('GET', healthUrl, const {'accept': 'application/json'}, '')
          .timeout(_timeout);
    } on TimeoutException {
      throw const AppFailure(FailureKind.timeout, '自检请求超时');
    } on IOException {
      throw const AppFailure(FailureKind.network, '自检请求无法发出');
    }
  }

  static Map<String, Object?>? _decodeEnvelope(String body) {
    if (body.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    return decoded is Map<String, Object?> ? decoded : null;
  }

  static Future<(int, String)> _sendOverHttp(
    String method,
    String url,
    Map<String, String> headers,
    String body,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(method, Uri.parse(url));
      headers.forEach(request.headers.set);
      request.write(body);
      final response = await request.close();
      return (response.statusCode, await utf8.decoder.bind(response).join());
    } finally {
      client.close(force: true);
    }
  }
}
