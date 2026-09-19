import 'dart:async';

import '../../core/async_mutex.dart';
import '../../domain/models/feedback_models.dart';
import '../../domain/ports/credential_store.dart';
import '../../domain/ports/platform_ports.dart';

final class InMemorySecureCredentialStore implements SecureCredentialStore {
  final Map<String, String> _values = {};
  final AsyncMutex _mutex = AsyncMutex();
  bool failNextWrite = false;

  Map<String, String> snapshotForTesting() => Map.unmodifiable(_values);

  /// How many reads the code under test performed. A keystore read is a platform
  /// channel call, so a change that removes them from a hot path is worth
  /// pinning.
  int readsForTesting = 0;
  @override
  Future<String?> read(String key) async {
    readsForTesting++;
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) => _mutex.protect(() async {
        if (failNextWrite) {
          failNextWrite = false;
          throw StateError('Injected secure-store write failure');
        }
        _values[key] = value;
      });

  @override
  Future<void> delete(String key) => _mutex.protect(() async {
        _values.remove(key);
      });

  @override
  Future<void> deleteAll(Iterable<String> keys) => _mutex.protect(() async {
        for (final key in keys) {
          _values.remove(key);
        }
      });

  @override
  Future<void> replaceAtomically(Map<String, String?> values) =>
      _mutex.protect(() async {
        if (failNextWrite) {
          failNextWrite = false;
          throw StateError('Injected secure-store write failure');
        }
        final replacement = Map<String, String>.from(_values);
        for (final entry in values.entries) {
          if (entry.value == null) {
            replacement.remove(entry.key);
          } else {
            replacement[entry.key] = entry.value!;
          }
        }
        _values
          ..clear()
          ..addAll(replacement);
      });
}

final class InMemoryConnectivityPort implements ConnectivityPort {
  InMemoryConnectivityPort({bool online = true}) : _online = online;

  bool _online;
  final StreamController<bool> _changes = StreamController<bool>.broadcast(
    sync: true,
  );

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<bool> isOnline() async => _online;

  void setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    _changes.add(value);
  }
}

final class InMemoryBrightnessPort implements BrightnessPort {
  InMemoryBrightnessPort({double initial = 0.5})
      : _value = initial,
        _original = initial;

  double _value;
  final double _original;

  double get value => _value;

  @override
  Future<double> current() async => _value;

  @override
  Future<void> restore() async => _value = _original;

  @override
  Future<void> set(double value) async => _value = value.clamp(0, 1);
}

final class InMemoryLifecyclePort implements AppLifecyclePort {
  InMemoryLifecyclePort([this._current = AppLifecycleState.resumed]);

  AppLifecycleState _current;
  final StreamController<AppLifecycleState> _changes =
      StreamController<AppLifecycleState>.broadcast(sync: true);

  @override
  Stream<AppLifecycleState> get changes => _changes.stream;

  @override
  AppLifecycleState get current => _current;

  void setState(AppLifecycleState value) {
    if (_current == value) return;
    _current = value;
    _changes.add(value);
  }
}

final class InMemoryScannerPort implements ScannerPort {
  final StreamController<String> _codes = StreamController<String>.broadcast(
    sync: true,
  );
  bool running = false;
  bool torch = false;
  String? nextImageCode;

  @override
  Stream<String> get scannedCodes => _codes.stream;

  void emit(String code) {
    if (running) _codes.add(code);
  }

  @override
  Future<String?> scanImage() async => nextImageCode;

  @override
  Future<void> setTorch(bool enabled) async => torch = enabled;

  @override
  Future<void> start() async => running = true;

  @override
  Future<void> stop() async => running = false;
}

final class InMemoryFeedbackPort implements FeedbackPort {
  final List<FeedbackEvent> events = [];
  final _options = <FeedbackScenario, FeedbackOptions>{};

  @override
  Future<FeedbackOptions> settingsFor(FeedbackScenario scenario) async =>
      _options[scenario] ??
      FeedbackOptions(sound: scenario != FeedbackScenario.interaction);

  @override
  Future<void> setEnabled(
    FeedbackScenario scenario,
    FeedbackChannel channel,
    bool enabled,
  ) async {
    _options[scenario] =
        (await settingsFor(scenario)).withEnabled(channel, enabled);
  }

  @override
  Future<void> play(FeedbackEvent event) async {
    final options = await settingsFor(event.scenario);
    if (options.vibration || options.sound) events.add(event);
  }
}
