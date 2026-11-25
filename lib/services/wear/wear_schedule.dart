import '../../models/assignment.dart';
import '../../models/course.dart';
import '../../models/course_table.dart';
import '../../models/custom_course.dart';
import '../../models/exam_course.dart';
import 'wear_protocol.dart';

/// Build the same course blocks as the phone for seven campus-calendar days.
List<WearCourse> buildWearSchedule({
  required CourseTable table,
  required DateTime termBegin,
  required DateTime from,
  required List<CustomCourse> customCourses,
  required Iterable<ExamAssignment> exams,
}) {
  final periods = table.periods.isEmpty
      ? defaultPeriods
      : table.periods.map((p) => p.toPeriod()).toList();
  DateTime campusClock(DateTime time) {
    final value = time.toUtc().add(const Duration(hours: 8));
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
  }

  final campusExams = exams
      .map(
        (exam) => ExamAssignment(
          id: exam.id,
          title: exam.title,
          course: exam.course,
          due: campusClock(exam.due),
          lateDue: exam.lateDue == null ? null : campusClock(exam.lateDue!),
          semesterId: exam.semesterId,
          location: exam.location,
          batchName: exam.batchName,
        ),
      )
      .toList();
  final result = <WearCourse>[];
  // Campus times are Asia/Shanghai, independent of the phone's current zone.
  final campusDay = from.toUtc().add(const Duration(hours: 8));
  final first = DateTime.utc(campusDay.year, campusDay.month, campusDay.day);
  final term = DateTime.utc(termBegin.year, termBegin.month, termBegin.day);
  for (var offset = 0; offset < 7; offset++) {
    final day = first.add(Duration(days: offset));
    final week = (day.difference(term).inDays / 7).floor() + 1;
    final courses = withExamCourses(
      withCustomCourses(
        eamsToDisplayCourses(table.courses, week, timetablePeriods: periods),
        customCourses,
        week,
        termBegin,
        periods: periods,
      ),
      campusExams,
      week,
      termBegin,
      periods: periods,
    );
    for (final course in courses
        .where((c) => c.dayOfWeek == day.weekday && c.occursOn(day))) {
      final start = parseClockMinutes(course.startTime)!;
      final end = parseClockMinutes(course.endTime)!;
      result.add(
        WearCourse(
          name: String.fromCharCodes(course.name.runes.take(80)),
          location: String.fromCharCodes(course.location.runes.take(40)),
          startAt: day.add(Duration(minutes: start - 480)),
          endAt: day.add(Duration(minutes: end - 480)),
        ),
      );
    }
  }
  result.sort((a, b) => a.startAt.compareTo(b.startAt));
  return result;
}
