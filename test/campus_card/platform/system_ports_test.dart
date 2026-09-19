import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/domain/models/feedback_models.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart';
import 'package:techpie/features/campus_card/platform/system_ports.dart';

/// The feature's port decides *whether* a waveform plays (its per-scenario
/// switches) and otherwise hands the request to the app's one dictionary. What
/// the phone is told to play is pinned in `test/haptics_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test('$platform is given the waveform, and only the sound it asked for',
        () async {
      debugDefaultTargetPlatformOverride = platform;
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
      final port = SystemFeedbackPort();

      await port.play(FeedbackEvent.paymentSuccess);
      expect(calls.single.method, 'play');
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['id'], 'paymentSuccess');
      expect(args['vibration'], isTrue);
      expect(args['sound'], isTrue);
      expect(args['soundAsset'], 'assets/campus_card/audio/payment-success.wav');
      expect(args['soundDurationMs'], 1397);
      final pulses = args['pulses'] as List<Object?>;
      expect(pulses, hasLength(2));
      final first = pulses.first as Map<Object?, Object?>;
      expect(first['atMs'], 0);
      expect(first['durationMs'], 18);
      expect(first['intensity'], 0.75);

      // Sound off: the waveform still plays, without the asset.
      await port.setEnabled(
        FeedbackScenario.paymentSuccess,
        FeedbackChannel.sound,
        false,
      );
      await port.play(FeedbackEvent.paymentSuccess);
      final muted = calls.last.arguments as Map<Object?, Object?>;
      expect(muted['vibration'], isTrue);
      expect(muted['sound'], isFalse);
      expect(muted.containsKey('soundAsset'), isFalse);

      // Vibration off too: nothing is played at all.
      await port.setEnabled(
        FeedbackScenario.paymentSuccess,
        FeedbackChannel.vibration,
        false,
      );
      await port.play(FeedbackEvent.paymentSuccess);
      expect(calls, hasLength(2));

      final restored = await SystemFeedbackPort()
          .settingsFor(FeedbackScenario.paymentSuccess);
      expect(restored.sound, isFalse);
      expect(restored.vibration, isFalse);
    });
  }

  test('the interaction switch gates its own waveforms', () async {
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
    final port = SystemFeedbackPort();
    await port.play(FeedbackEvent.success);
    expect(
      (calls.single.arguments as Map<Object?, Object?>)['id'],
      'success',
    );
    await port.setEnabled(
      FeedbackScenario.interaction,
      FeedbackChannel.vibration,
      false,
    );
    await port.play(FeedbackEvent.selection);
    await port.play(FeedbackEvent.success);
    expect(calls, hasLength(1));
  });

  test('a platform without a player is silent', () async {
    // No player on this host, and nothing pretends otherwise. The platform is
    // named explicitly because `flutter_test` defaults it to Android.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await SystemFeedbackPort().play(FeedbackEvent.success);
    expect(calls, isEmpty);
  });

  testWidgets('a slow player cannot block the action that asked for it',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('techpie/feedback');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
      if (!pending.isCompleted) pending.complete(null);
    });
    var completed = false;
    final playing =
        SystemFeedbackPort().play(FeedbackEvent.selection).then((_) => completed = true);
    await tester.pump(const Duration(milliseconds: 350));
    expect(completed, isTrue, reason: 'a vibration never holds up a payment');
    pending.complete(null);
    await playing;
    // The framework checks its debug variables at the end of the body.
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform
      in TargetPlatform.values.where((value) => value.name == 'ohos')) {
    test(
        'OHOS reports real connectivity and does not treat channel failures as online',
        () async {
      debugDefaultTargetPlatformOverride = platform;
      const channel = MethodChannel('techpie/campus_card');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(channel, null);
      });
      var online = false;
      messenger.setMockMethodCallHandler(channel, (_) async => online);
      final port = SystemConnectivityPort();
      expect(await port.isOnline(), isFalse);
      online = true;
      expect(await port.isOnline(), isTrue);
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'NETWORK_STATE_FAILED');
      });
      expect(await port.isOnline(), isFalse);
    });
  }
}
