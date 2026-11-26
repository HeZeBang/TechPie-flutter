import '../models/assignment.dart';
import '../models/course.dart';
import '../models/course_table.dart';
import '../models/custom_course.dart';
import '../models/exam_course.dart';

/// 今日课程合并与状态判定，首页与手环快照共用同一口径。
class ScheduleTimeline {
  /// 合并 EAMS / 自定义 / 考试课程，取 [now] 当天并按开始时间排序。
  static List<Course> todayCourses({
    required CourseTable? table,
    required List<CustomCourse> customCourses,
    required int? week,
    required DateTime? termBegin,
    List<Assignment> assignments = const [],
    String? semesterId,
    required DateTime now,
  }) {
    final periods = table == null
        ? defaultPeriods
        : table.periods.map((p) => p.toPeriod()).toList();
    final merged = withExamCourses(
      withCustomCourses(
        eamsToDisplayCourses(
          table?.courses ?? const [],
          week,
          timetablePeriods: periods,
        ),
        customCourses,
        week,
        termBegin,
        periods: periods,
      ),
      examsForSemester(assignments, semesterId),
      week,
      termBegin,
      periods: periods,
    );
    return merged
        .where((course) => course.dayOfWeek == now.weekday && course.occursOn(now))
        .toList()
      ..sort((a, b) => a.gridStart.compareTo(b.gridStart));
  }

  /// past / ongoing / soon（15 分钟内开课）/ upcoming，与首页判定一致。
  ///
  /// [end] is exclusive: at the minute a class ends it is over, the same way
  /// [buildIslandFrame] reads it. An inclusive bound left the class on screen
  /// as "上课中" for one more minute on every surface.
  static String courseState(Course course, DateTime now) {
    final nowMinutes = now.hour * 60 + now.minute;
    final start = parseClockMinutes(course.startTime);
    final end = parseClockMinutes(course.endTime);
    if (start == null || end == null) return 'upcoming';
    if (nowMinutes >= end) return 'past';
    if (nowMinutes >= start) return 'ongoing';
    final diff = start - nowMinutes;
    return diff > 0 && diff <= 15 ? 'soon' : 'upcoming';
  }
}
