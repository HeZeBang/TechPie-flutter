// Run on an Android device: the aTrust system-VPN path, end to end, with no taps.
//
//   flutter run -d <serial> -t tool/android_atrust_smoke.dart
//
// It is a smoke test, not a unit test: everything here needs a real device, a
// real campus session and a real gateway. What it proves, in order:
//
//   1. the stored aTrust session is still good — the app restores it and reaches
//      the controller without an SMS, which is what "credentials survive a
//      restart" means;
//   2. the engine comes up, and the interface it is attached to does *not* route
//      the gateway the engine dials (the loop that killed the tunnel before);
//   3. traffic the device sends is carried: a campus address answers through it,
//      and the engine's own counters say it carried flows rather than dropping
//      them.
//
// The verdict is one line, `ANDROID_ATRUST_SMOKE COMPLETE failures=N`, printed to
// the log stream — the only channel a device gives us that a script can read.
//
// It deliberately does not log in: a fresh login would spend an SMS. A device
// with no stored session fails check 1 with that stated, which is the honest
// answer — run the app's developer lab once to log in.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/atrust_control_client.dart';
import 'package:techpie/services/atrust_routing.dart';
import 'package:techpie/services/atrust_tunnel_service.dart';
import 'package:techpie/services/atrust_vpn_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';

/// A campus address to reach through the tunnel. Literal on purpose: a name
/// would make a DNS failure look like a tunnel failure, and the point here is
/// the packet path.
const _campusAddress = 'http://10.15.89.181/';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var failures = 0;

  Future<void> check(String name, Future<String> Function() operation) async {
    try {
      final detail = await operation();
      debugPrint('[atrust] smoke ok   $name${detail.isEmpty ? '' : ': $detail'}');
    } on Object catch (error) {
      failures++;
      debugPrint('[atrust] smoke FAIL $name: $error');
    }
  }

  final storage = StorageService(await SharedPreferences.getInstance());
  final vpn = AtrustVpnService();
  final tunnel = AtrustTunnelService.load();
  final control = AtrustControlClient(
    http: LoggingHttpClient(DebugLogger()),
    storage: storage,
    // Only used when there is no stored session, which this smoke test does not
    // try to create — it reports that instead.
    castgc: () => '',
    clientType: AtrustClientType.desktop,
    onTrace: (stage) async => debugPrint('[atrust] $stage'),
  );

  // The first thing that touches the network after an install can catch a
  // teardown: the previous process's interface is still up for a moment, and
  // while it is, every lookup goes into a tunnel whose engine has already died.
  // Ask for a teardown first, then tolerate a few failed minutes of settling.
  final settling = <String>[];
  Future<String> retry(Future<String> Function() operation) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await operation();
      } on Object catch (error) {
        if (attempt >= 6) rethrow;
        settling.add('attempt $attempt: $error');
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  await vpn.stop(engine: tunnel);

  AtrustSession? session;
  await check('the stored session is still good (no SMS)', () async {
    final stage = await retry(() async {
      final state = await control.ensureOnline();
      if (state.stage != AtrustStage.online) {
        throw StateError('session not online: ${state.stage.name} ${state.hint}');
      }
      return state.stage.name;
    });
    if (settling.isNotEmpty) {
      debugPrint('[atrust] smoke settled: ${settling.join(' | ')}');
    }
    session = control.session;
    // Why a fresh login still costs an SMS: whether this device is on the
    // account's trusted-terminal list, and whether the campus allows binding at
    // all. Both are the controller's answers, not the app's guess. Reported as
    // information — a session that works is a pass even when this probe is not
    // answered.
    String trust;
    try {
      final state = await control.trustState();
      trust = 'trustDevice enable=${state.enable} '
          'currentTrustStatus=${state.currentTrustStatus} '
          'selfId=${state.selfId} devices=${state.devices.length}';
    } on Object catch (error) {
      trust = 'trustDevice query failed: $error';
    }
    return '$stage ${session!.username} trusted=${session!.trusted} '
        'gateways=${session!.gateways.length} · $trust';
  });

  final ready = session;
  if (ready == null) {
    debugPrint('ANDROID_ATRUST_SMOKE COMPLETE failures=$failures');
    exit(failures == 0 ? 0 : 1);
  }

  // The controller can reject a bind for account/device policy reasons even
  // while the session and data plane are healthy. Report that fact without
  // turning a tunnel smoke test red; the page exposes the same action for a
  // user who wants to retry it.
  if (ready.trusted) {
    debugPrint('[atrust] smoke info trusted-terminal: already trusted');
  } else {
    final bound = await control.bindDevice();
    final trust = await control.trustState();
    debugPrint(
      '[atrust] smoke info trusted-terminal: bound=$bound '
      'currentTrustStatus=${trust.currentTrustStatus} '
      'enable=${trust.enable} devices=${trust.devices.length}',
    );
  }

  if (!vpn.isSupported) {
    failures++;
    debugPrint('[atrust] smoke FAIL the system tunnel is not available here');
  } else {
    // A clean start: a VpnService that is already up keeps the routes it was
    // created with, so a second run would silently test the first run's.
    await vpn.stop(engine: tunnel);

    await check('the interface comes up with the gateways kept out of it',
        () async {
      final verdict = await vpn.start(ready, engine: tunnel);
      if (verdict != 'active') throw StateError(verdict);
      final status = tunnel.status();
      if (!status.alive) throw StateError('the engine is not alive');
      if (status.gateways.isEmpty) {
        throw StateError('the engine reports no gateway to keep out');
      }
      // The exclusion itself is the pure function the unit tests pin; what this
      // device run adds is that the engine really is up and really names the
      // gateways the interface must not carry.
      final routes = AtrustRouting.withoutGateways(
        AtrustVpnService.campusRoutes,
        status.gateways,
      );
      return 'alive at ${status.vip} via ${status.gateway}; '
          'gateways ${status.gateways} → ${routes.length} route entries';
    });

    await check('a campus address answers through the tunnel', () async {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      try {
        final request = await client.getUrl(Uri.parse(_campusAddress));
        final response = await request.close().timeout(const Duration(seconds: 20));
        await response.drain<void>();
        final peer = response.connectionInfo;
        if (response.statusCode >= 500) {
          throw StateError('HTTP ${response.statusCode}');
        }
        return 'HTTP ${response.statusCode} at ${peer?.remoteAddress.address}';
      } finally {
        client.close(force: true);
      }
    });

    await check('the engine carried flows rather than dropping them', () async {
      final tun = tunnel.status().tun;
      if (tun.isEmpty) throw StateError('nothing is attached to the engine');
      final flows = (tun['tcp_flows'] ?? 0) + (tun['udp_flows'] ?? 0);
      if (flows == 0) throw StateError('the interface carried no flows');
      if ((tun['refused_flows'] ?? 0) > 0) {
        throw StateError('${tun['refused_flows']} flows refused by the policy');
      }
      return tun.entries.map((entry) => '${entry.key}=${entry.value}').join(' ');
    });
  }

  // Leave the device as it was found. An interface whose engine died with this
  // process would route every campus destination into nothing, and the device
  // would keep doing it until someone noticed.
  await vpn.stop(engine: tunnel);

  debugPrint('ANDROID_ATRUST_SMOKE COMPLETE failures=$failures');
  exit(failures == 0 ? 0 : 1);
}
