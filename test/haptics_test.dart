import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/haptics.dart';

/// The app's vibration dictionary is the single source of what a tap, a success
/// or a lost connection feels like; these pin the shape of a waveform and the
/// payload a phone is given for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every waveform is a short, ordered, in-range pattern', () {
    for (final waveform in AppHaptics.all.values) {
      expect(AppHaptics.all[waveform.id], same(waveform));
      expect(waveform.pulses, isNotEmpty);
      var cursor = 0;
      for (final pulse in waveform.pulses) {
        expect(pulse.durationMs, greaterThanOrEqualTo(3));
        expect(
          pulse.atMs,
          greaterThanOrEqualTo(cursor),
          reason: '${waveform.id} must not overlap its own pulses',
        );
        expect(pulse.intensity, inInclusiveRange(0, 1));
        expect(pulse.sharpness, inInclusiveRange(0, 1));
        cursor = pulse.endMs;
      }
      // The whole point of the dictionary: a platform default can hold a motor
      // on for a quarter of a second, which reads as an alarm, not as feedback.
      expect(
        waveform.durationMs,
        lessThanOrEqualTo(250),
        reason: '${waveform.id} has to stay a tick',
      );
    }
  });

  test('only the two designed patterns carry a sound', () {
    expect(AppHaptics.paymentSuccess.soundAsset, isNotNull);
    expect(AppHaptics.paymentSuccess.soundDurationMs, isNotNull);
    expect(AppHaptics.networkDisconnected.soundAsset, isNotNull);
    expect(AppHaptics.networkDisconnected.soundDurationMs, isNotNull);
    for (final waveform in AppHaptics.all.values) {
      if (waveform.id == 'paymentSuccess' ||
          waveform.id == 'networkDisconnected') {
        continue;
      }
      expect(waveform.soundAsset, isNull, reason: waveform.id);
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform is given the pulse plan', () async {
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

      await AppHaptics.play(AppHaptics.tabHold);
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['id'], 'tabHold');
      expect(args['vibration'], isTrue);
      expect(args['sound'], isFalse, reason: 'tabHold has no sound');
      final pulses = args['pulses'] as List<Object?>;
      expect(pulses, hasLength(1));
      expect((pulses.single as Map<Object?, Object?>)['durationMs'], 14);

      await AppHaptics.play(AppHaptics.networkDisconnected, sound: true);
      final withSound = calls.last.arguments as Map<Object?, Object?>;
      expect(withSound['sound'], isTrue);
      expect(
        withSound['soundAsset'],
        'assets/campus_card/audio/network-disconnected.wav',
      );
      expect(withSound['soundDurationMs'], 1104);

      // Nothing to play: no call at all.
      await AppHaptics.play(AppHaptics.error, vibration: false);
      expect(calls, hasLength(2));
    });
  }

  test('a platform without a player stays silent', () async {
    // `flutter_test` puts the default platform at Android; this test is about
    // the hosts that have no player at all.
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
    expect(AppHaptics.hasPlayer, isFalse);
    await AppHaptics.play(AppHaptics.success);
    expect(calls, isEmpty);
  });

  test('a player that never answers does not hold the caller', () async {
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
    await AppHaptics.play(AppHaptics.mediumImpact).timeout(
      const Duration(seconds: 2),
      onTimeout: () => fail('AppHaptics.play must give up on its own'),
    );
  });
}
