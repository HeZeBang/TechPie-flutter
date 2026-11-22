import 'assignment.dart';

typedef ScheduledReminderRemoval = ({String assignmentKey, int after});

/// Local user-side overrides on top of the deadline data we fetch from
/// the backend. Stored in SharedPreferences (non-sensitive).
class AssignmentOverrides {
  final Map<String, bool> completed;
  final Set<String> hidden;
  final Map<String, int> reminderCompletions;
  final Map<String, DeadlineReminderChange> reminderChanges;
  final Map<String, ScheduledReminderRemoval> reminderRemovals;

  AssignmentOverrides({
    Map<String, bool>? completed,
    Set<String>? hidden,
    Map<String, int>? reminderCompletions,
    Map<String, DeadlineReminderChange>? reminderChanges,
    Map<String, ScheduledReminderRemoval>? reminderRemovals,
  })  : completed = completed ?? {},
        hidden = hidden ?? {},
        reminderCompletions = reminderCompletions ?? {},
        reminderChanges = reminderChanges ?? {},
        reminderRemovals = reminderRemovals ?? {};

  AssignmentOverrides copy() => AssignmentOverrides(
        completed: {...completed},
        hidden: {...hidden},
        reminderCompletions: {...reminderCompletions},
        reminderChanges: {...reminderChanges},
        reminderRemovals: {...reminderRemovals},
      );

  static String keyFor(Assignment a) => '${a.platform}:${a.id}';

  bool isHidden(Assignment a) => hidden.contains(keyFor(a));

  /// Returns the effective "submitted" state for the assignment, applying
  /// any local override on top of the platform-derived [Assignment.submitted].
  bool effectiveCompleted(Assignment a) {
    final ov = completed[keyFor(a)];
    if (ov != null) return ov;
    return a.submitted;
  }

  bool hasCompletionOverride(Assignment a) => completed.containsKey(keyFor(a));

  Map<String, dynamic> toJson() => {
        'completed': completed,
        'hidden': hidden.toList(),
        if (reminderCompletions.isNotEmpty)
          'reminderCompletions': reminderCompletions,
        if (reminderChanges.isNotEmpty)
          'reminderChanges': reminderChanges.map((key, change) => MapEntry(key, change.name)),
        if (reminderRemovals.isNotEmpty)
          'reminderRemovals': {
            for (final entry in reminderRemovals.entries)
              entry.key: [entry.value.assignmentKey, entry.value.after],
          },
      };

  factory AssignmentOverrides.fromJson(Map<String, dynamic> json) {
    final c = (json['completed'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as bool),
        ) ??
        <String, bool>{};
    final h =
        ((json['hidden'] as List?) ?? const []).map((e) => e as String).toSet();
    final reminders = json['reminderCompletions'];
    final removals = json['reminderRemovals'];
    return AssignmentOverrides(
      completed: c,
      hidden: h,
      reminderCompletions: {
        if (reminders is Map<String, dynamic>)
          for (final entry in reminders.entries)
            if (entry.value is int) entry.key: entry.value as int,
      },
      reminderChanges: DeadlineReminderChange.decode(json['reminderChanges']),
      reminderRemovals: {
        if (removals is Map<String, dynamic>)
          for (final entry in removals.entries)
            if (entry.value case [final String assignmentKey, final int after])
              entry.key: (assignmentKey: assignmentKey, after: after),
      },
    );
  }
}
