import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/pages/developer_lab_page.dart';
import 'package:techpie/utils/haptics.dart';

/// The developer lab exists to answer "what does this feel like on this phone".
/// These pin that it can: every waveform and every sound the app knows about has
/// a row, and a row asks for exactly the thing it names.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> mount(WidgetTester tester) async {
    // Tall enough that every row is built: the list is lazy, and a row that was
    // never laid out cannot be found (nor tapped) at all.
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DeveloperLabPage()));
    await tester.pump();
  }

  testWidgets('every waveform and every sound asset has a row', (tester) async {
    await mount(tester);
    for (final waveform in AppHaptics.all.values) {
      expect(find.text(waveform.id), findsWidgets, reason: waveform.id);
    }
    final assets = {
      for (final waveform in AppHaptics.all.values)
        if (waveform.soundAsset != null) waveform.soundAsset!,
    };
    expect(assets, isNotEmpty, reason: 'the lab is pointless without a sound');
    for (final asset in assets) {
      expect(
        find.text(asset.split('/').last),
        findsOneWidget,
        reason: asset,
      );
    }
  });

  testWidgets('a row asks for exactly what it names', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('techpie/feedback');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    await mount(tester);

    // A waveform row vibrates, and does not ask for its sound.
    await tester.tap(find.descendant(
      of: find.byKey(const Key('lab-haptics')),
      matching: find.text('tabHold'),
    ),);
    await tester.pump();
    final haptic = calls.single.arguments as Map<Object?, Object?>;
    expect(haptic['id'], 'tabHold');
    expect(haptic['vibration'], isTrue);
    expect(haptic['sound'], isFalse);

    // A sound row plays the asset, and does not vibrate.
    await tester.tap(find.descendant(
      of: find.byKey(const Key('lab-sounds')),
      matching: find.text('payment-success.wav'),
    ),);
    await tester.pump();
    final sound = calls.last.arguments as Map<Object?, Object?>;
    expect(sound['vibration'], isFalse);
    expect(sound['sound'], isTrue);
    expect(sound['soundAsset'], 'assets/campus_card/audio/payment-success.wav');

    // The designed pattern does both at once.
    await tester.tap(find.descendant(
      of: find.byKey(const Key('lab-together')),
      matching: find.text('paymentSuccess'),
    ),);
    await tester.pump();
    final both = calls.last.arguments as Map<Object?, Object?>;
    expect(both['id'], 'paymentSuccess');
    expect(both['vibration'], isTrue);
    expect(both['sound'], isTrue);
    expect(calls, hasLength(3));

    debugDefaultTargetPlatformOverride = null;
  });
}
