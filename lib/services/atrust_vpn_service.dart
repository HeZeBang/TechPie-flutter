import 'dart:convert';

import 'package:flutter/services.dart';

import '../utils/platform.dart';
import 'atrust_control_client.dart';
import 'atrust_tunnel_service.dart';

/// The **system-VPN** shape on OHOS: an interface the whole device routes
/// through, which is what reaches the campus from WebViews and from other apps —
/// something the in-app proxy cannot do.
///
/// Only a VPN extension can create an interface, so the extension process owns
/// the engine and this class only asks for it: it hands over the session, the
/// controller's policy and the destinations to route, and reads the extension's
/// verdict back. Everything the engine refuses is reported, never guessed at.
class AtrustVpnService {
  static const _ohosChannel = MethodChannel('techpie/geektrust_vpn');
  static const _androidChannel = MethodChannel('techpie/atrust_vpn');

  /// Campus destinations to route into the tunnel. Deliberately broad: the
  /// engine still authorizes every flow against the controller's policy, so a
  /// destination outside it is refused rather than leaked. IPv6 is not routed
  /// because the engine carries IPv4 only.
  static const campusRoutes = <String>[
    '10.0.0.0/8',
    '119.78.0.0/16',
    '59.78.0.0/16',
  ];

  /// OHOS and Android; the desktops use the proxy shape instead.
  bool get isSupported => isOhos() || isAndroid();

  /// Raises the tunnel. Returns the extension's verdict: `active`, or a
  /// `failed: …` string carrying the engine's own words.
  ///
  /// On Android the engine runs in this same process, so the interface's
  /// descriptor comes back over the channel and goes straight to it. On OHOS the
  /// extension process owns both, and only a verdict comes back.
  Future<String> start(AtrustSession session, {AtrustTunnelService? engine}) async {
    if (isOhos()) {
      // Plain strings across the channel: ArkTS refuses `any`, and JSON.parse is
      // typed as one, so lists travel joined.
      final status = await _ohosChannel.invokeMethod<String>('start', {
        'session': _sessionJson(session),
        'policy': session.policyJson,
        'routes': campusRoutes.join(','),
        'dns': session.dns.join(','),
      });
      return status ?? 'failed: the extension said nothing';
    }
    if (isAndroid()) {
      final fd = await _androidChannel.invokeMethod<int>('start', {
        'routes': campusRoutes,
        'dns': session.dns,
      });
      if (fd == null || fd < 0) {
        return 'failed: the interface did not come up';
      }
      final tunnel = engine ?? AtrustTunnelService.load();
      if (!tunnel.isSupported) {
        await _androidChannel.invokeMethod<void>('stop');
        return 'failed: ${tunnel.unsupportedReason}';
      }
      tunnel.start(
        sessionJson: _sessionJson(session),
        policyJson: session.policyJson,
      );
      tunnel.attachTunFd(fd);
      return 'active';
    }
    return 'failed: the system tunnel is not available on this platform';
  }

  String _sessionJson(AtrustSession session) => jsonEncode({
    'sid': session.sid,
    'device_id': session.deviceId,
    'username': session.username,
    'base_url': session.baseUrl,
    'gateways': session.gateways,
    'dns': session.dns,
  });

  /// Takes the interface down and forgets the request. On Android the engine
  /// runs here, so it is stopped first.
  Future<void> stop({AtrustTunnelService? engine}) async {
    if (!isSupported) return;
    if (isAndroid()) {
      engine?.stop();
      await _androidChannel.invokeMethod<void>('stop');
      return;
    }
    await _ohosChannel.invokeMethod<void>('stop');
  }

  /// The extension's record (OHOS): `status`, `engineStatus` (the engine's own
  /// JSON), `routes`, `error`. Null when nothing was ever asked for, and null on
  /// Android, where the engine's own status is the answer.
  Future<Map<String, dynamic>?> status() async {
    if (!isOhos()) return null;
    final raw = await _ohosChannel.invokeMethod<String>('status');
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
