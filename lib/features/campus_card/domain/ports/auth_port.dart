import '../models/auth_models.dart';

abstract interface class AuthPort {
  /// Restores only locally persisted identity state without network I/O.
  Future<AuthSnapshot> restoreLocal();

  /// Refreshes the locally restored identity and session against eCard.
  Future<AuthSnapshot> restore();
  Future<AuthSnapshot> signIn(AuthCredential credential);
  Future<void> signOut();
  Stream<AuthSnapshot> get changes;
}

/// Verifies an OpenID against eCard without changing the saved account.
abstract interface class OpenIdAuthVerifier {
  Future<void> verifyOpenId(String openId, {EcardOpenIdChannel channel = EcardOpenIdChannel.wechat});
}
