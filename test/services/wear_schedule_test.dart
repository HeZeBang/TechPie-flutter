import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course.dart';
import 'package:techpie/models/course_table.dart';
import 'package:techpie/models/custom_course.dart';
import 'package:techpie/services/wear/wear_schedule.dart';

void main() {
  const table = CourseTable(
    periods: [
      CoursePeriod(index: 1, timeRange: '08:00-08:45'),
    ],
    courses: [
      EamsCourse(
        name: '第一周课程',
        classroom: '101',
        teachers: '',
        weeks: '010',
        times: {
          1: [1],
        },
      ),
      EamsCourse(
        name: '第二周课程',
        classroom: '202',
        teachers: '',
        weeks: '001',
        times: {
          1: [1],
        },
      ),
    ],
  );
  test('campus midnight crosses a teaching-week boundary even on a UTC phone',
      () {
    final courses = buildWearSchedule(
      table: table,
      termBegin: DateTime(2026, 11, 9),
      from: DateTime.utc(2026, 11, 15, 17),
      customCourses: [],
      exams: [],
    );
    expect(courses.map((c) => c.name), ['第二周课程']);
    expect(courses.single.startAt, DateTime.utc(2026, 11, 16));
    expect(courses.single.endAt, DateTime.utc(2026, 11, 16, 0, 45));
  });
  test('custom sessions and exams retain their own campus day and clock range',
      () {
    final courses = buildWearSchedule(
      table: const CourseTable(periods: [], courses: []),
      termBegin: DateTime(2026, 11, 9),
      from: DateTime.utc(2026, 11, 12, 17),
      customCourses: [
        CustomCourse(
          id: 'lab',
          name: '实验课',
          date: DateTime(2026, 11, 13),
          time: const ClockCourseTime(startTime: '09:00', endTime: '09:50'),
        ),
      ],
      exams: [
        ExamAssignment(
          id: 'exam',
          title: '物理考试',
          course: '物理',
          due: DateTime.utc(2026, 11, 13, 2),
          lateDue: DateTime.utc(2026, 11, 13, 4),
          semesterId: '1',
          location: '201',
          batchName: '',
        ),
      ],
    );
    expect(courses.map((c) => c.name), ['实验课', '物理考试']);
    expect(courses.first.startAt, DateTime.utc(2026, 11, 13, 1));
    expect(courses.last.endAt, DateTime.utc(2026, 11, 13, 4));
  });
  test('seven-day window excludes ghosts and courses beyond the window', () {
    final courses = buildWearSchedule(
      table: table,
      termBegin: DateTime(2026, 11, 9),
      from: DateTime.utc(2026, 11, 9),
      customCourses: [],
      exams: [],
    );
    expect(courses.map((c) => c.name), ['第一周课程']);
    expect(courses.every((c) => c.endAt.isAfter(c.startAt)), true);
  });
}
