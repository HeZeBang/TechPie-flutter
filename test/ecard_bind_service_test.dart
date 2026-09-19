import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/auth/ecard_bind_code_client.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/services/ecard_bind_hijack.dart';
import 'package:techpie/services/ecard_bind_service.dart';

/// The eCard page drives the bind-code path through this facade: it owns the
/// tunnel's state, hands back a plain OPENID, and stores nothing itself, so
/// `CampusCardService` stays the only writer of the account.
void main() {
  late _ScriptedTunnel tunnel;
  late List<String> bodies;

  setUp(() {
    tunnel = _ScriptedTunnel();
    bodies = <String>[];
  });

  EcardBindService serviceIssuing({String userType = '8'}) => EcardBindService(
    hijack: tunnel,
    client: EcardBindCodeClient(
      send: (method, url, headers, body) async {
        bodies.add(body);
        return (
          200,
          '{"ok":true,"openid":"SYNTHETIC_OPENID_FROM_CODE","usertype":"$userType","orgid":"2"}',
        );
      },
    ),
  );

  /// A service whose client answers the health probe with [health] and the
  /// exchange with a valid payload.
  EcardBindService diagnoseService({
    required Future<List<String>> Function(String host) resolve,
    required (int, String) health,
  }) {
    tunnel.current = EcardBindHijackStatus.active;
    return EcardBindService(
      hijack: tunnel,
      client: EcardBindCodeClient(
        send: (method, url, headers, body) async =>
            method == 'GET' ? health : (200, '{"ok":true,"openid":"SYNTHETIC"}'),
      ),
      resolve: resolve,
    );
  }

  test('startHijack mirrors the platform and notifies only on a change', () async {
    final service = serviceIssuing();
    var notifications = 0;
    service.addListener(() => notifications += 1);

    expect(service.hijackActive, isFalse);

    expect(await service.startHijack(), EcardBindHijackStatus.active);
    expect(service.hijackActive, isTrue);
    // A second start for the same answer must not rebuild the page again.
    await service.startHijack();

    expect(tunnel.startCalls, 2);
    expect(notifications, 1);
  });

  test('stopHijack asks the platform and records the result', () async {
    final service = serviceIssuing();
    await service.startHijack();

    await service.stopHijack();

    expect(tunnel.stopCalls, 1);
    expect(service.status, EcardBindHijackStatus.inactive);
    expect(service.hijackActive, isFalse);
  });

  test('redeem returns the OPENID with the channel the code was issued for', () async {
    final service = serviceIssuing(userType: '18');

    final redeemed = await service.redeem(' ab12cd ');

    expect(redeemed.openId, 'SYNTHETIC_OPENID_FROM_CODE');
    expect(redeemed.channel, EcardOpenIdChannel.alipay);
    expect(bodies, ['{"code":"AB12CD"}']);
  });

  test('redeem leaves the tunnel up so the caller decides when to stop it', () async {
    final service = serviceIssuing();
    await service.startHijack();

    await service.redeem('AB12CD');

    expect(tunnel.stopCalls, 0);
    expect(service.hijackActive, isTrue);
  });

  test('the tunnel reports unsupported where there is no VpnService', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final android = EcardBindHijackService();

    expect(await android.start(), EcardBindHijackStatus.unsupported);
    expect(await android.status(), EcardBindHijackStatus.unsupported);
  });

  test('diagnose separates a hijacked host from an answering bind service', () async {
    final diagnosis = await diagnoseService(
      resolve: (host) async => <String>['119.78.254.196'],
      health: (200, '{"ok": true, "codes": 0}'),
    ).diagnose();

    expect(diagnosis.status, EcardBindHijackStatus.active);
    expect(diagnosis.routesToBindService, isTrue);
    expect(diagnosis.reachable, isTrue);
    expect(diagnosis.lookupError, isNull);
    expect(diagnosis.healthError, isNull);
  });

  test('diagnose reports the campus address as an unhijacked host', () async {
    final diagnosis = await diagnoseService(
      resolve: (host) async => <String>['10.17.0.54'],
      health: (404, '<html>not found</html>'),
    ).diagnose();

    expect(diagnosis.routesToBindService, isFalse);
    expect(diagnosis.reachable, isFalse);
  });

  test('diagnose keeps going when a step throws', () async {
    final diagnosis = await diagnoseService(
      resolve: (host) async => throw const SocketException('no address'),
      health: (503, ''),
    ).diagnose();

    expect(diagnosis.lookupError, isNotEmpty);
    expect(diagnosis.addresses, isEmpty);
    expect(diagnosis.reachable, isFalse);
  });
}

final class _ScriptedTunnel implements EcardBindHijackPort {
  EcardBindHijackStatus current = EcardBindHijackStatus.inactive;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<EcardBindHijackStatus> start() async {
    startCalls += 1;
    current = EcardBindHijackStatus.active;
    return current;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    current = EcardBindHijackStatus.inactive;
  }

  @override
  Future<EcardBindHijackStatus> status() async => current;
}
