import 'package:techpie/models/ids_passkey.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/ids/ids_client.dart';

/// Supplies software credentials and local OA cookies to business-service tests.
/// The real IDS wire protocol is exercised separately in ids_client_test.dart.
class FakeIdsClient extends IdsClient {
  static ThirdPartyAccount account(String username, {DateTime? boundAt, String name = 'User'}) {
    final account = IdsSyncBinding(
      credential: key(username),
      updatedAt: boundAt ?? DateTime.utc(2026),
      deviceId: 'fixture',
    ).toAccount();
    return account.copyWith(name: name, raw: {...account.raw, 'tgc': 'tgc-value', 'cookies': ''});
  }

  static IdsPasskey key(String username) => IdsPasskey(
        credentialId: 'synthetic-$username',
        privateKey: 'synthetic-private-key',
        userHandle: 'synthetic-user-handle',
        anonBiometricsId: 'synthetic-biometric-id',
        username: username,
      );

  @override
  Future<IdsSession> login(IdsPasskey secret, {bool backedUp = false}) async =>
      IdsSession(secret.username, {'tgc': 'tgc-value', 'cookies': ''}, name: 'User');

  @override
  Future<({IdsPasskey credential, IdsSession session})> register(
    String username,
    String password, {
    required IdsCaptchaPrompt promptCaptcha,
    required Future<void> Function(IdsPasskey) saveCandidate,
  }) async {
    final credential = key(username);
    await saveCandidate(credential);
    return (credential: credential, session: await login(credential));
  }

  @override
  Future<String> mintCookie(String nodeId, Map<String, dynamic> root) async {
    return switch (nodeId) {
      'eams' => 'JSESSIONID=eams-mock',
      'elearning' => 'session_id=elearning-mock',
      'egateApp' => 'MOD_AUTH_CAS=egate-mock',
      'oa' => 'shkjdx_session=oa-session',
      _ => throw StateError('Unexpected local cookie request: $nodeId'),
    };
  }
}
