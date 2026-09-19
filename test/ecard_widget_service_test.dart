import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart';
import 'package:techpie/services/ecard_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('warm widget taps reuse the mounted payment target',
      (tester) async {
    const channel = MethodChannel('test/ecard_widget_warm');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = EcardWidgetService(channel: channel);
    addTearDown(service.dispose);
    var root = 0;
    var existing = 0;
    service.initialize();
    service.setOpenPayHandler(() async => root++);
    final remove = service.registerPaymentTarget(() async => existing++);

    await _tapWidget(channel);
    await _tapWidget(channel);
    expect(root, 0);
    expect(existing, 2);
    remove();
    await _tapWidget(channel);
    expect(root, 1);
  });

  testWidgets('a second tap during startup targets the newly mounted page',
      (tester) async {
    const channel = MethodChannel('test/ecard_widget_pending');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = EcardWidgetService(channel: channel);
    addTearDown(service.dispose);
    final mounted = Completer<void>();
    var roots = 0;
    var existing = 0;
    service.initialize();
    service.setOpenPayHandler(() async {
      roots++;
      await mounted.future;
    });
    final first = _tapWidget(channel);
    await tester.pump();
    await _tapWidget(channel);
    service.registerPaymentTarget(() async => existing++);
    mounted.complete();
    await first;
    await tester.pump();
    expect(roots, 1);
    expect(existing, 1);
  });

  test('widget installation uses the native capability and pin request',
      () async {
    const channel = MethodChannel('test/ecard_widget_pin');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'widgetAvailability' ? 'nativePin' : true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = EcardWidgetService(channel: channel);
    expect(await service.availability(), HomeWidgetAvailability.nativePin);
    expect(await service.requestPin(), isTrue);
    expect(calls, ['widgetAvailability', 'requestPinWidget']);
    await service.dispose();
  });

  testWidgets(
      'cold-start eCard link opens after the navigator handler attaches', (
    tester,
  ) async {
    const channel = MethodChannel('test/ecard_deep_link');
    final nativeCalls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'consumePendingRoute') return 'pay';
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = EcardWidgetService(channel: channel);
    addTearDown(service.dispose);
    var opened = 0;

    service.initialize();
    await tester.pump();
    service.setOpenPayHandler(() async => opened += 1);
    await tester.pump();

    expect(opened, 1);
    expect(nativeCalls, ['consumePendingRoute', 'acknowledgePendingRoute']);
  });
}

Future<void> _tapWidget(MethodChannel channel) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    channel.name,
    const StandardMethodCodec()
        .encodeMethodCall(const MethodCall('openPayCode')),
    (_) {},
  );
}
