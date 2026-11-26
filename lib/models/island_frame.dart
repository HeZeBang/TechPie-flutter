import 'assignment.dart';
import 'course.dart';

/// One frame of schedule-island content, rendered by the platform.
class IslandFrame {
  const IslandFrame({
    required this.kind,
    required this.title,
    required this.statusLine,
    this.subTitle,
    this.detail,
    this.expiresAt,
  });

  /// `class` or `deadline` — what the island is about.
  final String kind;
  final String title;

  /// The capsule line: 上课中 / 20 分钟后开始 / 今天截止 23:59.
  final String statusLine;
  final String? subTitle;
  final String? detail;

  /// When this content stops being true: the end of a running class, the start
  /// of an upcoming one, or a deadline's due time. The platform posts the frame
  /// with this expiry, so a dismissal alarm the system never delivered cannot
  /// leave a finished class on screen.
  final DateTime? expiresAt;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'title': title,
    'statusLine': statusLine,
    'subTitle': subTitle,
    'detail': detail,
    'expiresAt': expiresAt?.millisecondsSinceEpoch,
  };

  @override
  String toString() => 'IslandFrame($kind, $title, $statusLine)';
}

/// A class is worth the island from this long before it starts.
const nextClassLead = Duration(minutes: 90);

/// A deadline is worth the island until this long before it is due.
const deadlineLead = Duration(hours: 24);

/// What the island should say at [now], or null when nothing deserves it — a
/// caller dismisses on null rather than leaving a stale frame up.
///
/// [dayCourses] is one day's sessions in period order and [upcomingDeadlines]
/// is already filtered to what the user still owes; both come from the cached
/// schedule and assignment state, never from a live fetch.
IslandFrame? buildIslandFrame({
  required List<Course> dayCourses,
  required List<Assignment> upcomingDeadlines,
  required DateTime now,
}) {
  final minutes = now.hour * 60 + now.minute;
  Course? running;
  Course? upcoming;
  for (final course in dayCourses) {
    final start = parseClockMinutes(course.startTime);
    final end = parseClockMinutes(course.endTime);
    if (start == null || end == null) continue;
    if (start <= minutes && minutes < end) {
      running = course;
      break;
    }
    if (start > minutes) {
      upcoming = course;
      break;
    }
  }

  if (running != null) {
    return IslandFrame(
      kind: 'class',
      title: running.name,
      subTitle: '${running.startTime}–${running.endTime}',
      statusLine: running.source is ExamCourseSource ? '考试中' : '上课中',
      detail: running.location,
      expiresAt: _clockOn(now, parseClockMinutes(running.endTime) ?? 0),
    );
  }

  final gap = upcoming == null
      ? null
      : Duration(
          minutes: (parseClockMinutes(upcoming.startTime) ?? 0) - minutes,
        );
  final deadline = _nearestDeadline(upcomingDeadlines, now);

  if (gap != null && gap <= nextClassLead) {
    return IslandFrame(
      kind: 'class',
      title: upcoming!.name,
      subTitle: '${upcoming.startTime}–${upcoming.endTime}',
      statusLine: gap <= const Duration(hours: 1)
          ? '${gap.inMinutes} 分钟后开始'
          : '${upcoming.startTime} 开始',
      detail: upcoming.location,
      expiresAt: _clockOn(now, parseClockMinutes(upcoming.startTime) ?? 0),
    );
  }

  if (deadline != null) {
    return IslandFrame(
      kind: 'deadline',
      title: deadline.title,
      statusLine: _deadlineStatus(deadline.due, now),
      detail: _deadlineDetail(deadline),
      expiresAt: deadline.due,
    );
  }

  // Nothing imminent: a class hours away or a deadline tomorrow is the home
  // page's business, not the status bar's.
  return null;
}

String _deadlineDetail(Assignment deadline) {
  final course = deadline.course.trim();
  final location = switch (deadline) {
    CustomDeadline(:final location) => location.trim(),
    ExamAssignment(:final location) => location.trim(),
    _ => '',
  };
  final parts = <String>[
    if (course.isNotEmpty) course,
    if (location.isNotEmpty) location,
    deadline.kind.label,
  ];
  return parts.join(' · ');
}

Assignment? _nearestDeadline(
  List<Assignment> deadlines,
  DateTime now, {
  Duration window = deadlineLead,
}) {
  Assignment? best;
  for (final assignment in deadlines) {
    final left = assignment.due.difference(now);
    if (left <= Duration.zero || left > window) continue;
    if (best == null || assignment.due.isBefore(best.due)) best = assignment;
  }
  return best;
}

String _deadlineStatus(DateTime due, DateTime now) {
  final day = _clock(due);
  if (due.year == now.year && due.month == now.month && due.day == now.day) {
    return '今天截止 $day';
  }
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  if (due.year == tomorrow.year &&
      due.month == tomorrow.month &&
      due.day == tomorrow.day) {
    return '明天截止 $day';
  }
  return '${due.difference(now).inHours} 小时后截止';
}

/// [minutes] after midnight on [now]'s date.
DateTime _clockOn(DateTime now, int minutes) =>
    DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

/// Event-driven snapshots for the next three days, including days without a
/// class. Each event is evaluated with the courses for its own calendar date.
Map<int, IslandFrame?> buildIslandTimeline({
  required List<Course> Function(DateTime day) coursesForDay,
  required List<Assignment> deadlines,
  required DateTime now,
}) {
  final horizon = DateTime(now.year, now.month, now.day + 3);
  final events = <DateTime>{horizon};
  void add(DateTime value) {
    if (value.isAfter(now) && !value.isAfter(horizon)) events.add(value);
  }

  for (var offset = 0; offset < 3; offset++) {
    final day = DateTime(now.year, now.month, now.day + offset);
    add(day);
    for (final course in coursesForDay(day)) {
      final startMinutes = parseClockMinutes(course.startTime);
      final endMinutes = parseClockMinutes(course.endTime);
      if (startMinutes == null || endMinutes == null) continue;
      final start = _clockOn(day, startMinutes);
      add(start.subtract(nextClassLead));
      add(start.subtract(const Duration(minutes: 30)));
      add(start.subtract(const Duration(minutes: 10)));
      add(start);
      add(_clockOn(day, endMinutes));
    }
  }
  for (final deadline in deadlines) {
    add(deadline.due.subtract(deadlineLead));
    add(deadline.due);
  }
  final ordered = events.toList()..sort();
  return {
    for (final at in ordered)
      at.millisecondsSinceEpoch: at == horizon
          ? null
          : buildIslandFrame(
              dayCourses: coursesForDay(at),
              upcomingDeadlines: deadlines,
              now: at,
            ),
  };
}
