import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import 'assignment_service.dart';

typedef OpenDeadlinesHandler = Future<void> Function();

/// Publishes display-only data; native widgets never receive account credentials.
class DeadlineWidgetService with WidgetsBindingObserver {
  DeadlineWidgetService(
    this._assignments, {
    MethodChannel? channel,
    DateTime Function()? now,
    bool enabled = true,
  })  : _channel = channel ?? const MethodChannel('techpie/deadline_widgets'),
        _enabled = enabled,
        _now = now ?? DateTime.now;

  final AssignmentService _assignments;
  final MethodChannel _channel;
  final DateTime Function() _now;
  bool _enabled;
  bool get enabled => _enabled;

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    _lastPublished = null;
    await _publish();
  }

  OpenDeadlinesHandler? _handler;
  bool _pendingRoute = false;
  bool _dispatching = false;
  bool _disposed = false;
  bool _initialized = false;
  String? _lastPublished;
  Future<void> _writes = Future.value();

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _assignments.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openDeadlines') await _open();
    });
    unawaited(_consumeRoute());
    _changed();
  }

  static List<Map<String, Object>> displayItems(
    Iterable<Assignment> assignments,
    bool Function(Assignment) completed,
    DateTime now,
  ) {
    final items = assignments.where((a) => !completed(a) && a.due.isAfter(now)).toList()
      ..sort((a, b) {
        final order = a.due.compareTo(b.due);
        return order != 0
            ? order
            : AssignmentOverrides.keyFor(a).compareTo(AssignmentOverrides.keyFor(b));
      });
    final result = <Map<String, Object>>[];
    final ids = <String>{};
    var bytes = 1024; // Reserve the envelope and list separators.
    for (final a in items) {
      final id = AssignmentOverrides.keyFor(a);
      final due = a.due.toUtc().millisecondsSinceEpoch / 1000;
      if (utf8.encode(id).length > 4096 || !ids.add(id) || due < 0 || due > 253402300799) continue;
      final row = <String, Object>{
        'id': id,
        'kind': a.kind.id,
        'title': String.fromCharCodes(a.title.runes.take(256)),
        'course': String.fromCharCodes(a.course.runes.take(128)),
        'dueAt': due,
      };
      final size = utf8.encode(jsonEncode(row)).length + 1;
      if (bytes + size > 262144) break;
      result.add(row);
      bytes += size;
      if (result.length == 512) break;
    }
    return result;
  }

  void _changed() => unawaited(_publish());

  Future<void> _publish() async {
    final epoch = _assignments.identityEpoch;
    // Publish an empty valid snapshot as soon as sharing is enabled. This
    // keeps the desktop card truthful before the first sync.
    final ready = _enabled;
    final items = _assignments.hasCachedData ? displayItems(
      _assignments.visibleAssignments,
      _assignments.isCompleted,
      _now(),
    ) : <Map<String, Object>>[];
    final content = ready ? jsonEncode(items) : null;
    _writes = _writes.then((_) async {
      if (_disposed ||
          epoch != _assignments.identityEpoch ||
          ready != _enabled) {
        return;
      }
      if (_lastPublished == content && content != null) return;
      try {
        if (!ready) {
          await _channel.invokeMethod<void>('clear');
        } else {
          await _channel.invokeMethod<void>(
            'publish',
            jsonEncode({
              'schemaVersion': 1,
              'writtenAt': _now().toUtc().millisecondsSinceEpoch / 1000,
              'items': items,
            }),
          );
        }
        _lastPublished = content;
      } on MissingPluginException {
        // Unsupported platforms keep using the regular deadlines page.
      } on PlatformException {
        // Retry on the next change/foreground event; never block the app.
      }
    });
    await _writes;
  }

  Future<void> flush() => _writes;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _disposed) return;
    _changed();
  }

  void setOpenHandler(OpenDeadlinesHandler handler) {
    _handler = handler;
    if (_pendingRoute) unawaited(_open());
  }

  void clearOpenHandler() => _handler = null;

  Future<void> _consumeRoute() async {
    try {
      if (await _channel.invokeMethod<bool>('consumePendingRoute') == true) {
        await _open();
      }
    } on MissingPluginException {
      // A missing native bridge does not delay app navigation.
    } on PlatformException {
      // Retry when a later native route event arrives.
    }
  }

  Future<void> _open() async {
    if (_disposed) return;
    if (_handler == null || _dispatching) {
      _pendingRoute = true;
      return;
    }
    _pendingRoute = false;
    _dispatching = true;
    try {
      await _handler!();
      try {
        await _channel.invokeMethod<void>('acknowledgePendingRoute');
      } on MissingPluginException {
        // Tests may dispatch without a native peer.
      } on PlatformException {
        // The destination is already visible.
      }
    } finally {
      _dispatching = false;
      if (_pendingRoute) unawaited(_open());
    }
  }

  void dispose() {
    _disposed = true;
    _handler = null;
    if (!_initialized) return;
    _assignments.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
  }
}
