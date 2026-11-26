import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'telemetry_client.dart' if (dart.library.js_interop) 'telemetry_client_web.dart';

/// Anonymous product metrics. Only these event constructors accept application data.
class UsageTelemetry extends ChangeNotifier {
  UsageTelemetry(
    this._prefs, {
    required this.endpoint,
    required this.version,
    required this.platform,
    required bool existingInstall,
    DateTime Function()? clock,
    http.Client Function()? clientFactory,
  })  : _now = clock ?? DateTime.now,
        _clientFactory = clientFactory ?? createTelemetryClient {
    _launch = _now();
    _firstSession = !existingInstall && !_prefs.containsKey(_seenKey);
    if (!_prefs.containsKey(_seenKey)) unawaited(_prefs.setBool(_seenKey, true));
    final raw = _prefs.getString(_stateKey);
    if (raw != null) {
      try {
        final state = jsonDecode(raw);
        if (state
            case {
              'installation': final String id,
              'logged': final bool logged,
              'events': final List<dynamic> events
            }
            when RegExp(r'^[0-9a-f]{32}$').hasMatch(id) &&
                events.every((e) => e is Map<String, dynamic>)) {
          _installation = id;
          _logged = logged;
          _events.addAll(events.cast<Map<String, dynamic>>());
        }
      } on FormatException {
        // Start with telemetry off if its stored consent record is unreadable.
      }
      if (!enabled) unawaited(_prefs.remove(_stateKey));
    }
    opened();
  }

  static const _seenKey = 'usage_launch_seen_v1';
  static const _stateKey = 'usage_metrics_v1';
  static final _random = Random.secure();
  static String _id() =>
      List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  final SharedPreferences _prefs;
  final Uri endpoint;
  final String version, platform;
  final DateTime Function() _now;
  final http.Client Function() _clientFactory;
  final List<Map<String, dynamic>> _events = [];
  late final DateTime _launch;
  late bool _firstSession;
  bool _logged = false;
  DateTime? _firstLoginInSession;
  String? _installation;
  DateTime? _lastOpen;
  Timer? _timer;
  http.Client? _sending;
  Duration _retry = const Duration(seconds: 10);
  bool _disposed = false;
  bool get enabled => !_disposed && _installation != null;

  Future<void> setEnabled(bool value) async {
    if (enabled == value) return;
    if (!value) {
      _installation = null;
      _timer?.cancel();
      _timer = null;
      _sending?.close();
      _sending = null;
      _events.clear();
      _logged = false;
      _lastOpen = null;
      _firstSession = false;
      _firstLoginInSession = null;
      _retry = const Duration(seconds: 10);
      final removed = _prefs.remove(_stateKey);
      notifyListeners();
      await removed;
      return;
    }
    _installation = _id();
    if (_firstSession) {
      _event('first_launch', time: _launch);
      if (_firstLoginInSession != null) _login(_firstLoginInSession!);
    }
    opened();
    notifyListeners();
    await _save();
  }

  void firstLogin() {
    final now = _now();
    _firstLoginInSession ??= now;
    if (enabled) _login(now);
  }

  void _login(DateTime time) {
    if (_logged) return;
    _logged = true;
    _event('first_login', time: time);
  }

  void opened() {
    if (!enabled) return;
    final now = _now();
    if (now == _lastOpen) return;
    _lastOpen = now;
    _event('app_open', time: now);
  }

  static const _features = {
    'home',
    'schedule',
    'deadlines',
    'settings',
    'campus_services',
    'feedback',
    'elrc_recordings',
    'ecourse',
    'student_leave',
    'campus_card',
    'oa_gym',
    'egate_xshd',
    'study_plan',
    'blackboard',
    'student_allowance',
    'grades',
    'course_catalog',
    'pnp_minor',
    'academic_certificates',
    'holiday_travel',
    'campus_jobs',
    'counseling',
    'more',
  };

  void featureOpened(String feature) {
    if (_features.contains(feature)) _event('feature_open', fields: {'feature': feature});
  }

  UsageVisit? beginFeedback() => _begin('feedback');
  UsageVisit? beginRecording() => _begin('recording');
  UsageVisit? _begin(String type) {
    if (!enabled) return null;
    final visit = UsageVisit._(this, _installation!, _id(), type);
    _event('${type}_open', fields: {'visit': visit._id});
    return visit;
  }

  void _event(String kind, {DateTime? time, Map<String, Object> fields = const {}}) {
    if (!enabled) return;
    if (_events.length >= 240) {
      final oldest =
          _events.indexWhere((e) => !{'first_launch', 'first_login'}.contains(e['kind']));
      _events.removeAt(oldest);
    }
    _events.add({
      'id': _id(),
      'kind': kind,
      'at': (time ?? _now()).millisecondsSinceEpoch,
      'version': version,
      'platform': platform,
      ...fields,
    });
    unawaited(_save());
    _schedule();
  }

  Future<bool> _save() => _prefs.setString(
        _stateKey,
        jsonEncode({
          'installation': _installation,
          'logged': _logged,
          'events': _events,
        }),
      );

  void _schedule([Duration delay = const Duration(seconds: 1)]) {
    if (!enabled || _events.isEmpty || _timer != null || _sending != null) return;
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (!enabled || _events.isEmpty || _sending != null) return;
    final owner = _installation!;
    final batch = _events.take(60).toList();
    final client = _clientFactory();
    _sending = client;
    var accepted = false;
    var permanentlyRejected = false;
    try {
      final request = http.Request('POST', endpoint)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'installation': owner, 'events': batch});
      final response = await client.send(request).timeout(const Duration(seconds: 8));
      await response.stream.drain<void>().timeout(const Duration(seconds: 8));
      final status = response.statusCode;
      accepted = status == 204;
      permanentlyRejected = status >= 400 && status < 500 && status != 408 && status != 429;
      if ((accepted || permanentlyRejected) && _installation == owner) {
        final ids = batch.map((e) => e['id']).toSet();
        _events.removeWhere((e) => ids.contains(e['id']));
        await _save();
      }
    } on Exception {
      // Keep the batch so a later attempt can send the same event IDs.
    } finally {
      client.close();
      if (identical(_sending, client)) {
        _sending = null;
        final settled = accepted || permanentlyRejected;
        final delay = settled ? const Duration(seconds: 1) : _retry;
        _retry = settled
            ? const Duration(seconds: 10)
            : Duration(seconds: min(300, 2 * _retry.inSeconds));
        _schedule(delay);
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _installation = null;
    _sending?.close();
    _sending = null;
    super.dispose();
  }
}

class UsageVisit {
  UsageVisit._(this._service, this._owner, this._id, this._type);
  final UsageTelemetry _service;
  final String _owner, _id, _type;
  final _clock = Stopwatch()..start();
  bool _ready = false, _error = false, _ended = false;

  void feedbackAttempt() => _mark('attempt');
  void feedbackResult(bool delivered) => _mark(delivered ? 'success' : 'failure');
  void recordingReady() {
    if (_ready) return;
    _ready = true;
    _mark('ready');
  }

  void recordingError() {
    if (_error) return;
    _error = true;
    _mark('error');
  }

  void recordingExit() {
    if (_ended) return;
    _mark('exit');
    _ended = true;
  }

  void _mark(String kind) {
    if (_service._installation != _owner || _ended) return;
    _service._event(
      '${_type}_$kind',
      fields: {'visit': _id, if (_type == 'recording') 'elapsed': _clock.elapsedMilliseconds},
    );
  }
}
