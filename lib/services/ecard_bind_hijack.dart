import 'package:flutter/services.dart';

import '../utils/platform.dart';

/// What the DNS-only tunnel for the bind-code flow is doing right now.
enum EcardBindHijackStatus {
  /// No implementation on this platform (iOS, desktop, OHOS).
  unsupported,

  /// Android, and no tunnel is up.
  inactive,

  /// The tunnel is answering DNS for [EcardBindHijackService.host].
  active,

  /// The user refused the system VPN consent dialog.
  denied;

  static EcardBindHijackStatus parse(Object? value) => switch (value) {
    'active' => EcardBindHijackStatus.active,
    'denied' => EcardBindHijackStatus.denied,
    _ => EcardBindHijackStatus.inactive,
  };
}

/// The platform tunnel, as the service facade sees it — a seam for callers that
/// cannot start a real `VpnService` (tests, and every non-Android platform).
abstract interface class EcardBindHijackPort {
  Future<EcardBindHijackStatus> start();
  Future<void> stop();
  Future<EcardBindHijackStatus> status();
}

/// Android tunnel that redirects one host name and leaves the rest alone.
///
/// `EcardBindVpnService` answers only DNS for [host] with [targetIp]; TCP still
/// goes out the ordinary network, so this does not proxy anything the mini
/// program or the exchange request actually send.
final class EcardBindHijackService implements EcardBindHijackPort {
  static const _channel = MethodChannel('techpie/ecard_bind');

  /// The campus host the bind service is served under, and the address the
  /// tunnel answers with (`ecard.techpie.geekpie.club`).
  static const host = 'ecard.shanghaitech.edu.cn';
  static const targetIp = '119.78.254.196';

  /// The mini program is where the code is read, so WeChat is allowed into the
  /// tunnel; this app is always allowed as well, because the exchange request
  /// resolves [host] itself.
  static const wechatPackage = 'com.tencent.mm';

  static const Map<String, Object?> _arguments = <String, Object?>{
    'host': host,
    'ip': targetIp,
    'packages': <String>[wechatPackage],
  };

  @override
  Future<EcardBindHijackStatus> start() async {
    if (!isAndroid()) return EcardBindHijackStatus.unsupported;
    try {
      return EcardBindHijackStatus.parse(
        await _channel.invokeMethod<String>('start', _arguments),
      );
    } on MissingPluginException {
      return EcardBindHijackStatus.unsupported;
    } on PlatformException {
      return EcardBindHijackStatus.inactive;
    }
  }

  @override
  Future<void> stop() async {
    if (!isAndroid()) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // No host implementation: there is nothing to stop.
    } on PlatformException {
      // Same: the tunnel is gone either way.
    }
  }

  @override
  Future<EcardBindHijackStatus> status() async {
    if (!isAndroid()) return EcardBindHijackStatus.unsupported;
    try {
      return EcardBindHijackStatus.parse(
        await _channel.invokeMethod<String>('status'),
      );
    } on MissingPluginException {
      return EcardBindHijackStatus.unsupported;
    } on PlatformException {
      return EcardBindHijackStatus.inactive;
    }
  }
}
