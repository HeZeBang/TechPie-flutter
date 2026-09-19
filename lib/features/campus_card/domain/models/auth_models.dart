import 'dart:convert';
import 'package:crypto/crypto.dart';

enum EcardOpenIdChannel {
  wechat('wechat_openid', 'WeChat（微信）', '8'),
  alipay('alipay_openid', 'Alipay（支付宝）', '18');

  const EcardOpenIdChannel(this.method, this.label, this.userType);
  final String method;
  final String label;
  final String userType;

  static EcardOpenIdChannel parse(Object? value) {
    if (value == null) return wechat; // Pre-channel settings were WeChat-only.
    return values.firstWhere((channel) => channel.method == value,
      orElse: () => throw const FormatException('Unknown OPENID channel'),);
  }

  String subjectId(String openId) => sha256.convert(utf8.encode(
    this == wechat ? openId : '$method:$openId',
  ),).toString();
}

enum AuthState { signedOut, signingIn, authenticated, unconfigured, expired }

sealed class AuthCredential {
  const AuthCredential();
}

final class DemoAuthCredential extends AuthCredential {
  const DemoAuthCredential();
}

final class OpenIdAuthCredential extends AuthCredential {
  const OpenIdAuthCredential({
    required this.openId,
    this.channel = EcardOpenIdChannel.wechat,
    this.expectedIdSerial,
    this.expectedCardId,
  });

  final String openId;
  final EcardOpenIdChannel channel;

  /// Optional one-shot guard values supplied by an authorized caller.
  /// They must never be logged or persisted.
  final String? expectedIdSerial;
  final String? expectedCardId;

  void validate() {
    final value = openId.trim();
    if (value.length < 16 ||
        value.length > 256 ||
        value.contains(RegExp(r'\s'))) {
      throw const FormatException('OpenID format is invalid');
    }
  }
}

final class AuthSession {
  const AuthSession({
    required this.subjectId,
    required this.orgId,
    this.maskedIdentity,
    this.generation = 0,
  });

  /// Opaque local subject identifier. It must not be logged.
  final String subjectId;
  final String orgId;
  final int generation;

  /// Presentation-safe identifier. Implementations may expose only a short
  /// first/last mask; the complete credential never leaves secure storage.
  final String? maskedIdentity;
}

enum AuthChangeReason { userSignedOut, accountChanged }

final class AuthSnapshot {
  const AuthSnapshot({required this.state, this.session, this.message, this.reason});

  final AuthChangeReason? reason;
  final AuthState state;
  final AuthSession? session;
  final String? message;
}
