import 'dart:convert';

import 'package:flutter/services.dart';

import '../utils/platform.dart';
import 'atrust_control_client.dart';

/// The **system-VPN** shape on OHOS: an interface the whole device routes
/// through, which is what reaches the campus from WebViews and from other apps —
/// something the in-app proxy cannot do.
///
/// Only a VPN extension can create an interface, so the extension process owns
/// the engine and this class only asks for it: it hands over the session, the
/// controller's policy and the destinations to route, and reads the extension's
/// verdict back. Everything the engine refuses is reported, never guessed at.
class AtrustVpnService {
  static const _channel = MethodChannel('techpie/geektrust_vpn');

  /// Campus destinations to route into the tunnel. Deliberately broad: the
  /// engine still authorizes every flow against the controller's policy, so a
  /// destination outside it is refused rather than leaked. IPv6 is not routed
  /// because the engine carries IPv4 only.
  static const campusRoutes = <String>[
    '10.0.0.0/8',
    '119.78.0.0/16',
    '59.78.0.0/16',
  ];

  /// Only OHOS has this shape here: Android would need its own `VpnService`
  /// shell, and the desktops use the proxy instead.
  bool get isSupported => isOhos();

  /// Raises the tunnel. Returns the extension's verdict: `active`, or a
  /// `failed: …` string carrying the engine's own words.
  Future<String> start(AtrustSession session) async {
    if (!isSupported) {
      return 'failed: the system tunnel is OHOS-only on this build';
    }
    // Plain strings across the channel: ArkTS refuses `any`, and JSON.parse is
    // typed as one, so lists travel joined.
    final status = await _channel.invokeMethod<String>('start', {
      'session': jsonEncode({
        'sid': session.sid,
        'device_id': session.deviceId,
        'username': session.username,
        'base_url': session.baseUrl,
        'gateways': session.gateways,
        'dns': session.dns,
      }),
      'policy': session.policyJson,
      'routes': campusRoutes.join(','),
      'dns': session.dns.join(','),
    });
    return status ?? 'failed: the extension said nothing';
  }

  /// Takes the interface down and forgets the request.
  Future<void> stop() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('stop');
  }

  /// The extension's record: `status`, `engineStatus` (the engine's own JSON),
  /// `routes`, `error`. Empty when nothing was ever asked for.
  Future<Map<String, dynamic>?> status() async {
    if (!isSupported) return null;
    final raw = await _channel.invokeMethod<String>('status');
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
