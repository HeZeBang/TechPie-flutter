import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/platform.dart';
import 'atrust_control_client.dart';
import 'atrust_routing.dart';
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
  ///
  /// The extension cuts the tunnel's own gateways out of these before it hands
  /// them to the interface: they are campus addresses, so they fall inside these
  /// ranges, and a gateway routed into the interface it carries is a loop the
  /// engine refuses. The flattened gateway list exists only inside the engine,
  /// so that subtraction is the extension's — see GeekTrustVpnRoutes.ets.
  static const campusRoutes = <String>[
    '10.0.0.0/8',
    '119.78.0.0/16',
    '59.78.0.0/16',
  ];

  /// Nameservers for the interface — deliberately none.
  ///
  /// The policy hands out the campus resolver, and pushing it makes the tunnel
  /// the device's only resolver. The campus resolver does not answer for the
  /// aTrust controller (`vpn.shanghaitech.edu.cn` is an off-campus name), so
  /// raising the system VPN made the app unable to reach the controller it had
  /// just authenticated against: login, session refresh and trusted-terminal
  /// queries all failed with "unknown host" until the VPN was switched off.
  ///
  /// Leaving this empty keeps the device on the resolver its network gave it.
  /// Measured on a phone: with the VPN up and the policy DNS pushed, the name
  /// did not resolve; with it empty, it did. The cost is split-horizon names the
  /// policy DNS exists for — `netinfo.shanghaitech.edu.cn` and the like — which
  /// the app's own campus hosts do not depend on.
  static const interfaceDns = <String>[];

  /// OHOS and Android; the desktops use the proxy shape instead.
  bool get isSupported => isOhos() || isAndroid();

  /// Raises the tunnel. Returns the extension's verdict: `active`, or a
  /// `failed: …` string carrying the engine's own words.
  ///
  /// On Android the engine runs in this same process, so the interface's
  /// descriptor comes back over the channel and goes straight to it. On OHOS the
  /// extension process owns both, and only a verdict comes back.
  Future<String> start(
    AtrustSession session, {
    AtrustTunnelService? engine,
  }) async {
    if (isOhos()) {
      // Plain strings across the channel: ArkTS refuses `any`, and JSON.parse is
      // typed as one, so lists travel joined.
      debugPrint('[atrust] asking the OHOS extension to raise the tunnel');
      final status = await _ohosChannel.invokeMethod<String>('start', {
        'session': _sessionJson(session),
        'policy': session.policyJson,
        'routes': campusRoutes.join(','),
        'dns': '',
      });
      return status ?? 'failed: the extension said nothing';
    }
    if (isAndroid()) {
      // The engine has to be up — and its gateway list known — *before* the
      // interface exists:
      //
      //  * a gateway is where the tunnel begins, so it must stay outside the
      //    interface that carries it. A gateway covered by these routes is
      //    captured by the very interface they configure, the device side
      //    refuses the engine's own dial (`ErrGatewayLoop`), and the tunnel dies
      //    with it. Only the engine knows the flattened list, so it is read off
      //    its own status — see [AtrustRouting.withoutGateways].
      //  * `geektrust_attach_tun_fd` refuses a tunnel that is not alive yet.
      //
      // The OHOS extension does the same, in the same order, for the same
      // reason; this is the Android spelling of it.
      final tunnel = engine ?? AtrustTunnelService.load();
      if (!tunnel.isSupported) {
        return 'failed: ${tunnel.unsupportedReason}';
      }
      tunnel.start(
        sessionJson: _sessionJson(session),
        policyJson: session.policyJson,
      );
      if (!await _waitForAlive(tunnel)) {
        return 'failed: the engine never reported a live tunnel';
      }
      final gateways = tunnel.status().gateways;
      final routes = AtrustRouting.withoutGateways(campusRoutes, gateways);
      debugPrint(
        '[atrust] asking the VpnService for an interface: '
        '${routes.length} routes, gateways kept out of it: $gateways',
      );
      final fd = await _androidChannel.invokeMethod<int>('start', {
        'routes': routes,
        'dns': interfaceDns,
      });
      if (fd == null || fd < 0) {
        await _androidChannel.invokeMethod<void>('stop');
        return 'failed: the interface did not come up';
      }
      tunnel.attachTunFd(fd);
      debugPrint('[atrust] tunnel attached to fd $fd');
      return 'active';
    }
    return 'failed: the system tunnel is not available on this platform';
  }

  /// How long the engine is given to dial the gateway, and how often it is asked.
  /// The same numbers the OHOS extension waits with: the same engine, the same
  /// dial, the same deadline.
  static const _engineTimeout = Duration(seconds: 20);
  static const _enginePoll = Duration(milliseconds: 150);

  /// Waits for the engine to report a live tunnel. It dials the gateway in the
  /// background, so nothing may be attached before that — `geektrust_status` is
  /// the only thing that says when.
  Future<bool> _waitForAlive(AtrustTunnelService tunnel) async {
    final deadline = DateTime.now().add(_engineTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (tunnel.status().alive) return true;
      await Future<void>.delayed(_enginePoll);
    }
    return false;
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
