import '../models/course.dart';
import '../models/course_table.dart';
import '../models/custom_course.dart';
import '../models/exam_course.dart';
import '../services/assignment_service.dart';
import '../services/schedule_service.dart';

/// The sessions scheduled for [day], timetable + custom + exam entries merged,
/// in clock order. Supports both undergraduate and graduate timetables.
List<Course> coursesOnDay(
  ScheduleService schedule,
  AssignmentService assignments,
  DateTime day,
) {
  final table = schedule.fullCourseTable;
  final periods = table != null && table.periods.isNotEmpty
      ? table.periods.map((period) => period.toPeriod()).toList()
      : defaultPeriods;
  final begin = schedule.termBegin;
  final date = DateTime(day.year, day.month, day.day);
  final firstDay =
      begin == null ? null : DateTime(begin.year, begin.month, begin.day);
  final int week;
  if (schedule.isGraduate) {
    week = teachingWeekOf(date, begin) ?? 0;
  } else {
    week = firstDay == null ? 1 : date.difference(firstDay).inDays ~/ 7 + 1;
  }
  final inTerm = schedule.isGraduate ||
      firstDay == null ||
      (!date.isBefore(firstDay) && week <= schedule.totalWeeks);
  final timetableCourses =
      inTerm ? (table?.courses ?? const <EamsCourse>[]) : const <EamsCourse>[];
  final withCustom = withCustomCourses(
    eamsToDisplayCourses(
      timetableCourses,
      week,
      timetablePeriods: periods,
      onDate: date,
    ),
    schedule.customCourses,
    week,
    begin,
    periods: periods,
    onDate: date,
  );
  final all = withExamCourses(
    withCustom,
    examsForSemester(assignments.assignments, schedule.selectedSemesterId),
    week,
    begin,
    periods: periods,
  );
  return all
      .where(
        (course) => course.dayOfWeek == date.weekday && course.occursOn(date),
      )
      .toList()
    ..sort((a, b) {
      final startA = parseClockMinutes(a.startTime) ?? 0;
      final startB = parseClockMinutes(b.startTime) ?? 0;
      return startA.compareTo(startB);
    });
}
