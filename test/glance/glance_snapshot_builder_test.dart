import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/glance/application/glance_snapshot_builder.dart';
import 'package:techpie/features/glance/domain/glance_snapshot.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course_table.dart';

CourseTable _table(DateTime now) {
  const periods = [
    CoursePeriod(index: 1, timeRange: '08:00-08:45'),
    CoursePeriod(index: 2, timeRange: '08:55-09:40'),
    CoursePeriod(index: 3, timeRange: '10:00-10:45'),
  ];
  final weeks = '0${'1' * 30}';
  return CourseTable(
    periods: periods,
    courses: [
      EamsCourse(
        name: '高等数学',
        classroom: 'A101',
        teachers: '张老师',
        weeks: weeks,
        times: {
          now.weekday: [1],
        },
      ),
      EamsCourse(
        name: '大学物理',
        classroom: 'B202',
        teachers: '李老师',
        weeks: weeks,
        times: {
          now.weekday: [3],
        },
      ),
    ],
  );
}

Assignment _assignment(String title, DateTime due) => Assignment(
      id: title,
      platform: 'test',
      title: title,
      course: '课程',
      due: due,
    );

GlanceSnapshot _build({
  required DateTime now,
  List<Assignment> pending = const [],
  bool loggedIn = true,
  bool scheduleLoading = false,
  String? scheduleError,
}) {
  return GlanceSnapshotBuilder.build(
    courseTable: _table(now),
    customCourses: const [],
    termBegin: DateTime(now.year, now.month, now.day).subtract(
      const Duration(days: 7),
    ),
    week: 2,
    rawAssignments: pending,
    pendingAssignments: pending,
    semesterId: '2026-1',
    now: now,
    loggedIn: loggedIn,
    inTerm: true,
    scheduleLoading: scheduleLoading,
    scheduleError: scheduleError,
    assignmentsLoading: false,
    assignmentsError: null,
  );
}

void main() {
  test('merges the day and identifies the current/next course', () {
    final now = DateTime(2026, 10, 26, 8, 10);
    final snapshot = _build(now: now);

    expect(snapshot.hasCourses, isTrue);
    expect(snapshot.courses.map((item) => item.course.name), [
      '高等数学',
      '大学物理',
    ]);
    expect(snapshot.currentCourse?.course.name, '高等数学');
    expect(snapshot.currentCourse?.state, GlanceCourseState.ongoing);
    expect(snapshot.nextCourse?.course.name, '大学物理');
    expect(snapshot.leadCourse?.course.name, '高等数学');
    expect(snapshot.activeCourses.length, 2);
    expect(snapshot.week, 2);
    expect(snapshot.inTerm, isTrue);
  });

  test('after a course ends the next one leads and past stays in the list', () {
    final now = DateTime(2026, 10, 26, 9, 0);
    final snapshot = _build(now: now);

    expect(snapshot.currentCourse, isNull);
    expect(snapshot.nextCourse?.course.name, '大学物理');
    expect(snapshot.leadCourse?.course.name, '大学物理');
    expect(snapshot.courses.first.state, GlanceCourseState.past);
    expect(snapshot.activeCourses.length, 1);
  });

  test('a day with no remaining classes has no lead course', () {
    final now = DateTime(2026, 10, 26, 12, 0);
    final snapshot = _build(now: now);

    expect(snapshot.hasCourses, isTrue);
    expect(snapshot.currentCourse, isNull);
    expect(snapshot.nextCourse, isNull);
    expect(snapshot.leadCourse, isNull);
    expect(snapshot.activeCourses, isEmpty);
  });

  test('sorts pending deadlines and formats their labels', () {
    final now = DateTime(2026, 10, 26, 10, 0);
    final snapshot = _build(
      now: now,
      pending: [
        _assignment('后天', DateTime(2026, 10, 28, 23, 59)),
        _assignment('今天', DateTime(2026, 10, 26, 18, 0)),
        _assignment('明天', DateTime(2026, 10, 27, 9, 0)),
      ],
    );

    expect(
      snapshot.pendingAssignments.map((item) => item.assignment.title),
      ['今天', '明天', '后天'],
    );
    expect(snapshot.pendingAssignments.first.dueLabel, '今天 18:00');
    expect(snapshot.pendingAssignments[1].dueLabel, '明天 09:00');
    expect(snapshot.pendingAssignments.last.dueLabel, '10/28 23:59');
  });

  test('carries login and loading/error flags through unchanged', () {
    final snapshot = _build(
      now: DateTime(2026, 10, 26, 10, 0),
      loggedIn: false,
      scheduleLoading: true,
      scheduleError: '网络错误',
    );
    expect(snapshot.loggedIn, isFalse);
    expect(snapshot.scheduleLoading, isTrue);
    expect(snapshot.scheduleError, '网络错误');
    expect(snapshot.assignmentsLoading, isFalse);
    expect(snapshot.assignmentsError, isNull);
  });
}
