import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform.dart';

/// One vibration pulse: when it starts, how long it lasts, how strong it is.
///
/// Pulses are the unit every platform can be given: Android plays them as one
/// `VibrationEffect` waveform, iOS as Core Haptics transients, and OHOS either
/// as a motor pattern (API 19 and an HD motor) or as a schedule of short
/// vibrations.
@immutable
final class AppHapticPulse {
  const AppHapticPulse({
    required this.atMs,
    required this.durationMs,
    required this.intensity,
    this.sharpness = 0.5,
  });

  /// Milliseconds after the start of the waveform.
  final int atMs;

  /// Milliseconds the pulse lasts. Short is what makes a tick feel like a tick:
  /// the platform APIs behind this can hold a motor on for hundreds.
  final int durationMs;

  /// Fraction of the motor's amplitude, 0..1. Android maps it to 0..255 and iOS
  /// to `hapticIntensity`; a platform that cannot express it plays the pulse at
  /// its own default rather than skipping it.
  final double intensity;

  /// Core Haptics only: 0 is dull, 1 is crisp. Ignored by the other platforms.
  final double sharpness;

  int get endMs => atMs + durationMs;

  Map<String, Object?> toJson() => {
        'atMs': atMs,
        'durationMs': durationMs,
        'intensity': intensity,
        'sharpness': sharpness,
      };
}

/// A named waveform, optionally with the sound that plays with it.
///
/// The dictionary below is the single source of vibration in the app: the
/// feature's settings screen, the host's navigation bar and the eCard events all
/// name a waveform from [AppHaptics] instead of each carrying its own idea of
/// what a tap or a success feels like.
@immutable
final class AppHapticWaveform {
  const AppHapticWaveform({
    required this.id,
    required this.pulses,
    this.soundAsset,
    this.soundDurationMs,
  });

  final String id;
  final List<AppHapticPulse> pulses;

  /// Played with the waveform, on the platforms that can play one.
  final String? soundAsset;

  /// How long the sound runs: the player keeps its session alive for this long,
  /// which is usually longer than the vibration itself.
  final int? soundDurationMs;

  int get durationMs =>
      pulses.fold(0, (longest, pulse) => pulse.endMs > longest ? pulse.endMs : longest);
}

/// The app's vibration dictionary, and the one place that plays it.
///
/// Mechanism only: whether a waveform plays at all belongs to the caller (the
/// eCard settings screen owns per-scenario vibration and sound switches), and a
/// platform without a player does nothing at all. It is deliberately not faked
/// with `HapticFeedback`: that would give the same action two different feels
/// depending on the device, which is the problem this library exists to remove.
abstract final class AppHaptics {
  /// Long-press on the bottom bar, matching what the client we ported it from
  /// does on a held tab (`HapticFeedbackConstants.LONG_PRESS` there).
  static const tabHold = AppHapticWaveform(
    id: 'tabHold',
    pulses: [AppHapticPulse(atMs: 0, durationMs: 14, intensity: 0.70, sharpness: 0.5)],
  );

  /// A tab or a row becomes selected: the lightest tick we have.
  static const tabSelect = AppHapticWaveform(
    id: 'tabSelect',
    pulses: [AppHapticPulse(atMs: 0, durationMs: 6, intensity: 0.35, sharpness: 0.6)],
  );

  static const selection = AppHapticWaveform(
    id: 'selection',
    pulses: [AppHapticPulse(atMs: 0, durationMs: 5, intensity: 0.30, sharpness: 0.6)],
  );

  static const lightImpact = AppHapticWaveform(
    id: 'lightImpact',
    pulses: [AppHapticPulse(atMs: 0, durationMs: 9, intensity: 0.45, sharpness: 0.5)],
  );

  static const mediumImpact = AppHapticWaveform(
    id: 'mediumImpact',
    pulses: [AppHapticPulse(atMs: 0, durationMs: 14, intensity: 0.70, sharpness: 0.5)],
  );

  static const success = AppHapticWaveform(
    id: 'success',
    pulses: [
      AppHapticPulse(atMs: 0, durationMs: 12, intensity: 0.60, sharpness: 0.6),
      AppHapticPulse(atMs: 70, durationMs: 14, intensity: 0.85, sharpness: 0.6),
    ],
  );

