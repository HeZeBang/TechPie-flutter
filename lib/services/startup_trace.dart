import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Compile-time switch for boot timing. Build with
/// `--dart-define=BOOT_TRACE=true` to enable the marks; normal builds pay
/// nothing beyond a constant check.
const bool startupTraceEnabled = bool.fromEnvironment('BOOT_TRACE');

/// Thin, always-compiled-in boot tracer.
///
/// The elapsed numbers are relative to the first [mark] (the first line of
/// `main` in this app), not to process/engine start. Use Android `am start`
/// and the native start timestamp for the engine-to-Dart portion.
/// Logs go through [debugPrint] because it is visible in profile builds under
/// logcat; [developer.Timeline] carries the same points into DevTools.
class StartupTrace {
  StartupTrace._();

  static final Stopwatch _clock = Stopwatch()..start();

  static void mark(String name) {
    if (!startupTraceEnabled) return;
    developer.Timeline.instantSync('boot/$name');
    debugPrint('[BOOT] ${_clock.elapsedMilliseconds}ms $name');
  }

  /// Times an async phase and emits the duration next to the global mark.
  static Future<T> time<T>(String name, Future<T> Function() action) async {
    if (!startupTraceEnabled) return action();
    final watch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      mark('$name ${watch.elapsedMilliseconds}ms');
    }
  }
}
