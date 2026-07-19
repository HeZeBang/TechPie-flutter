enum ThirdPartyPlatform {
  gradescope,
  hydro,
  egate;

  String get id => name;
  String get label => switch (this) {
        ThirdPartyPlatform.gradescope => 'Gradescope',
        ThirdPartyPlatform.hydro => 'Hydro',
        ThirdPartyPlatform.egate => 'eGate / IDS',
      };

  static ThirdPartyPlatform? fromId(String id) {
    for (final p in ThirdPartyPlatform.values) {
      if (p.id == id) return p;
    }
    return null;
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
  });

  DateTime? get expireAt => expire == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(expire! * 1000);

  bool get isExpired {
    final at = expireAt;
    return at != null && at.isBefore(DateTime.now());
  }

  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    if (email != null && email!.isNotEmpty) return email!;
    if (sid != null && sid!.isNotEmpty) return sid!;
    return account;
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
      };

  factory ThirdPartyAccount.fromJson(Map<String, dynamic> json) {
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
      boundAt:
          DateTime.tryParse(json['boundAt'] as String? ?? '') ?? DateTime.now(),
      autoRenew: json['autoRenew'] as bool? ?? false,
      password: json['password'] as String?,
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
    );
  }
}
