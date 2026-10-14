import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/auth/ecard_bind_code_client.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/services/ecard_bind_hijack.dart';
import 'package:techpie/services/ecard_bind_service.dart';

/// The eCard page drives the bind-code path through this facade: it owns the
/// tunnel's state, hands back a plain OPENID, and stores nothing itself, so
/// `CampusCardService` stays the only writer of the account.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('stopHijack rejects a tunnel that still reports active', () async {
    final service = serviceIssuing();
    await service.startHijack();
    tunnel.stayActiveAfterStop = true;

    await expectLater(
      service.stopHijack(),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code, 'code', 'ECARD_BIND_STOP_FAILED',
        ),
      ),
    );
    expect(service.hijackActive, isTrue);
  });

  test('a pending status read cannot overwrite a completed stop', () async {
    final service = serviceIssuing();
    await service.startHijack();
    final statusReply = Completer<EcardBindHijackStatus>();
    tunnel.statusReply = () => statusReply.future;
    final pendingStatus = service.refreshStatus();
    await Future<void>.delayed(Duration.zero);
    tunnel.statusReply = null;
    final stopping = service.stopHijack();
    await Future<void>.delayed(Duration.zero);
    final stopsBeforeStatusReply = tunnel.stopCalls;
    statusReply.complete(EcardBindHijackStatus.active);
    await pendingStatus;
    await stopping;

    expect(stopsBeforeStatusReply, 0);
    expect(service.status, EcardBindHijackStatus.inactive);
  });

  test('a failed DNS lookup cannot pass the account connection gate', () async {
    final service = EcardBindService(
      hijack: tunnel,
      resolve: (_) async => throw const SocketException('unavailable'),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.prepareCampusConnection(),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code, 'code', 'ECARD_BIND_DNS_UNAVAILABLE',
        ),
      ),
    );
  });

  test('unsupported tunnel allows normal campus DNS without stopping', () async {
    tunnel.current = EcardBindHijackStatus.unsupported;
    final service = EcardBindService(
      hijack: tunnel,
      resolve: (_) async => ['10.17.0.54'],
    );
    addTearDown(service.dispose);

    await service.prepareCampusConnection();

    expect(service.status, EcardBindHijackStatus.unsupported);
    expect(service.hijackNeedsStop, isFalse);
    expect(tunnel.stopCalls, 0);
  });

  test('unsupported tunnel still rejects DNS pointing at the bind service', () async {
    tunnel.current = EcardBindHijackStatus.unsupported;
    final service = EcardBindService(
      hijack: tunnel,
      resolve: (_) async => [EcardBindHijackService.targetIp],
    );
    addTearDown(service.dispose);

    await expectLater(
      service.prepareCampusConnection(),
      throwsA(
        isA<AppFailure>()
            .having((failure) => failure.code, 'code', 'ECARD_BIND_DNS_NOT_RESTORED'),
      ),
    );
    expect(tunnel.stopCalls, 0);
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

  test('iOS uses the native bind tunnel channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('techpie/ecard_bind');
    final calls = <String>[];
    var active = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'start':
              active = true;
              expect(call.arguments, {
                'host': EcardBindHijackService.host,
                'ip': EcardBindHijackService.targetIp,
              });
              return 'active';
            case 'stop':
              active = false;
              return null;
            case 'status':
              return active ? 'active' : 'inactive';
          }
          fail('unexpected method: ${call.method}');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final ios = EcardBindHijackService();
    expect(await ios.start(), EcardBindHijackStatus.active);
    expect(await ios.status(), EcardBindHijackStatus.active);
    await ios.stop();
    expect(await ios.status(), EcardBindHijackStatus.inactive);
    expect(calls, ['start', 'status', 'stop', 'status']);
  });

  test('missing native host reports unsupported', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final ios = EcardBindHijackService();

    expect(await ios.start(), EcardBindHijackStatus.unsupported);
    expect(await ios.status(), EcardBindHijackStatus.unsupported);
  });

  test('native stop failures reach the caller', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('techpie/ecard_bind');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'ECARD_TUNNEL_STILL_ACTIVE');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await expectLater(
      EcardBindHijackService().stop(), throwsA(isA<PlatformException>()),
    );
  });

  test('a failed or malformed status response never confirms a stopped tunnel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('techpie/ecard_bind');
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    for (final reply in [null, 'connecting', 'status-error']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'stop') return null;
            if (reply == 'status-error') {
              throw PlatformException(code: 'PREFERENCES_UNAVAILABLE');
            }
            return reply;
          });
      final service = EcardBindService();
      addTearDown(service.dispose);
      await expectLater(service.stopHijack(), throwsA(isA<AppFailure>()));
    }
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
    // The line shows what the service actually answered, not just the status.
    expect(diagnosis.healthLine, contains('{"ok": true, "codes": 0}'));
    expect(diagnosis.healthLine, contains('绑定服务正常'));
  });

  test('diagnose reports the campus address as an unhijacked host', () async {
    final diagnosis = await diagnoseService(
      resolve: (host) async => <String>['10.17.0.54'],
      health: (404, '<html>not found</html>'),
    ).diagnose();

    expect(diagnosis.routesToBindService, isFalse);
    expect(diagnosis.reachable, isFalse);
  });

  test('a 200 without the service ok is refused', () async {
    // The bind service answers `ok` when it did something with the code, and
    // something else on that host — the campus itself — answers 200 without it.
    for (final body in <String>[
      '{"openid":"SYNTHETIC_OPENID_FROM_CODE"}',
      '{"ok":false,"openid":"SYNTHETIC_OPENID_FROM_CODE"}',
    ]) {
      final service = EcardBindService(
        hijack: tunnel,
        client: EcardBindCodeClient(
          send: (method, url, headers, request) async => (200, body),
        ),
      );
      await expectLater(
        service.redeem('SYNTHETIC-CODE'),
        throwsA(
          isA<AppFailure>()
              .having((failure) => failure.kind, 'kind', FailureKind.protocol),
        ),
        reason: 'body was $body',
      );
    }
  });

  test('a 200 that is not the bind service is not healthy', () async {
    final diagnosis = await diagnoseService(
      resolve: (host) async => <String>['119.78.254.196'],
      health: (200, '{"ok": false, "codes": 0}'),
    ).diagnose();

    expect(diagnosis.routesToBindService, isTrue);
    expect(diagnosis.reachable, isFalse);
    expect(diagnosis.healthLine, contains('{"ok": false, "codes": 0}'));
    expect(diagnosis.healthLine, contains('响应异常'));
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
  bool stayActiveAfterStop = false;
  Future<EcardBindHijackStatus> Function()? statusReply;

  @override
  Future<EcardBindHijackStatus> start() async {
    startCalls += 1;
    current = EcardBindHijackStatus.active;
    return current;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    if (!stayActiveAfterStop) current = EcardBindHijackStatus.inactive;
  }

  @override
  Future<EcardBindHijackStatus> status() async =>
      statusReply == null ? current : await statusReply!();
}
