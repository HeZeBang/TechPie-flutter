import '../models/offline_models.dart';

final class OfflineActivationRequest {
  const OfflineActivationRequest({
    required this.cardId,
    required this.deviceCode,
    required this.publicKeyCompressed,
    required this.privateKeyHex,
  });

  final String cardId;
  final String deviceCode;
  final String publicKeyCompressed;
  final String privateKeyHex;
}

final class OfflineActivationResponse {
  const OfflineActivationResponse({
    required this.authorInfo,
    required this.totalUses,
    this.expiresOn,
    this.validateContext,
    this.commitInSession,
  });

  final Future<void> Function()? validateContext;
  final Future<void> Function(Future<void> Function())? commitInSession;
  final String authorInfo;

  /// Null represents the backend value 0, which means unlimited use.
  final int? totalUses;
  final DateTime? expiresOn;
}

abstract interface class OfflineAuthorizationRemotePort {
  Future<OfflineActivationResponse> activate(OfflineActivationRequest request);
  Future<OfflineActivationResponse?> renew(OfflineAuthorization authorization);
}

abstract interface class OfflineCredentialRepository {
  Future<OfflineAuthorization?> read(
    String cardId, {
    required String deviceCode,
  });
  Future<OfflineAuthorization?> readMostRecent({required String deviceCode});

  /// Atomically persists [authorization] and its matching private key.
  Future<void> install({
    required OfflineAuthorization authorization,
    required String privateKeyHex,
  });

  /// Atomically increments `used` before returning. No rollback is permitted.
  Future<OfflineAuthorization> reserveUse(
    String cardId, {
    required String deviceCode,
  });

  Future<String?> readPrivateKey(String cardId, {required String deviceCode});
  Future<void> updateAuthorization(
    OfflineAuthorization authorization, {
    bool resetUsage = false,
  });
  Future<void> remove(String cardId);
  Future<void> removeAll();
}
