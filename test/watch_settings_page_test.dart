import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';
import 'package:techpie/pages/watch_settings_page.dart';
import 'package:techpie/services/watch_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('techpie/watch-settings-test');
  late AppRuntime runtime;
  late WatchSyncService sync;
  late Map<String, dynamic> native;
  bool failStatus = false;

  setUp(() async {
    runtime = await buildDemoRuntime();
    failStatus = false;
    native = {
      'enabled': true,
      'ready': true,
      'revision': 9,
      'acknowledged': 9,
      'phoneExpiresAt': DateTime.utc(2099, 1, 2).millisecondsSinceEpoch / 1000,
      'watchExpiresAt': DateTime.utc(2099, 1, 2).millisecondsSinceEpoch / 1000,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (failStatus) {
        throw PlatformException(
            code: 'READ_FAILURE', message: 'DO_NOT_RECORD_PRIVATE_DETAILS',);
      }
      return native;
    });
    sync = WatchSyncService(
        runtime, SecureSessionCredentialStore(InMemorySecureCredentialStore()),
        channel: channel,);
    await sync.refreshStatus();
  });

  tearDown(() async {
    sync.dispose();
    await runtime.offlinePayments.dispose();
    await runtime.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(WidgetTester tester,
      {Brightness brightness = Brightness.light,}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF9D0A12), brightness: brightness,),),
      home: Scaffold(body: WatchSettingsContent(sync: sync)),
    ),);
    await tester.pumpAndSettle();
  }

  testWidgets('one summary is visible and transport details expand on demand',
      (tester) async {
    await mount(tester);
    expect(find.text('已同步'), findsOneWidget);
    expect(find.text('离线使用至 2099-01-01'), findsOneWidget);
    expect(find.text('手表已确认同步'), findsNothing);
    expect(find.text('手机授权有效期'), findsNothing);
    expect(find.text('手表授权有效期'), findsNothing);
    expect(find.text('更新并同步'), findsOneWidget);
    await tester.tap(find.text('同步详情'));
    await tester.pumpAndSettle();
    expect(find.text('手机授权有效期'), findsOneWidget);
    expect(find.text('手表授权有效期'), findsOneWidget);
    expect(find.text('本次操作记录'), findsOneWidget);
    expect(find.text('手表已确认同步'), findsOneWidget);
    await tester.tap(find.text('同步详情'));
    await tester.pumpAndSettle();
    expect(find.text('手机授权有效期'), findsNothing);
  });

  testWidgets(
      'pending or missing grants have one distinct status instead of duplicated notices',
      (tester) async {
    native['revision'] = 10;
    await sync.refreshStatus();
    await mount(tester);
    expect(find.text('等待手表接收'), findsOneWidget);
    expect(find.text('已同步'), findsNothing);
    native['acknowledged'] = 10;
    native.remove('watchExpiresAt');
    await sync.refreshStatus();
    await tester.pumpAndSettle();
    expect(find.text('待同步离线授权'), findsOneWidget);
    expect(find.text('手表已确认同步'), findsNothing);
  });

  test(
      'repeated status reads are deduplicated and old receipts do not erase failures',
      () async {
    for (var i = 0; i < 5; i++) {
      await sync.refreshStatus();
    }
    expect(sync.events, hasLength(1));
    failStatus = true;
    await sync.refreshStatus();
    expect(sync.hasError, isTrue);
    failStatus = false;
    await sync.refreshStatus();
    expect(sync.hasError, isTrue);
    native['revision'] = 10;
    native['acknowledged'] = 10;
    await sync.refreshStatus();
    expect(sync.hasError, isFalse);
    for (var i = 11; i < 36; i++) {
      failStatus = true;
      await sync.refreshStatus();
      failStatus = false;
      native['revision'] = i;
      native['acknowledged'] = i;
      await sync.refreshStatus();
    }
    expect(sync.events, hasLength(20));
    expect(sync.events.any((event) => event.text.contains('DO_NOT_RECORD')),
        isFalse,);
  });

  testWidgets('narrow dark layout and larger text do not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(body: WatchSettingsContent(sync: sync)),),
    ),);
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步详情'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
