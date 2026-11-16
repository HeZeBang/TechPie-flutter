import '../models/auth_models.dart';

abstract interface class SecureCredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll(Iterable<String> keys);

  /// Replace all entries as one logical transaction or fail closed.
  Future<void> replaceAtomically(Map<String, String?> values);
}

abstract interface class SessionCredentialStore {
  Future<String?> readSessionCookie();
  Future<DateTime?> readSessionLastActivity();
  Future<void> writeSessionLastActivity(DateTime value);
  Future<String?> readOpenId();
  Future<EcardOpenIdChannel> readOpenIdChannel();
  Future<String?> readOrgId();
  Future<String?> readVerifiedIdSerial();
  Future<String?> readVerifiedCardId();
  Future<void> writeSession({
    required String sessionCookie,
    required String openId,
    required String orgId,
    required String verifiedIdSerial,
    required String verifiedCardId,
    DateTime? lastActivityAt,
    EcardOpenIdChannel channel = EcardOpenIdChannel.wechat,
  });
  Future<void> stageOpenId(String openId, {EcardOpenIdChannel channel = EcardOpenIdChannel.wechat});
  Future<void> clearSessionCookie();
  Future<void> clear();
}
