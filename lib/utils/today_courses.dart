import '../models/course.dart';
import '../models/course_table.dart';
import '../models/custom_course.dart';
import '../models/exam_course.dart';
import '../services/assignment_service.dart';
import '../services/schedule_service.dart';

/// The sessions scheduled for [day], timetable + custom + exam entries merged,
/// in period order. The home page and the schedule island read a day through
/// this so the two cannot disagree about what "today's classes" means.
List<Course> coursesOnDay(
  ScheduleService schedule,
  AssignmentService assignments,
  DateTime day,
) {
  final table = schedule.courseTable;
  final periods = table != null && table.periods.isNotEmpty
      ? table.periods.map((period) => period.toPeriod()).toList()
      : defaultPeriods;
  final begin = schedule.termBegin;
  final date = DateTime(day.year, day.month, day.day);
  final firstDay = begin == null
      ? null
      : DateTime(begin.year, begin.month, begin.day);
  final week = firstDay == null ? 1 : date.difference(firstDay).inDays ~/ 7 + 1;
  if (firstDay != null &&
      (date.isBefore(firstDay) || week > schedule.totalWeeks)) {
    return const [];
  }
  final withCustom = withCustomCourses(
    eamsToDisplayCourses(
      table?.courses ?? const <EamsCourse>[],
      week,
      timetablePeriods: periods,
    ),
    schedule.customCourses,
    week,
    schedule.termBegin,
    periods: periods,
  );
  final all = withExamCourses(
    withCustom,
    examsForSemester(assignments.assignments, schedule.selectedSemesterId),
    week,
    schedule.termBegin,
    periods: periods,
  );
  return all
      .where(
        (course) => course.dayOfWeek == day.weekday && course.occursOn(day),
      )
      .toList()
    ..sort((a, b) => a.gridStart.compareTo(b.gridStart));
}
