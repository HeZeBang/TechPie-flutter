import 'package:flutter/services.dart';

import '../features/campus_card/core/errors/app_failure.dart';
import '../utils/platform.dart';

/// What the DNS-only tunnel for the bind-code flow is doing right now.
enum EcardBindHijackStatus {
  /// No implementation on this platform (desktop, web, iOS simulator).
  unsupported,

  /// The platform can host it (Android, OHOS, iOS), and no tunnel is up.
  inactive,

  /// The tunnel is answering DNS for [EcardBindHijackService.host].
  active,

  /// The user refused the system VPN consent dialog.
  denied;

  static EcardBindHijackStatus parse(Object? value) => switch (value) {
        'active' => EcardBindHijackStatus.active,
        'denied' => EcardBindHijackStatus.denied,
        'unsupported' => EcardBindHijackStatus.unsupported,
        _ => EcardBindHijackStatus.inactive,
      };
}

/// The platform tunnel, as the service facade sees it — a seam for callers that
/// cannot start a real platform VPN (such as tests).
abstract interface class EcardBindHijackPort {
  Future<EcardBindHijackStatus> start();
  Future<void> stop();
  Future<EcardBindHijackStatus> status();
}

/// The platform tunnel that redirects one host name and leaves the rest alone.
///
/// The Android/OHOS VPN services and iOS Packet Tunnel extension answer
/// DNS for [EcardBindHijackService.host] with [EcardBindHijackService.targetIp];
/// TCP still goes out the ordinary network, so this does not proxy anything the
/// mini program or the exchange request actually send. It applies to every app,
/// not to a list of them.
final class EcardBindHijackService implements EcardBindHijackPort {
  static const _channel = MethodChannel('techpie/ecard_bind');

  /// The campus host the bind service is served under, and the address the
  /// tunnel answers with.
  static const host = 'ecard.shanghaitech.edu.cn';
  static const targetIp = '119.78.254.196';

  /// Each mobile platform implements the same channel contract. On iOS the
  /// native plugin reports unsupported when running in a simulator.
  static bool get _hostsTunnel => isAndroid() || isOhos() || isIos();

  /// No package allowlist: the mini program and this app must see the same
  /// answer. iOS scopes DNS to the campus host rather than replacing the
  /// device's resolver for unrelated domains.
  static const Map<String, Object?> _arguments = <String, Object?>{
    'host': host,
    'ip': targetIp,
  };

  @override
  Future<EcardBindHijackStatus> start() async {
    if (!_hostsTunnel) return EcardBindHijackStatus.unsupported;
    try {
      return EcardBindHijackStatus.parse(
        await _channel.invokeMethod<String>('start', _arguments),
      );
    } on MissingPluginException {
      return EcardBindHijackStatus.unsupported;
    } on PlatformException catch (error) {
      throw AppFailure(
        FailureKind.unavailable,
        '无法开启自动获取，请检查系统 VPN 设置及应用的 VPN 授权。',
        code: error.code,
        cause: error,
      );
    }
  }

  @override
  Future<void> stop() async {
    if (!_hostsTunnel) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // No host implementation: there is nothing to stop.
    } on PlatformException catch (error) {
      throw AppFailure(
        FailureKind.unavailable,
        '未能停止自动获取，请在系统 VPN 设置中断开 TechPie eCard 连接。',
        code: error.code,
        cause: error,
      );
    }
  }

  @override
  Future<EcardBindHijackStatus> status() async {
    if (!_hostsTunnel) return EcardBindHijackStatus.unsupported;
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
