import 'third_party_account.dart';

/// Exportable software credential. Only secure storage and encrypted Cloud Sync
/// may persist this object; never include it in API payloads or debug logs.
class IdsPasskey {
  static const rpId = 'ids.shanghaitech.edu.cn';
  final String credentialId;
  final String privateKey;
  final String userHandle;
  final String anonBiometricsId;
  final String username;

  const IdsPasskey({
    required this.credentialId,
    required this.privateKey,
    required this.userHandle,
    required this.anonBiometricsId,
    required this.username,
  });

  Map<String, dynamic> toJson() => {
        'credentialId': credentialId,
        'privateKey': privateKey,
        'userHandle': userHandle,
        'anonBiometricsId': anonBiometricsId,
        'username': username,
        'rpId': rpId,
        'alg': -7,
      };

  factory IdsPasskey.fromJson(Map<String, dynamic> json) {
    if (json['rpId'] != rpId || json['alg'] != -7) {
      throw const FormatException('Unsupported IDS credential');
    }
    return IdsPasskey(
      credentialId: json['credentialId'] as String,
      privateKey: json['privateKey'] as String,
      userHandle: json['userHandle'] as String,
      anonBiometricsId: json['anonBiometricsId'] as String,
      username: json['username'] as String,
    );
  }
}

/// A null credential is an explicit unbind; no binding means no sync opinion.
/// Session renewals never change this version or participate in its merge.
class IdsSyncBinding {
  final IdsPasskey? credential;
  final DateTime updatedAt;
  final String deviceId;

  const IdsSyncBinding({required this.credential, required this.updatedAt, required this.deviceId});

  ThirdPartyAccount toAccount() {
    final key = credential!;
    return ThirdPartyAccount(
      platform: ThirdPartyPlatform.ids,
      account: key.username,
      sid: key.username,
      token: '',
      raw: {
        'authMethod': 'passkey',
        'idsCredentialId': key.credentialId,
        'credential': key.toJson(),
      },
      boundAt: updatedAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      deviceId: deviceId,
    );
  }

  Map<String, dynamic> toJson() => credential == null
      ? {
          'platform': ThirdPartyPlatform.ids.id,
          'deletedAt': updatedAt.toUtc().toIso8601String(),
          'deviceId': deviceId,
        }
      : toAccount().toJson();

  static IdsSyncBinding? fromAccount(ThirdPartyAccount? account) {
    if (account?.platform != ThirdPartyPlatform.ids ||
        account!.raw['authMethod'] != 'passkey' ||
        account.raw['credential'] is! Map) {
      return null;
    }
    return IdsSyncBinding(
      credential: IdsPasskey.fromJson((account.raw['credential'] as Map).cast<String, dynamic>()),
      updatedAt: account.updatedAt,
      deviceId: account.deviceId,
    );
  }

  IdsSyncBinding merge(IdsSyncBinding? other) {
    if (other == null) return this;
    final time = updatedAt.compareTo(other.updatedAt);
    if (time != 0) return time > 0 ? this : other;
    final device = deviceId.compareTo(other.deviceId);
    if (device != 0) return device > 0 ? this : other;
    if (credential == null || other.credential == null) return credential == null ? this : other;
    return credential!.credentialId.compareTo(other.credential!.credentialId) >= 0 ? this : other;
  }
}
