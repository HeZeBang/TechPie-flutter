enum OfflineAuthorizationState {
  unavailable,
  missingCredential,
  active,
  renewalDue,
  expired,
  exhausted,
}

final class OfflineAuthorization {
  const OfflineAuthorization({
    required this.cardId,
    required this.deviceCode,
    required this.publicKeyCompressed,
    required this.authorInfo,
    required this.totalUses,
    required this.used,
    required this.updatedAt,
    this.expiresOn,
  });

  final String cardId;
  final String deviceCode;
  final String publicKeyCompressed;
  final String authorInfo;

  /// Null means the server granted unlimited local presentations.
  final int? totalUses;
  final int used;
  final DateTime updatedAt;
  final DateTime? expiresOn;

  bool get isLimited => totalUses != null;

  int? get remaining {
    final total = totalUses;
    if (total == null) return null;
    return total - used < 0 ? 0 : total - used;
  }

  OfflineAuthorization copyWith({
    String? authorInfo,
    int? totalUses,
    bool replaceTotalUses = false,
    int? used,
    DateTime? updatedAt,
    DateTime? expiresOn,
  }) =>
      OfflineAuthorization(
        cardId: cardId,
        deviceCode: deviceCode,
        publicKeyCompressed: publicKeyCompressed,
        authorInfo: authorInfo ?? this.authorInfo,
        totalUses: replaceTotalUses ? totalUses : totalUses ?? this.totalUses,
        used: used ?? this.used,
        updatedAt: updatedAt ?? this.updatedAt,
        expiresOn: expiresOn ?? this.expiresOn,
      );
}

final class OfflineQrCode {
  const OfflineQrCode({
    required this.hex,
    required this.payload,
    required this.reservedUse,
    required this.generatedAt,
  });

  final String hex;
  final String payload;
  final int reservedUse;
  final DateTime generatedAt;
}

final class OfflineAuthorizationView {
  const OfflineAuthorizationView({required this.state, this.authorization});

  final OfflineAuthorizationState state;
  final OfflineAuthorization? authorization;
}
