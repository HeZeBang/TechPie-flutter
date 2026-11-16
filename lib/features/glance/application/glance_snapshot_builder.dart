import '../../../models/assignment.dart';
import '../../../models/course.dart';
import '../../../models/course_table.dart';
import '../../../models/custom_course.dart';
import '../../../services/schedule_timeline_service.dart';
import '../domain/glance_snapshot.dart';
import '../presentation/glance_formatters.dart';

/// Builds the glance snapshot from raw service data.
///
/// The course merge and state rules come from [ScheduleTimeline], the same
/// source Home and the band app use. Deadline filtering is done by the caller
/// through [AssignmentService.visibleAssignments]/`isCompleted` so hidden and
/// locally completed items never leak into the small surface.
final class GlanceSnapshotBuilder {
  const GlanceSnapshotBuilder._();

  static GlanceSnapshot build({
    required CourseTable? courseTable,
    required List<CustomCourse> customCourses,
    required DateTime? termBegin,
    required int? week,
    required List<Assignment> rawAssignments,
    required List<Assignment> pendingAssignments,
    required String? semesterId,
    required DateTime now,
    required bool loggedIn,
    required bool inTerm,
    required bool scheduleLoading,
    required String? scheduleError,
    required bool assignmentsLoading,
    required String? assignmentsError,
  }) {
    final courses = ScheduleTimeline.todayCourses(
      table: courseTable,
      customCourses: customCourses,
      week: week,
      termBegin: termBegin,
      assignments: rawAssignments,
      semesterId: semesterId,
      now: now,
    );
    final pending = [...pendingAssignments]
      ..sort((a, b) => a.due.compareTo(b.due));

    return GlanceSnapshot(
      now: now,
      week: week,
      inTerm: inTerm,
      loggedIn: loggedIn,
      courses: [
        for (final course in courses)
          GlanceCourse(course: course, state: _stateOf(course, now)),
      ],
      pendingAssignments: [
        for (final assignment in pending)
          GlanceAssignment(
            assignment: assignment,
            dueLabel: formatGlanceDue(assignment.due, now),
          ),
      ],
      scheduleLoading: scheduleLoading,
      scheduleError: scheduleError,
      assignmentsLoading: assignmentsLoading,
      assignmentsError: assignmentsError,
    );
  }

  static GlanceCourseState _stateOf(Course course, DateTime now) =>
      switch (ScheduleTimeline.courseState(course, now)) {
        'past' => GlanceCourseState.past,
        'ongoing' => GlanceCourseState.ongoing,
        'soon' => GlanceCourseState.soon,
        _ => GlanceCourseState.upcoming,
      };
}
