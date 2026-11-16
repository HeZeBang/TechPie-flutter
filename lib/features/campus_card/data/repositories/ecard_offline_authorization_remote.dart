import '../../core/errors/app_failure.dart';
import '../../domain/models/offline_models.dart';
import '../../domain/ports/offline_ports.dart';
import '../api/ecard_api_client.dart';

/// Implements only the protocol recorded in pay_api.md.
///
/// The documented activation request sends the private key to the service.
/// Construction is blocked unless an explicit audited approval is supplied.
final class EcardOfflineAuthorizationRemote
    implements OfflineAuthorizationRemotePort {
  EcardOfflineAuthorizationRemote({
    required EcardTransport client,
    required bool backendSecurityApproval,
  })  : _client = client,
        _backendSecurityApproval = backendSecurityApproval;

  final EcardTransport _client;
  final bool _backendSecurityApproval;

  @override
  Future<OfflineActivationResponse> activate(
    OfflineActivationRequest request,
  ) async {
    if (!_backendSecurityApproval) {
      throw const AppFailure(
        FailureKind.unavailable,
        '真实离线付款开通尚未通过安全确认。',
        code: 'OFFLINE_ACTIVATION_SECURITY_HOLD',
      );
    }
    final response = requireObjectMap(
      await _client.post('/offlineCode/openOfflineCode', {
        'idserial': request.cardId,
        'offlinetype': '0',
        'devcode': request.deviceCode,
        'userpublickey': request.publicKeyCompressed,
        'userprivatekey': request.privateKeyHex,
      }),
      context: 'OFFLINE_ACTIVATION',
    );
    if (!apiSuccess(response)) {
      throw AppFailure(
        FailureKind.server,
        apiMessage(response, fallback: '离线付款开通失败。'),
        code: 'OFFLINE_ACTIVATION_REJECTED',
      );
    }
    final outer = requireObjectMap(
      response['data'],
      context: 'OFFLINE_ACTIVATION_DATA',
    );
    final data = requireObjectMap(
      outer['data'],
      context: 'OFFLINE_ACTIVATION_INNER',
    );
    final authorInfo = data['authorinfo']?.toString() ?? '';
    if (!_isHex(authorInfo)) {
      throw const AppFailure(
        FailureKind.protocol,
        '离线付款授权格式无效。',
        code: 'OFFLINE_AUTHORINFO_INVALID',
      );
    }
    return OfflineActivationResponse(
      validateContext: () => validateEcardResponse(response),
      commitInSession: (action) => commitEcardResponse(response, action),
      authorInfo: authorInfo.toUpperCase(),
      totalUses: _totalUses(data['offlineqrcodenum']),
      expiresOn: _parseDate(data['authordate']),
    );
  }

  @override
  Future<OfflineActivationResponse?> renew(
    OfflineAuthorization authorization,
  ) async {
    final response = requireObjectMap(
      await _client.get('/home/getUserkeys', {
        'devcode': authorization.deviceCode,
        'userpublickey': authorization.publicKeyCompressed,
      }),
      context: 'OFFLINE_RENEWAL',
    );
    final outer = response['data'] is Map
        ? requireObjectMap(response['data'], context: 'OFFLINE_RENEWAL_DATA')
        : response;
    final data = outer['data'] is Map
        ? requireObjectMap(outer['data'], context: 'OFFLINE_RENEWAL_INNER')
        : outer;
    final ukey = requireObjectMap(
      data['ukey'],
      context: 'OFFLINE_RENEWAL_UKEY',
    );
    if (ukey['result'] != true) return null;
    final authorInfo = ukey['authorinfo']?.toString() ?? '';
    if (!_isHex(authorInfo)) {
      throw const AppFailure(
        FailureKind.protocol,
        '离线付款续期授权格式无效。',
        code: 'OFFLINE_RENEWED_AUTHORINFO_INVALID',
      );
    }
    return OfflineActivationResponse(
      validateContext: () => validateEcardResponse(response),
      commitInSession: (action) => commitEcardResponse(response, action),
      authorInfo: authorInfo.toUpperCase(),
      totalUses: ukey.containsKey('offlineqrcodenum')
          ? _totalUses(ukey['offlineqrcodenum'])
          : authorization.totalUses,
      expiresOn: _parseDate(ukey['authordate']),
    );
  }

  static bool _isHex(String value) =>
      value.isNotEmpty &&
      value.length.isEven &&
      RegExp(r'^[0-9A-Fa-f]+$').hasMatch(value);

  static int _integer(Object? value, {required int fallback}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int? _totalUses(Object? value) {
    final parsed = _integer(value, fallback: 0);
    return parsed <= 0 ? null : parsed;
  }

  static DateTime? _parseDate(Object? value) {
    final digits = value?.toString();
    if (digits == null || !RegExp(r'^\d{8}$').hasMatch(digits)) return null;
    final parsed = DateTime.tryParse(
      '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6, 8)}',
    );
    return parsed == null
        ? null
        : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }
}
