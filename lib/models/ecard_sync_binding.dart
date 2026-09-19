import '../features/campus_card/domain/models/auth_models.dart';

/// Only the login parameter is synced; cookies, identity pins and keys stay local.
final class EcardSyncBinding {
  const EcardSyncBinding({required this.openId, required this.updatedAt, required this.deviceId, this.channel = EcardOpenIdChannel.wechat});
  final String? openId; // null is an explicit deletion, not an absent backup.
  final DateTime updatedAt;
  final String deviceId;
  final EcardOpenIdChannel channel;

  Map<String, Object?> toJson() => {
    'openid': openId, 'channel': channel.method, 'updatedAt': updatedAt.toUtc().toIso8601String(), 'deviceId': deviceId,
  };

  static EcardSyncBinding? fromJson(Object? value) {
    if (value is! Map || !value.containsKey('openid')) return null;
    final openId = value['openid'];
    final EcardOpenIdChannel channel;
    try { channel = EcardOpenIdChannel.parse(value['channel']); } on FormatException { return null; }
    final updatedAt = DateTime.tryParse(value['updatedAt']?.toString() ?? '');
    final deviceId = value['deviceId'];
    if (updatedAt == null || deviceId is! String || (openId != null && openId is! String)) return null;
    if (openId is String) {
      try { OpenIdAuthCredential(openId: openId, channel: channel).validate(); } on FormatException { return null; }
    }
    return EcardSyncBinding(channel: channel, openId: openId as String?, updatedAt: updatedAt, deviceId: deviceId);
  }

  EcardSyncBinding merge(EcardSyncBinding? other) {
    if (other == null) return this;
    final time = updatedAt.compareTo(other.updatedAt);
    if (time != 0) return time > 0 ? this : other;
    final device = deviceId.compareTo(other.deviceId);
    if (device != 0) return device > 0 ? this : other;
    if (openId == null || other.openId == null) return openId == null ? this : other;
    final identity = '${channel.method}:$openId'.compareTo('${other.channel.method}:${other.openId}');
    return identity >= 0 ? this : other;
  }
}

abstract interface class EcardSyncStore {
  Future<EcardSyncBinding?> readSyncBinding();
  Future<void> applySyncBinding(EcardSyncBinding? binding);
}
