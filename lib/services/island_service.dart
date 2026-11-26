import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/assignment.dart';
import '../models/island_frame.dart';
import '../utils/platform.dart';
import '../utils/today_courses.dart';
import 'assignment_service.dart';
import 'schedule_service.dart';
import 'storage_service.dart';

/// What the device can show the schedule as, as reported by the platform.
class IslandCapability {
  const IslandCapability({
    required this.backend,
    required this.notificationsEnabled,
    required this.islandGranted,
    required this.liveUpdateGranted,
  });

  /// `hyper_island`, `live_update` or `plain`.
  final String backend;
  final bool notificationsEnabled;

  /// The focus-notification grant is Xiaomi's own approval, so a device can be
  /// capable and still not allowed to float.
  final bool islandGranted;
  final bool liveUpdateGranted;

  static IslandCapability? fromMap(Object? map) {
    if (map is! Map) return null;
    return IslandCapability(
      backend: map['backend'] as String? ?? 'plain',
      notificationsEnabled: map['postNotifications'] as bool? ?? false,
      islandGranted: map['islandGranted'] as bool? ?? false,
      liveUpdateGranted: map['liveUpdateGranted'] as bool? ?? false,
    );
  }
}

/// Keeps the status-bar island on one screen of schedule state.
///
/// The island is a reflection of what the app already cached: it never hits the
/// network, because the campus session lives here and the widget host has no
/// business holding it.
final class IslandService {
  IslandService(
    this._storage,
    this._schedule,
    this._assignments, {
    MethodChannel? channel,
    DateTime Function()? now,
  })  : _channel = channel ?? const MethodChannel('techpie/island'),
        _now = now ?? DateTime.now;

  static const _refreshCooldown = Duration(seconds: 30);
  static const _tick = Duration(minutes: 1);

  final StorageService _storage;
  final ScheduleService _schedule;
  final AssignmentService _assignments;
  final MethodChannel _channel;
  final DateTime Function() _now;

  Timer? _timer;
  Timer? _timelineDebounce;
  DateTime? _lastRefresh;
  bool _showing = false;
  bool _started = false;

  bool get supported => isAndroid();

  bool get enabled => supported && _storage.islandEnabled;

  Future<IslandCapability?> capability() async {
    if (!supported) return null;
    try {
      final map = await _channel.invokeMethod<Object>('probe');
      return IslandCapability.fromMap(map);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Turn the island on or off. Enabling asks for the notification permission
  /// first, since a denied permission means nothing can be shown at all.
  Future<void> setEnabled(bool value) async {
    await _storage.setIslandEnabled(value);
    if (!value) {
      await dismiss(force: true);
      await _invokeQuiet('cancelFrames');
      return;
    }
    await _requestNotificationPermission();
    await refreshNow(force: true);
    await scheduleTimeline();
  }

  /// Follow the schedule and deadlines while the app runs; the platform side
  /// keeps the last frame on screen once this process is gone.
  void start() {
    if (!supported || _started) return;
    _started = true;
    // Whatever the last run left on screen is ours to settle: assume it is up,
    // so the first refresh either refreshes it or clears it exactly once.
    _showing = enabled;
    _schedule.addListener(_onDataChanged);
    _assignments.addListener(_onDataChanged);
    _timer = Timer.periodic(_tick, (_) => unawaited(refreshNow()));
    unawaited(refreshNow(force: true));
    // The platform keeps painting frames once this process is gone.
    unawaited(scheduleTimeline());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _timelineDebounce?.cancel();
    _timelineDebounce = null;
    if (!_started) return;
    _started = false;
    _schedule.removeListener(_onDataChanged);
    _assignments.removeListener(_onDataChanged);
  }

  Future<void> refreshNow({bool force = false}) async {
    if (!enabled) return;
    final now = _now();
    final last = _lastRefresh;
    if (!force &&
        last != null &&
        now.difference(last) < _refreshCooldown) {
      return;
    }
    _lastRefresh = now;
    final frame = buildIslandFrame(
      dayCourses: coursesOnDay(_schedule, _assignments, now),
      upcomingDeadlines: _openDeadlines(),
      now: now,
    );
    if (frame == null) {
      await dismiss();
      return;
    }
    await _push(frame);
  }

  /// [force] clears even what this run never showed — turning the feature off
  /// means a frame left up by an earlier run has to go.
  Future<void> dismiss({bool force = false}) async {
    if (!supported) return;
    if (!_showing && !force) return;
    _showing = false;
    try {
      await _channel.invokeMethod<bool>('dismiss');
    } on PlatformException {
      // Already gone.
    } on MissingPluginException {
      // Non-Android platforms do not register the channel.
    }
  }

  List<Assignment> _openDeadlines() => _assignments.visibleAssignments
      .where((assignment) => !_assignments.isCompleted(assignment))
      .toList();

  Future<void> _push(IslandFrame frame) async {
    try {
      await _channel.invokeMethod<String>('updateFrame', {
        'frame': jsonEncode(frame.toJson()),
      });
      _showing = true;
    } on PlatformException {
      // A frame that cannot be shown is dropped, not retried: the next tick
      // recomputes from state that is by then current.
    } on MissingPluginException {
      // Non-Android platforms do not register the channel.
    }
  }

  Future<void> _onDataChanged() async {
    if (!enabled) return;
    await refreshNow(force: true);
    // A schedule/assignment load arrives as a burst of changes; rescheduling is
    // a full alarm rebuild, so let it settle first.
    _timelineDebounce?.cancel();
    _timelineDebounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(scheduleTimeline()),
    );
  }

  /// Precompute the frames for the next days so the platform can post them with
  /// AlarmManager while this process is gone. A null frame is a dismissal.
  Future<void> scheduleTimeline() async {
    if (!supported) return;
    if (!enabled) {
      await _invokeQuiet('cancelFrames');
      return;
    }
    final events = buildIslandTimeline(
      coursesForDay: (day) => coursesOnDay(_schedule, _assignments, day),
      deadlines: _openDeadlines(),
      now: _now(),
    ).entries;
    final payload = [
      for (final entry in events)
        {'at': entry.key, 'frame': entry.value?.toJson()},
    ];
    try {
      await _channel.invokeMethod<int>('scheduleFrames', {
        'frames': jsonEncode(payload),
      });
    } on PlatformException {
      // Best effort: the in-process refresh still runs while the app is open.
    } on MissingPluginException {
      // Non-Android platforms do not register the channel.
    }
  }

  Future<void> _invokeQuiet(String method) async {
    try {
      await _channel.invokeMethod<Object?>(method);
    } on PlatformException {
      // Best effort.
    } on MissingPluginException {
      // Non-Android platforms do not register the channel.
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('requestPermission');
    } on PlatformException {
      // The prompt is advisory; the capability probe still says whether the
      // island can be shown.
    } on MissingPluginException {
      // Non-Android platforms do not register the channel.
    }
  }
}
