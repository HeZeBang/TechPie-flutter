import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/course.dart';
import '../models/custom_course.dart';
import '../models/exam_course.dart';
import '../utils/platform.dart';
import '../utils/today_courses.dart';
import 'assignment_service.dart';
import 'campus_card_service.dart';
import 'schedule_service.dart';
import 'storage_service.dart';

typedef OpenScheduleHandler = Future<void> Function();

/// Publishes display-only snapshots for native home & lock-screen widgets and
/// handles deep-link routing back into TechPie's schedule view.
///
/// Snapshots contain strictly non-sensitive display state (timetable courses,
/// OKLCH course colors, binding status, and cached e-card balance preview);
/// credentials, openIds, tokens, and offline keys never leave the app.
final class HomeWidgetsService with WidgetsBindingObserver {
  HomeWidgetsService(
    this._storage,
    this._schedule,
    this._assignments,
    this._campusCard, {
    MethodChannel? channel,
    DateTime Function()? now,
    bool? enabled,
  })  : _channel = channel ?? const MethodChannel('techpie/home_widgets'),
        _now = now ?? DateTime.now,
        _enabled = enabled ??
            (!kIsWeb &&
                (isIos() ||
                    defaultTargetPlatform == TargetPlatform.macOS ||
                    isAndroid() ||
                    isOhos()));

  static const int scheduleWindowDays = 7;

  final StorageService _storage;
  final ScheduleService _schedule;
  final AssignmentService _assignments;
  final CampusCardService _campusCard;
  final MethodChannel _channel;
  final DateTime Function() _now;
  final bool _enabled;

  bool get enabled => _enabled;

  OpenScheduleHandler? _openScheduleHandler;
  bool _pendingScheduleRoute = false;
  bool _dispatching = false;
  bool _disposed = false;
  bool _initialized = false;

  String? _lastScheduleDigest;
  String? _lastEcardDigest;
  Future<void> _writes = Future.value();

  void initialize() {
    if (_initialized || _disposed) return;
    _initialized = true;
    if (!_enabled) return;

    _schedule.addListener(_onScheduleDataChanged);
    _assignments.addListener(_onScheduleDataChanged);
    _campusCard.addListener(_onEcardDataChanged);
    _storage.hideCampusCardBalanceNotifier.addListener(_onEcardDataChanged);
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_handleMethodCall);

