enum ThirdPartyPlatform {
  gradescope,
  hydro,
  cpdaily;

  /// Stable id used for storage keys and cloud-sync payloads. Note: the
  /// backend bind route for cpdaily is still 'egate' (unrenamed); see
  /// [apiPath].
  String get id => name;
  String get label => switch (this) {
        ThirdPartyPlatform.gradescope => 'Gradescope',
        ThirdPartyPlatform.hydro => 'Hydro',
        ThirdPartyPlatform.cpdaily => 'CpDaily / IDS',
      };

  /// Backend bind/renew route name. cpdaily maps to 'egate' (the backend
  /// route was not renamed); all others map to their own [id].
  String get apiPath => switch (this) {
        ThirdPartyPlatform.cpdaily => 'egate',
        _ => id,
      };

  /// Parse a platform id, accepting the legacy 'egate' alias for cpdaily.
  static ThirdPartyPlatform? fromId(String id) {
    return switch (id) {
      'gradescope' => ThirdPartyPlatform.gradescope,
      'hydro' => ThirdPartyPlatform.hydro,
      'cpdaily' || 'egate' => ThirdPartyPlatform.cpdaily,
      _ => null,
    };
  }
}


class ThirdPartyAccount {
  final ThirdPartyPlatform platform;
  final String account;
  final String? sid;
  final String? name;
  final String? email;
  final String token;
  final int? expire;
  final Map<String, dynamic> raw;
  final String? hydroOrigin;
  final List<String>? hydroDomains;
  final DateTime boundAt;
  // Auto-renew config. When [autoRenew] is true the password is also
  // persisted (in the same secure-storage entry) so the app can silently
  // re-authenticate when the token nears expiry.
  final bool autoRenew;
  final String? password;

  /// Wall-clock timestamp of the most recent local mutation of this account
  /// (bind / rebind / renew / raw update). Used by the cloud-sync merge to do
  /// per-account last-writer-wins with [deviceId] as a deterministic
  /// tie-breaker. Defaults to [boundAt] for accounts created before this
  /// field existed (back-compat: treated as "ancient" so any newer write
  /// wins).
  final DateTime updatedAt;

  /// Stable id of the device that produced the current [updatedAt] bump. Used
  /// as the LWW tie-breaker so two devices with skewed clocks still converge
  /// deterministically. Empty for legacy accounts; newer devices always win
  /// against an empty deviceId.
  final String deviceId;

  const ThirdPartyAccount({
    required this.platform,
    required this.account,
    this.sid,
    this.name,
    this.email,
    required this.token,
    this.expire,
    this.raw = const {},
    this.hydroOrigin,
    this.hydroDomains,
    required this.boundAt,
    this.autoRenew = false,
    this.password,
    DateTime? updatedAt,
    String? deviceId,
  })  : updatedAt = updatedAt ?? boundAt,
        deviceId = deviceId ?? '';

  DateTime? get expireAt => expire == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(expire! * 1000);

  bool get isExpired =>
      expireAt != null && DateTime.now().isAfter(expireAt!);

  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    return account;
  }

  /// Comparison key for LWW merge: newer [updatedAt] wins; on a tie the
  /// lexicographically-larger [deviceId] wins (deterministic, total order).
  /// An empty deviceId is treated as oldest of all so legacy data loses to
  /// any real device write.
  int compareVersionTo(ThirdPartyAccount other) {
    final c = updatedAt.compareTo(other.updatedAt);
    if (c != 0) return c;
    // Empty deviceId always loses.
    if (deviceId.isEmpty && other.deviceId.isNotEmpty) return -1;
    if (deviceId.isNotEmpty && other.deviceId.isEmpty) return 1;
    return deviceId.compareTo(other.deviceId);
  }

  Map<String, dynamic> toJson() => {
        'platform': platform.id,
        'account': account,
        if (sid != null) 'sid': sid,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        'token': token,
        if (expire != null) 'expire': expire,
        'raw': raw,
        if (hydroOrigin != null) 'hydroOrigin': hydroOrigin,
        if (hydroDomains != null) 'hydroDomains': hydroDomains,
        'boundAt': boundAt.toIso8601String(),
        'autoRenew': autoRenew,
        if (password != null) 'password': password,
        'updatedAt': updatedAt.toIso8601String(),
        'deviceId': deviceId,
      };

  factory ThirdPartyAccount.fromJson(Map<String, dynamic> json) {
    final boundAt =
        DateTime.tryParse(json['boundAt'] as String? ?? '') ?? DateTime.now();
    return ThirdPartyAccount(
      platform: ThirdPartyPlatform.fromId(json['platform'] as String? ?? '') ??
          ThirdPartyPlatform.gradescope,
      account: json['account'] as String? ?? '',
      sid: json['sid'] as String?,
      name: json['name'] as String?,
      email: json['email'] as String?,
      token: json['token'] as String? ?? '',
      expire: (json['expire'] as num?)?.toInt(),
      raw: (json['raw'] as Map?)?.cast<String, dynamic>() ?? const {},
      hydroOrigin: json['hydroOrigin'] as String?,
      hydroDomains:
          (json['hydroDomains'] as List?)?.map((e) => e as String).toList(),
      boundAt: boundAt,
      autoRenew: json['autoRenew'] as bool? ?? false,
      password: json['password'] as String?,
      // Back-compat: pre-v2 blobs had no updatedAt/deviceId. Fall back to
      // boundAt / empty so they merge as "older than any real write".
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? boundAt,
      deviceId: json['deviceId'] as String? ?? '',
    );
  }

  ThirdPartyAccount copyWith({
    String? token,
    int? expire,
    String? sid,
    String? name,
    String? email,
    Map<String, dynamic>? raw,
    String? hydroOrigin,
    List<String>? hydroDomains,
    bool? autoRenew,
    String? password,
    DateTime? updatedAt,
    String? deviceId,
  }) {
    return ThirdPartyAccount(
      platform: platform,
      account: account,
      sid: sid ?? this.sid,
      name: name ?? this.name,
      email: email ?? this.email,
      token: token ?? this.token,
      expire: expire ?? this.expire,
      raw: raw ?? this.raw,
      hydroOrigin: hydroOrigin ?? this.hydroOrigin,
      hydroDomains: hydroDomains ?? this.hydroDomains,
      boundAt: boundAt,
      autoRenew: autoRenew ?? this.autoRenew,
      password: password ?? this.password,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}
