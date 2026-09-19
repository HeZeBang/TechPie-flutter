import 'offline_models.dart';

/// Exported only through the paired-watch bridge; never log or cache as settings.
final class WatchOfflineCredential {
  const WatchOfflineCredential(
      this.authorization, this.privateKey, this.deviceChecksum,);
  final OfflineAuthorization authorization;
  final String privateKey;
  final int deviceChecksum;

  Map<String, Object?> toMessage() => {
        'cardID': authorization.cardId,
        'privateKey': privateKey,
        'publicKey': authorization.publicKeyCompressed,
        'deviceChecksum': deviceChecksum,
        'authorInfo': authorization.authorInfo,
        'expiresAt': authorization.expiresOn!
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch /
            1000,
        'totalUses': authorization.totalUses,
      };
}