    unawaited(_consumeRoute());
    _onScheduleDataChanged();
    _onEcardDataChanged();
  }

  /// Wait for all queued native snapshot writes to finish. Useful in tests.
  Future<void> flush() => _writes;

  void setOpenScheduleHandler(OpenScheduleHandler handler) {
    _openScheduleHandler = handler;
    if (_pendingScheduleRoute) {
      unawaited(_openSchedule());
    }
  }

  void clearOpenScheduleHandler() => _openScheduleHandler = null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _disposed || !_enabled) return;
    _onScheduleDataChanged();
    _onEcardDataChanged();
  }

  void _onScheduleDataChanged() {
    if (_disposed || !_enabled) return;
    unawaited(_publishSchedule());
  }

  void _onEcardDataChanged() {
    if (_disposed || !_enabled) return;
    unawaited(_publishEcard());
  }

  bool get _hasScheduleData =>
      _schedule.fullCourseTable != null ||
      _schedule.customCourses.isNotEmpty ||
      examsForSemester(
        _assignments.assignments,
        _schedule.selectedSemesterId,
      ).isNotEmpty;

  /// Builds the semantic schedule payload (`weekNumber` and 7-day window).
  Map<String, Object?> buildScheduleSemanticPayload(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final days = <Map<String, Object?>>[];
    for (var offset = 0; offset < scheduleWindowDays; offset++) {
      final day = DateTime(today.year, today.month, today.day + offset);
      final dateKey = _formatDateKey(day);
      final courses = coursesOnDay(_schedule, _assignments, day);
      final seenIds = <String, int>{};
      final courseEntries = <Map<String, Object?>>[];

      for (final course in courses) {
        final startMinutes = parseClockMinutes(course.startTime);
        final endMinutes = parseClockMinutes(course.endTime);
        if (startMinutes == null ||
            endMinutes == null ||
            endMinutes <= startMinutes) {
          continue;
        }
        final startDt = DateTime(
          day.year,
          day.month,
          day.day,
          startMinutes ~/ 60,
          startMinutes % 60,
        );
        final endDt = DateTime(
          day.year,
          day.month,
          day.day,
          endMinutes ~/ 60,
          endMinutes % 60,
        );

        final baseId =
            '$dateKey|${course.startTime}|${course.endTime}|${course.name}';
        final count = seenIds[baseId] ?? 0;
        seenIds[baseId] = count + 1;
        final id = count == 0 ? baseId : '$baseId#$count';

        courseEntries.add({
          'id': id,
          'title': course.name,
          'location': course.location.trim(),
          'teacher': (course.teachers ?? '').trim(),
          'startAt': _formatUtcIso(startDt),
          'endAt': _formatUtcIso(endDt),
          'startPeriod': course.usesCustomTime ? null : course.startPeriod,
          'endPeriod': course.usesCustomTime ? null : course.endPeriod,
          'periodLabel': course.usesCustomTime
              ? null
              : (course.startPeriod == course.endPeriod
                  ? '${course.startPeriod}'
                  : '${course.startPeriod}-${course.endPeriod}'),
          'isExam': course.source is ExamCourseSource,
          'colorLightHex': _toHex(course.color.accentColor(Brightness.light)),
          'colorDarkHex': _toHex(course.color.accentColor(Brightness.dark)),
        });
      }

      days.add({
        'date': dateKey,
        'weekday': day.weekday,
        'weekNumber': _weekNumberForDay(day),
        'courses': courseEntries,
      });
    }

    return {
      'schemaVersion': 1,
      'weekNumber': _weekNumberForDay(today),
      'days': days,
    };
  }

  /// Builds the semantic e-card widget payload without `generatedAt`.
  Map<String, Object?> buildEcardSemanticPayload() {
    final configured = _campusCard.configured;
    final balance = _campusCard.cachedBalance;
    final balanceText = (!configured || balance == null)
        ? null
        : '¥ ${balance.toYuanFixed()}';
    return {
      'schemaVersion': 1,
      'configured': configured,
      'balanceText': balanceText,
      'hideBalance': _storage.hideCampusCardBalance,
    };
  }

  Future<void> publishScheduleNow() => _publishSchedule();

  Future<void> clearSchedule() {
    if (!_enabled || _disposed) return _writes;
    _writes = _writes.then((_) async {
      if (_disposed || _lastScheduleDigest == '__cleared__') return;
      try {
        await _channel.invokeMethod<void>('clearSchedule');
        _lastScheduleDigest = '__cleared__';
      } on MissingPluginException {
        // Unsupported host platform.
      } on PlatformException {
        // Retry on next lifecycle or data change.
      }
    });
    return _writes;
  }

  Future<void> _publishSchedule() {
    final now = _now();
    final hasData = _hasScheduleData;
    final semantic = hasData ? buildScheduleSemanticPayload(now) : null;
    final digest = semantic == null ? '__cleared__' : jsonEncode(semantic);

    _writes = _writes.then((_) async {
      if (_disposed) return;
      if (_lastScheduleDigest == digest) return;
      try {
        if (semantic == null) {
          await _channel.invokeMethod<void>('clearSchedule');
        } else {
          final fullPayload = <String, Object?>{
            ...semantic,
            'generatedAt': _formatUtcIso(now),
          };
          await _channel.invokeMethod<void>(
            'publishSchedule',
            jsonEncode(fullPayload),
          );
        }
        _lastScheduleDigest = digest;
      } on MissingPluginException {
        // Platforms without this channel ignore widget snapshots gracefully.
      } on PlatformException {
        // Retry on next change/foreground event; never disrupt the app.
      }
    });
    return _writes;
  }

  Future<void> _publishEcard() {
    final now = _now();
    final semantic = buildEcardSemanticPayload();
    final digest = jsonEncode(semantic);

    _writes = _writes.then((_) async {
      if (_disposed) return;
      if (_lastEcardDigest == digest) return;
      try {
        final fullPayload = <String, Object?>{
          ...semantic,
          'generatedAt': _formatUtcIso(now),
        };
        await _channel.invokeMethod<void>(
          'publishEcard',
          jsonEncode(fullPayload),
        );
        _lastEcardDigest = digest;
      } on MissingPluginException {
        // Unsupported host platform.
      } on PlatformException {
        // Retry on next state change/resume.
      }
    });
    return _writes;
  }

  int? _weekNumberForDay(DateTime day) {
    final begin = _schedule.termBegin;
    if (begin == null) return null;
    final date = DateTime(day.year, day.month, day.day);
    if (_schedule.isGraduate) {
      final week = teachingWeekOf(date, begin);
      return (week != null && week > 0) ? week : null;
    }
    final firstDay = DateTime(begin.year, begin.month, begin.day);
    if (date.isBefore(firstDay)) return null;
    final week = date.difference(firstDay).inDays ~/ 7 + 1;
    return week <= _schedule.totalWeeks ? week : null;
  }

  static String _formatDateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static String _formatUtcIso(DateTime dt) =>
      dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

  static String _toHex(Color color) {
    final rgb = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '#${rgb.toUpperCase()}';
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method == 'openSchedule') {
      await _openSchedule();
    }
    return null;
  }

  Future<void> _consumeRoute() async {
    try {
      final route = await _channel.invokeMethod<String>('consumePendingRoute');
      if (route == 'schedule') {
        await _openSchedule();
      }
    } on MissingPluginException {
      // No native bridge registered on this host.
    } on PlatformException {
      // Later warm-start callbacks will deliver the route.
    }
  }

  Future<void> _openSchedule() async {
    if (_disposed) return;
    if (_openScheduleHandler == null || _dispatching) {
      _pendingScheduleRoute = true;
      return;
    }
    _pendingScheduleRoute = false;
    _dispatching = true;
    try {
      await _openScheduleHandler!();
      try {
        await _channel.invokeMethod<void>('acknowledgePendingRoute');
      } on MissingPluginException {
        // Tests may dispatch without a native peer.
      } on PlatformException {
        // Schedule page is already open.
      }
    } finally {
      _dispatching = false;
      if (_pendingScheduleRoute) {
        unawaited(_openSchedule());
      }
    }
  }

  void dispose() {
    _disposed = true;
    _openScheduleHandler = null;
    if (!_initialized || !_enabled) return;
    _schedule.removeListener(_onScheduleDataChanged);
    _assignments.removeListener(_onScheduleDataChanged);
    _campusCard.removeListener(_onEcardDataChanged);
    _storage.hideCampusCardBalanceNotifier.removeListener(_onEcardDataChanged);
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
  }
}
