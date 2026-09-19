import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as flutter;
import 'package:screen_brightness/screen_brightness.dart';

import '../../../utils/haptics.dart';
import '../data/storage/feedback_preferences.dart';
import '../domain/models/feedback_models.dart';
import '../domain/ports/platform_ports.dart';

final class SystemFeedbackPort implements FeedbackPort {
  SystemFeedbackPort({FeedbackPreferences? preferences})
      : _preferences = preferences ?? FeedbackPreferences();

  final FeedbackPreferences _preferences;

  @override
  Future<FeedbackOptions> settingsFor(FeedbackScenario scenario) =>
      _preferences.read(scenario);

  @override
  Future<void> setEnabled(
    FeedbackScenario scenario,
    FeedbackChannel channel,
    bool enabled,
  ) =>
      _preferences.setEnabled(scenario, channel, enabled);

  @override
  Future<void> play(FeedbackEvent event) async {
    final options = await _preferences.read(event.scenario);
    // The waveform comes from the app's one dictionary (lib/utils/haptics.dart);
    // whether it plays at all stays here, per scenario.
    await AppHaptics.play(
      switch (event) {
        FeedbackEvent.selection => AppHaptics.selection,
        FeedbackEvent.lightImpact => AppHaptics.lightImpact,
        FeedbackEvent.mediumImpact => AppHaptics.mediumImpact,
        FeedbackEvent.success => AppHaptics.success,
        FeedbackEvent.warning => AppHaptics.warning,
        FeedbackEvent.error => AppHaptics.error,
        FeedbackEvent.paymentSuccess => AppHaptics.paymentSuccess,
        FeedbackEvent.networkDisconnected => AppHaptics.networkDisconnected,
      },
      vibration: options.vibration,
      sound: options.sound,
    );
  }
}

final class SystemBrightnessPort implements BrightnessPort {
  SystemBrightnessPort({ScreenBrightness? screenBrightness})
      : _screenBrightness = screenBrightness ?? ScreenBrightness.instance;

  final ScreenBrightness _screenBrightness;
  double? _original;

  @override
  Future<double> current() async {
    final value = await _screenBrightness.application;
    _original ??= value;
    return value;
  }

  @override
  Future<void> set(double value) async {
    _original ??= await _screenBrightness.application;
    await _screenBrightness.setApplicationScreenBrightness(value.clamp(0, 1));
  }

  @override
  Future<void> restore() async {
    final original = _original;
    _original = null;
    try {
      await _screenBrightness.resetApplicationScreenBrightness();
    } catch (_) {
      if (original != null) {
        await _screenBrightness.setApplicationScreenBrightness(original);
      }
    }
  }
}

final class SystemConnectivityPort implements ConnectivityPort {
  SystemConnectivityPort({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  bool get _isOhos => !kIsWeb && defaultTargetPlatform.name == 'ohos';
  static const _ohosMethod = MethodChannel('techpie/campus_card');
  static const _ohosEvents = EventChannel('techpie/campus_card/connectivity');

  bool get _pluginSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  Future<bool> isOnline() async {
    if (_isOhos) {
      try {
        return await _ohosMethod.invokeMethod<bool>('isOnline') ?? false;
      } on PlatformException {
        return false;
      } on MissingPluginException {
        return false;
      }
    }
    if (!_pluginSupported) return true;
    try {
      return _hasNetwork(await _connectivity.checkConnectivity());
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Stream<bool> get changes {
    if (_isOhos) {
      return _ohosConnectivityChanges().distinct();
    }
    if (!_pluginSupported) return Stream<bool>.value(true);
    return _connectivityChanges();
  }

  Stream<bool> _ohosConnectivityChanges() async* {
    try {
      await for (final event in _ohosEvents.receiveBroadcastStream()) {
        yield event == true;
      }
    } on PlatformException {
      yield false;
    } on MissingPluginException {
      yield false;
    }
  }

  Stream<bool> _connectivityChanges() async* {
    try {
      await for (final results in _connectivity.onConnectivityChanged) {
        yield _hasNetwork(results);
      }
    } on MissingPluginException {
      yield true;
    } on PlatformException {
      yield true;
    }
  }

  bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}

final class FlutterAppLifecyclePort
    with flutter.WidgetsBindingObserver
    implements AppLifecyclePort {
  FlutterAppLifecyclePort() {
    flutter.WidgetsBinding.instance.addObserver(this);
    _current = _map(flutter.WidgetsBinding.instance.lifecycleState);
  }

  final StreamController<AppLifecycleState> _changes =
      StreamController<AppLifecycleState>.broadcast(sync: true);
  late AppLifecycleState _current;

  @override
  AppLifecycleState get current => _current;

  @override
  Stream<AppLifecycleState> get changes => _changes.stream;

  @override
  void didChangeAppLifecycleState(flutter.AppLifecycleState state) {
    final mapped = _map(state);
    if (mapped == _current) return;
    _current = mapped;
    _changes.add(mapped);
  }

  Future<void> dispose() async {
    flutter.WidgetsBinding.instance.removeObserver(this);
    await _changes.close();
  }

  AppLifecycleState _map(flutter.AppLifecycleState? state) => switch (state) {
        flutter.AppLifecycleState.resumed => AppLifecycleState.resumed,
        flutter.AppLifecycleState.inactive ||
        flutter.AppLifecycleState.hidden =>
          AppLifecycleState.inactive,
        flutter.AppLifecycleState.paused => AppLifecycleState.paused,
        flutter.AppLifecycleState.detached ||
        null =>
          AppLifecycleState.detached,
      };
}
