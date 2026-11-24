import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/pages/huawei_watch_page.dart';
import 'package:techpie/services/wear/wear_engine_service.dart';
import 'package:techpie/services/wear/wear_protocol.dart';

import 'wear_engine_service_test.dart' show Peer, Source, MemoryMetadata, fingerprint, testNow;

class DevicePeer extends Peer {
  @override
  Future<List<Map<String, dynamic>>> devices() async => [
        {'id': 'watch', 'name': 'GT 6 Pro', 'connected': true},
        {'id': 'offline', 'name': 'GT 3', 'connected': false},
      ];
}

class PingFailurePeer extends DevicePeer {
  PingFailurePeer(this.code);
  final int code;

  @override
  Future<void> open(String deviceId, String fingerprint) async =>
      throw WearFailure('PEER_NOT_READY', nativeCode: code);
}

class ScopeFailurePeer extends DevicePeer {
  @override
  Future<Map<String, dynamic>> authorize({required bool notify}) async =>
      throw const WearFailure('SERVICE_UNAVAILABLE', nativeCode: 8);
}

void main() {
  testWidgets('SDK authorization failure shows code without claiming empty device list',
      (tester) async {
    final service = WearEngineService(
      transport: ScopeFailurePeer(),
      source: Source(),
      metadata: MemoryMetadata(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HuaweiWatchContent(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('授权并查找手表'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SDK 错误码：8'), findsOneWidget);
    expect(find.text('尚未发现手表，请完成配对后重新查找。'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
  for (final entry in {200: '未找到匹配的手表应用', 201: '请在手表上打开 TechPie'}.entries) {
    testWidgets('watch ping ${entry.key} shows the matching recovery action', (tester) async {
      final service = WearEngineService(
        transport: PingFailurePeer(entry.key),
        source: Source(),
        metadata: MemoryMetadata(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HuaweiWatchContent(service: service))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('授权并查找手表'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('GT 6 Pro'));
      await tester.tap(find.text('GT 6 Pro'));
      await tester.pumpAndSettle();
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(find.textContaining('SDK 错误码：${entry.key}'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });
  }
  testWidgets('connection-only watch capability and heartbeat loss are reflected accurately',
      (tester) async {
    final peer = DevicePeer()..capabilities = ['account.display', 'connection.heartbeat'];
    final service = WearEngineService(
      transport: peer,
      source: Source(),
      metadata: MemoryMetadata(),
      now: () => testNow,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HuaweiWatchContent(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    final opened = service.open('watch', watchFingerprint: fingerprint);
    await tester.pumpAndSettle();
    await opened;
    expect(peer.received.where((m) => m['type'] == 'ddl.snapshot'), isEmpty);
    expect(find.text('张三'), findsOneWidget);
    peer.ignoreHeartbeat = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 9));
    expect(service.ready, true); // One missing heartbeat can be a transient send failure.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 9));
    expect(service.ready, false);
    expect(find.text('张三'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
  testWidgets('unsupported platform keeps connection guide visible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HuaweiWatchContent(service: null)),
      ),
    );
    expect(find.text('等待首次配对'), findsOneWidget);
    expect(find.textContaining('Android 手机'), findsOneWidget);
    expect(find.text('暂无设备用户'), findsOneWidget);
  });

  testWidgets('authorization lists devices; handshake shows user; disconnect hides user',
      (tester) async {
    final peer = DevicePeer();
    final service = WearEngineService(
      transport: peer,
      source: Source(),
      metadata: MemoryMetadata(),
      now: () => testNow,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HuaweiWatchContent(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('等待首次配对'), findsOneWidget);
    await tester.tap(find.text('授权并查找手表'));
    await tester.pumpAndSettle();
    expect(find.text('GT 6 Pro'), findsOneWidget);
    final offlineTile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'GT 3'));
    expect(offlineTile.enabled, false);
    final opened = service.open('watch', watchFingerprint: fingerprint);
    await tester.pumpAndSettle();
    await opened;
    expect(find.text('正在同步'), findsOneWidget);
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('学号：00123'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('暂停自动同步'), 240);
    await tester.tap(find.text('暂停自动同步'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('等待首次配对'), -240);
    expect(find.text('等待首次配对'), findsOneWidget);
    expect(find.text('张三'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
