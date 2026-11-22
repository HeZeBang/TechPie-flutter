import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/assignment.dart';
import 'assignment_service.dart';

typedef ReminderExportResult = ({int added, int existing, int failed});

class DeadlineReminderService with WidgetsBindingObserver {
  DeadlineReminderService(
    this._assignments, {
    MethodChannel channel = const MethodChannel('techpie/deadline_reminders'),
  }) : _channel = channel;

  final AssignmentService _assignments;
  final MethodChannel _channel;
  List<Assignment>? _lastAssignments;
  int? _lastIdentityEpoch;
  bool _initialized = false;
  bool _syncing = false;
  bool _syncAgain = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _assignments.addListener(_assignmentsChanged);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'remindersChanged') await syncCompletions();
    });
    _assignmentsChanged();
  }

  void dispose() {
    if (!_initialized) return;
    _initialized = false;
    _lastAssignments = null;
    _lastIdentityEpoch = null;
    WidgetsBinding.instance.removeObserver(this);
    _assignments.removeListener(_assignmentsChanged);
    _channel.setMethodCallHandler(null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(syncCompletions());
  }

  void _assignmentsChanged() {
    final assignments = _assignments.assignments;
    final epoch = _assignments.identityEpoch;
    if (identical(assignments, _lastAssignments) && epoch == _lastIdentityEpoch) {
      return;
    }
    _lastAssignments = assignments;
    _lastIdentityEpoch = epoch;
    unawaited(syncCompletions());
  }

  String _keyFor(Assignment assignment) =>
      sha256.convert(utf8.encode(_assignments.scopedKeyFor(assignment))).toString();

  Future<ReminderExportResult> add(Iterable<Assignment> assignments) async {
    final data = await _channel.invokeMapMethod<String, int>('add', [
      for (final assignment in assignments)
        {
          'key': _keyFor(assignment),
          'title': assignment.title,
          'notes': switch (assignment) {
            ExamAssignment(:final location) => location,
            CustomDeadline(:final course, :final notes) =>
              [course, notes].where((line) => line.isNotEmpty).join('\n'),
            _ => assignment.course,
          },
          'due': assignment.due.millisecondsSinceEpoch,
          'completed': _assignments.isCompleted(assignment),
        },
    ]);
    if (data == null) {
      throw PlatformException(code: 'reminders_unavailable');
    }
    unawaited(syncCompletions());
    return (
      added: data['added'] ?? 0,
      existing: data['existing'] ?? 0,
      failed: data['failed'] ?? 0,
    );
  }

  Future<void> syncCompletions() async {
    if (!_initialized || _assignments.assignments.isEmpty) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }

    _syncing = true;
    try {
      final epoch = _assignments.identityEpoch;
      final assignments = _assignments.assignments;
      final byKey = {
        for (final assignment in assignments) _keyFor(assignment): assignment,
      };
      final completed = await _channel.invokeMapMethod<String, int>(
        'completed',
        byKey.keys.toList(),
      );
      if (!_initialized ||
          completed == null ||
          epoch != _assignments.identityEpoch ||
          !identical(assignments, _assignments.assignments)) {
        return;
      }
      await _assignments.applyReminderCompletions({
        for (final entry in completed.entries)
          if (byKey[entry.key] case final assignment?)
            entry.key: (assignment: assignment, completedAt: entry.value),
      });
    } on MissingPluginException {
      // The native runner may still be connecting its channel on startup.
    } on PlatformException catch (error) {
      debugPrint('Reminder completion sync failed: ${error.code}');
    } on StateError catch (error) {
      debugPrint('Could not apply reminder completions: $error');
    } finally {
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(syncCompletions());
      }
    }
  }
}
