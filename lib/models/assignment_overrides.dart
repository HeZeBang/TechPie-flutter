import 'assignment.dart';

/// Local user-side overrides on top of the deadline data we fetch from
/// the backend. Stored in SharedPreferences (non-sensitive).
class AssignmentOverrides {
  final Map<String, bool> completed;
  final Set<String> hidden;
  final Map<String, int> reminderCompletions;

  AssignmentOverrides({
    Map<String, bool>? completed,
    Set<String>? hidden,
    Map<String, int>? reminderCompletions,
  })  : completed = completed ?? {},
        hidden = hidden ?? {},
        reminderCompletions = reminderCompletions ?? {};

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
      };

  factory AssignmentOverrides.fromJson(Map<String, dynamic> json) {
    final c = (json['completed'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as bool),
        ) ??
        <String, bool>{};
    final h =
        ((json['hidden'] as List?) ?? const []).map((e) => e as String).toSet();
    final reminders = json['reminderCompletions'];
    return AssignmentOverrides(
      completed: c,
      hidden: h,
      reminderCompletions: {
        if (reminders is Map<String, dynamic>)
          for (final entry in reminders.entries)
            if (entry.value is int) entry.key: entry.value as int,
      },
    );
  }
}
