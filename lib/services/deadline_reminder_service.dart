import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../features/campus_card/core/async_mutex.dart';
import '../models/assignment.dart';
import 'assignment_service.dart';

typedef ReminderExportResult = ({int added, int existing, int failed});
typedef ReminderSelectionResult = ({
  Set<String> added,
  Set<String> existing,
  Set<String> removed,
  int failed,
});

class DeadlineReminderService with WidgetsBindingObserver {
  DeadlineReminderService(
    this._assignments, {
    MethodChannel channel = const MethodChannel('techpie/deadline_reminders'),
  }) : _channel = channel;

  final AssignmentService _assignments;
  final MethodChannel _channel;
  late final _writes = AsyncMutex();
  List<Assignment>? _lastAssignments;
  int? _lastIdentityEpoch;
  int? _lastChangesRevision;
  Timer? _removalTimer;
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
    _lastChangesRevision = null;
    _removalTimer?.cancel();
    _removalTimer = null;
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
    final revision = _assignments.reminderChangesRevision;
    if (identical(assignments, _lastAssignments) &&
        epoch == _lastIdentityEpoch &&
        revision == _lastChangesRevision) {
      return;
    }
    _lastAssignments = assignments;
    _lastIdentityEpoch = epoch;
    _lastChangesRevision = revision;
    unawaited(syncCompletions());
  }

  Future<ReminderExportResult> add(Iterable<Assignment> assignments) async {
    final result = await saveSelection(
      epoch: _assignments.identityEpoch,
      add: assignments.map(_assignments.reminderKeyFor).toSet(),
      remove: const {},
    );
    return (added: result.added.length, existing: result.existing.length, failed: result.failed);
  }

  Future<Set<String>> linkedKeys(Set<String> keys, {required int epoch}) =>
      _writes.protect(() async {
        _checkEpoch(epoch);
        final linked = await _channel.invokeListMethod<String>('linked', keys.toList());
        _checkEpoch(epoch);
        if (linked == null) throw PlatformException(code: 'reminders_unavailable');
        return linked.toSet().intersection(keys);
      });

  Future<ReminderSelectionResult> saveSelection({
    required int epoch,
    required Set<String> add,
    required Set<String> remove,
  }) async {
    final result = await _writes.protect(() async {
      _checkEpoch(epoch);
      final current = {
        for (final assignment in _assignments.assignments)
          _assignments.reminderKeyFor(assignment): assignment,
      };
      final data = await _channel.invokeMapMethod<String, List<Object?>>('saveSelection', {
        'add': [
          for (final key in add)
            if (current[key] case final assignment?)
              {
                'key': key,
                ..._details(assignment),
                'completed': _assignments.isCompleted(assignment),
              },
        ],
        'remove': remove.toList(),
      });
      if (data == null) throw PlatformException(code: 'reminders_unavailable');
      final added = {...?data['added']?.whereType<String>()}.intersection(add);
      final existing = {...?data['existing']?.whereType<String>()}.intersection(add);
      final removed = {...?data['removed']?.whereType<String>()}.intersection(remove);
      return (
        added: added,
        existing: existing,
        removed: removed,
        failed: add.difference(added.union(existing)).length + remove.difference(removed).length,
      );
    });
    unawaited(syncCompletions());
    return result;
  }

  void _checkEpoch(int epoch) {
    if (epoch != _assignments.identityEpoch) {
      throw PlatformException(code: 'reminders_workspace_changed');
    }
  }

  Map<String, Object> _details(Assignment assignment) => {
        'title': assignment.title,
        'notes': switch (assignment) {
          ExamAssignment(:final location) => location,
          CustomDeadline(:final course, :final location, :final notes) => [
              if (course.isNotEmpty) course,
              if (location.isNotEmpty) '地点：$location',
              if (notes.isNotEmpty) notes,
            ].join('\n'),
          _ => assignment.course,
        },
        if (assignment is CustomDeadline) 'location': assignment.location,
        'due': assignment.due.millisecondsSinceEpoch,
      };

  Future<void> syncCompletions() async {
    if (!_initialized) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }

    _syncing = true;
    try {
      final epoch = _assignments.identityEpoch;
      await _syncChanges(epoch);
      if (!_initialized || epoch != _assignments.identityEpoch) return;

      final assignments = _assignments.assignments;
      final pending = _assignments.reminderSyncWork.changes;
      final byKey = {
        for (final assignment in assignments)
          if (_assignments.reminderKeyFor(assignment) case final key
              when !pending.containsKey(key))
            key: assignment,
      };
      if (byKey.isEmpty) return;
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
      await _assignments.applyReminderCompletions(
        {
          for (final entry in completed.entries)
            if (byKey[entry.key] case final assignment?)
              entry.key: (assignment: assignment, completedAt: entry.value),
        },
        epoch: epoch,
      );
    } on MissingPluginException {
      // The native runner may still be connecting its channel on startup.
    } on PlatformException catch (error) {
      debugPrint('Reminder completion sync failed: ${error.code}');
    } on StateError catch (error) {
      debugPrint('Could not apply reminder completions: ${error.runtimeType}');
    } finally {
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(syncCompletions());
      }
    }
  }

  Future<void> _syncChanges(int epoch) async {
    try {
      await _writes.protect(() async {
        if (!_initialized || epoch != _assignments.identityEpoch) return;
        final (:changes, :nextRemoval) = await _assignments.readReminderSyncWork();
        if (!_initialized || epoch != _assignments.identityEpoch) return;
        _removalTimer?.cancel();
        _removalTimer = nextRemoval == null
            ? null
            : Timer(nextRemoval, () => unawaited(syncCompletions()));

        if (changes.isNotEmpty) {
          final resolved = await _channel.invokeListMethod<String>(
            'change',
            changes.map((key, change) => MapEntry(key, change.name)),
          );
          if (!_initialized || epoch != _assignments.identityEpoch) return;
          if (resolved != null && resolved.isNotEmpty) {
            await _assignments.acknowledgeReminderChanges(
              {
                for (final key in resolved)
                  if (changes[key] case final change?) key: change,
              },
              epoch: epoch,
            );
          }
        }

        if (!_initialized || epoch != _assignments.identityEpoch) return;
        final edits = _assignments.pendingReminderEdits;
        if (edits.isEmpty) return;
        final saved = await _channel.invokeListMethod<String>(
          'edit',
          edits.map((key, deadline) => MapEntry(key, _details(deadline))),
        );
        if (!_initialized || epoch != _assignments.identityEpoch || saved == null) return;
        await _assignments.acknowledgeReminderEdits(
          saved.map((key) => edits[key]).whereType<CustomDeadline>(),
          epoch: epoch,
        );
      });
    } on PlatformException catch (error) {
      debugPrint('Could not write reminder changes: ${error.code}');
    }
  }
}
