// What a stop must do on a platform that will not release the interface.
//
// Measured on a device: `stopSelf()`, `stopService()` and closing the
// descriptor all leave the interface (and its routes) up, because the VPN
// framework binds a service for as long as its interface exists. The one lever
// that works — the system's own VPN entry, whose revoke tears it down — is the
// user's, not the app's. So the app's contract is:
//
//  * a stop the platform refuses keeps the tunnel running (an interface whose
//    routes outlive its engine drops every campus destination into a descriptor
//    nobody reads), and says where the interface can be released;
//  * the ask is remembered, and the system's disconnect finishes it.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/atrust_service.dart';
import 'package:techpie/services/atrust_vpn_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';

/// A platform that refuses to release the interface until it is told to.
class _PlatformVpn extends AtrustVpnService {
  _PlatformVpn({required this.releases});

  /// Whether a teardown this side actually takes the interface down.
  bool releases;

  /// Whether the platform reports an interface as up.
  bool up = true;

  @override
  Future<bool> stop() async {
    if (releases) up = false;
    return releases;
  }

  @override
  Future<bool> active() async => up;
}

void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
    // The service paths that matter here are the mobile ones, and the platform
    // is what decides which those are.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  AtrustService serviceWith(_PlatformVpn vpn) => AtrustService(
        http: LoggingHttpClient(
          DebugLogger(),
          inner: MockClient((_) async {
            throw UnimplementedError('no network in this test');
          }),
        ),
        storage: storage,
        castgc: () => '',
        vpn: vpn,
        // No engine here: AtrustTunnelService.load() answers an unsupported
        // instance rather than throwing, and stopping one is a no-op.
      );

  test('a refused stop keeps the interface honest and points at the system',
      () async {
    final vpn = _PlatformVpn(releases: false);
    final service = serviceWith(vpn);
    // The platform says an interface is up — the state a stop finds itself in.
    await service.refreshSystemVpn();
    expect(service.systemVpnActive, isTrue);

    await service.stopTunnel();

    expect(service.systemVpnActive, isTrue);
    expect(service.detail, contains('系统 VPN 未释放'));
  });

  test('the system letting go afterwards finishes the remembered stop',
      () async {
    final vpn = _PlatformVpn(releases: false);
    final service = serviceWith(vpn);
    await service.refreshSystemVpn();
    await service.stopTunnel();
    expect(service.detail, contains('未释放'));

    // The user does in the system what the app could not.
    vpn.up = false;
    await service.refreshSystemVpn();

    expect(service.systemVpnActive, isFalse);
    expect(service.detail, contains('隧道已停止'));
  });

  test('a stop the platform honours is a plain stop', () async {
    final vpn = _PlatformVpn(releases: true);
    final service = serviceWith(vpn);
    await service.refreshSystemVpn();

    await service.stopTunnel();

    expect(service.systemVpnActive, isFalse);
    expect(service.detail, contains('隧道已停止'));
  });
}
