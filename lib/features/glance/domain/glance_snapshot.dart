import '../../../models/assignment.dart';
import '../../../models/course.dart';

enum GlanceCourseState { past, ongoing, soon, upcoming }

final class GlanceCourse {
  const GlanceCourse({required this.course, required this.state});

  final Course course;
  final GlanceCourseState state;

  bool get isPast => state == GlanceCourseState.past;

  bool get isOngoing => state == GlanceCourseState.ongoing;
}

final class GlanceAssignment {
  const GlanceAssignment({required this.assignment, required this.dueLabel});

  final Assignment assignment;
  final String dueLabel;
}

/// A point-in-time view of today's schedule and pending deadlines.
final class GlanceSnapshot {
  const GlanceSnapshot({
    required this.now,
    required this.week,
    required this.inTerm,
    required this.loggedIn,
    required this.courses,
    required this.pendingAssignments,
    required this.scheduleLoading,
    required this.scheduleError,
    required this.assignmentsLoading,
    required this.assignmentsError,
  });

  final DateTime now;
  final int? week;
  final bool inTerm;
  final bool loggedIn;
  final List<GlanceCourse> courses;
  final List<GlanceAssignment> pendingAssignments;
  final bool scheduleLoading;
  final String? scheduleError;
  final bool assignmentsLoading;
  final String? assignmentsError;

  bool get hasCourses => courses.isNotEmpty;

  bool get hasPending => pendingAssignments.isNotEmpty;

  GlanceCourse? get currentCourse {
    for (final course in courses) {
      if (course.isOngoing) return course;
    }
    return null;
  }

  GlanceCourse? get nextCourse {
    for (final course in courses) {
      if (course.state == GlanceCourseState.soon ||
          course.state == GlanceCourseState.upcoming) {
        return course;
      }
    }
    return null;
  }

  /// Today's courses that are still ongoing or upcoming, in start order.
  List<GlanceCourse> get activeCourses =>
      [for (final course in courses) if (!course.isPast) course];

  /// The course to lead with: the one in progress, otherwise the next one.
  GlanceCourse? get leadCourse => currentCourse ?? nextCourse;
}
