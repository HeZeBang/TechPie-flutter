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

  /// Nameservers to hand the interface. Empty here on purpose: the platform
  /// shell fills it in with the resolvers of the network the interface sits
  /// above.
  ///
  /// The policy hands out the *campus* resolver, and that one cannot answer for
  /// the aTrust controller (`vpn.shanghaitech.edu.cn` is an off-campus name), so
  /// pushing it made the app unable to reach the controller it had just
  /// authenticated against. Declaring *no* resolver is worse still: an interface
  /// with nowhere to ask becomes the device's default network and every lookup
  /// fails — measured with `ping vpn.shanghaitech.edu.cn` from the device shell
  /// answering "unknown host" while this interface was up.
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
    // The control plane is cut out of the routes on every platform: a destination
    // the interface carries cannot be reached by the code that drives it, and the
    // login's first request is to the controller itself (see
    // [AtrustRouting.controlPlaneHosts]). Resolved here, before the interface
    // exists, while the name still resolves the ordinary way.
    final controlPlane = await AtrustRouting.resolveHosts(
      AtrustRouting.controlPlaneHosts,
    );
    if (isOhos()) {
      // Plain strings across the channel: ArkTS refuses `any`, and JSON.parse is
      // typed as one, so lists travel joined.
      debugPrint('[atrust] asking the OHOS extension to raise the tunnel');
      final status = await _ohosChannel.invokeMethod<String>('start', {
        'session': _sessionJson(session),
        'policy': session.policyJson,
        'routes': AtrustRouting.withoutGateways(
          campusRoutes,
          controlPlane,
        ).join(','),
        'dns': session.dns.join(','),
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
      final routes = AtrustRouting.withoutGateways(campusRoutes, [
        ...gateways,
        ...controlPlane,
      ]);
      debugPrint(
        '[atrust] asking the VpnService for an interface: '
        '${routes.length} routes, gateways kept out of it: $gateways, '
        'control plane kept out: $controlPlane',
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

  /// Whether the platform says the interface is up.
  ///
  /// Asked rather than remembered: on Android the system's own VPN entry can
  /// disconnect it, and on OHOS the extension process can end on its own. Both
  /// happen outside the app, so the app asks instead of trusting its own last
  /// request.
  Future<bool> active() async {
    if (isAndroid()) {
      final verdict = await _androidChannel.invokeMethod<String>('status');
      return verdict == 'active';
    }
    if (isOhos()) {
      final state = await status();
      return state != null && state['status'] == 'active';
    }
    return false;
  }

  /// Keeps this app's process out of the system's background freezer while the
  /// tunnel is up: a `dataTransfer` long-running task, which is the OHOS
  /// counterpart of the foreground service the Android side raises. Without one
  /// the process is frozen as soon as the app leaves the foreground — and the
  /// tunnel, which this process drives, goes with it.
  Future<void> startContinuousTask() async {
    if (!isOhos()) return;
    await _ohosChannel.invokeMethod<bool>('startContinuousTask');
  }

  Future<void> stopContinuousTask() async {
    if (!isOhos()) return;
    await _ohosChannel.invokeMethod<bool>('stopContinuousTask');
  }

  /// Opens the system's battery-optimisation list, where this app can be exempted
  /// from the system reclaiming it in the background.
  Future<void> openBatterySettings() async {
    if (!isAndroid()) return;
    await _androidChannel.invokeMethod<void>('openBatterySettings');
  }

  /// Takes the system interface down, and answers whether it really went.
  ///
  /// The engine is not touched. It is the tunnel, and this interface sits above
  /// it: stopping the engine here is what made "close the system proxy" mean
  /// "close the tunnel" as well, which the two controls are deliberately
  /// separate about. The tunnel's own stop is what takes this interface down
  /// with it — see `AtrustService.stopTunnel`.
  ///
  /// The answer is not a formality: the platform may hold the service for the
  /// interface it carries. Measured on Android 12 (MAA-AN00): `stopSelf()` with
  /// the descriptor open was acknowledged and changed nothing — the service, the
  /// interface and its 56 routes stayed — because the VPN framework binds a
  /// service whose interface exists; with the descriptor closed the service went
  /// and the framework immediately started it again; and the interface is
  /// released, every time, when the app's process ends. A caller that assumed
  /// success would draw a switch that is off over an interface that is on, so
  /// the verdict is read back from the service and the switch follows it.
  ///
  /// (OHOS is the exception in the other direction: there the extension owns the
  /// engine, so its teardown is both layers at once.)
  Future<bool> stop() async {
    if (!isSupported) return true;
    if (isAndroid()) {
      debugPrint('[atrust] asking the VpnService to take its interface down');
      final verdict = await _androidChannel.invokeMethod<String>('stop');
      debugPrint('[atrust] interface is $verdict');
      return verdict != 'active';
    }
    // OHOS: the extension owns both layers — its teardown is the tunnel's — so
    // the verdict is read back rather than assumed.
    await _ohosChannel.invokeMethod<void>('stop');
    return !await active();
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