  static const warning = AppHapticWaveform(
    id: 'warning',
    pulses: [
      AppHapticPulse(atMs: 0, durationMs: 12, intensity: 0.70, sharpness: 0.4),
      AppHapticPulse(atMs: 80, durationMs: 12, intensity: 0.60, sharpness: 0.4),
    ],
  );

  static const error = AppHapticWaveform(
    id: 'error',
    pulses: [
      AppHapticPulse(atMs: 0, durationMs: 18, intensity: 0.90, sharpness: 0.3),
      AppHapticPulse(atMs: 60, durationMs: 22, intensity: 0.90, sharpness: 0.3),
    ],
  );

  /// The two designed patterns: a card payment landing, and the app noticing it
  /// went offline. Both stay inside the scale the client we follow uses for its
  /// own patterns (single pulses of a few milliseconds, a whole pattern well
  /// under a quarter second) — a long buzz reads as an alarm, not as feedback.
  static const paymentSuccess = AppHapticWaveform(
    id: 'paymentSuccess',
    pulses: [
      AppHapticPulse(atMs: 0, durationMs: 18, intensity: 0.75, sharpness: 0.8),
      AppHapticPulse(atMs: 140, durationMs: 28, intensity: 1.0, sharpness: 0.9),
    ],
    soundAsset: 'assets/campus_card/audio/payment-success.wav',
    soundDurationMs: 1397,
  );

  static const networkDisconnected = AppHapticWaveform(
    id: 'networkDisconnected',
    pulses: [
      AppHapticPulse(atMs: 0, durationMs: 16, intensity: 0.45, sharpness: 0.6),
      AppHapticPulse(atMs: 70, durationMs: 16, intensity: 0.40, sharpness: 0.6),
      AppHapticPulse(atMs: 130, durationMs: 18, intensity: 0.50, sharpness: 0.7),
      AppHapticPulse(atMs: 186, durationMs: 20, intensity: 0.65, sharpness: 0.7),
    ],
    soundAsset: 'assets/campus_card/audio/network-disconnected.wav',
    soundDurationMs: 1104,
  );

  /// Every waveform, for the contract tests and for the settings screen.
  static const Map<String, AppHapticWaveform> all = {
    'tabHold': tabHold,
    'tabSelect': tabSelect,
    'selection': selection,
    'lightImpact': lightImpact,
    'mediumImpact': mediumImpact,
    'success': success,
    'warning': warning,
    'error': error,
    'paymentSuccess': paymentSuccess,
    'networkDisconnected': networkDisconnected,
  };

  /// Places that can play a waveform. Anywhere else this is a no-op, on purpose.
  static bool get hasPlayer => isAndroid() || isIos() || isOhos();

  static const _channel = MethodChannel('techpie/feedback');
  static const _timeout = Duration(milliseconds: 300);

  /// Plays [waveform], with its sound when [sound] is asked for and the waveform
  /// has one. Failures are swallowed: feedback must never fail the action that
  /// asked for it, and a confirmed payment must not hang on a vibration.
  static Future<void> play(
    AppHapticWaveform waveform, {
    bool vibration = true,
    bool sound = false,
    MethodChannel channel = _channel,
  }) async {
    final wantsSound = sound && waveform.soundAsset != null;
    if (!hasPlayer || (!vibration && !wantsSound)) return;
    try {
      await channel.invokeMethod<void>('play', {
        'id': waveform.id,
        'pulses': [for (final pulse in waveform.pulses) pulse.toJson()],
        'vibration': vibration,
        'sound': wantsSound,
        if (wantsSound) 'soundAsset': waveform.soundAsset,
        if (wantsSound) 'soundDurationMs':
            waveform.soundDurationMs ?? waveform.durationMs,
      }).timeout(_timeout);
    } on TimeoutException {
      return;
    } on MissingPluginException {
      // A platform without our player. Nothing to fall back to by design.
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint('AppHaptics: ${waveform.id} could not play (${error.code})');
      }
    }
  }
}
