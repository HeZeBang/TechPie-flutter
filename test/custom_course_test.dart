import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/course.dart';
import 'package:techpie/models/custom_course.dart';
import 'package:techpie/services/storage_service.dart';

void main() {
  // The term begins on a Monday (2026-09-07), so week N starts (N-1)*7 days
  // after it and weekday N lands on the Monday + (N-1).
  final termBegin = DateTime(2026, 9, 7);

  group('course placement', () {
    const periods = [
      Period(number: 1, startTime: '09:20', endTime: '10:05'),
      Period(number: 2, startTime: '10:15', endTime: '11:00'),
    ];

    test('period time occupies complete rows', () {
      const time = PeriodCourseTime(startPeriod: 1, endPeriod: 2);

      final placement = time.resolve(periods)!;

      expect(placement.gridStart, 0);
      expect(placement.gridEnd, 2);
      expect(placement.usesCustomTime, isFalse);
    });

    test('clock time keeps its minute offset inside a row', () {
      const time = ClockCourseTime(startTime: '10:37', endTime: '10:52');

      final placement = time.resolve(periods)!;

      expect(placement.gridStart, closeTo(1 + 22 / 45, 0.0001));
      expect(placement.gridEnd, closeTo(1 + 37 / 45, 0.0001));
      expect(placement.label, '10:37 – 10:52');
      expect(placement.usesCustomTime, isTrue);
    });
  });

  group('when a session runs', () {
    test('a recurring session is active in the weeks it lists', () {
      const course = CustomCourse(
        id: 'a',
        name: '习题课',
        weekdays: [3],
        time: PeriodCourseTime(startPeriod: 3, endPeriod: 3),
        weeks: [1, 2, 3],
      );

      expect(course.isActiveInWeek(2, termBegin), isTrue);
      expect(course.isActiveInWeek(4, termBegin), isFalse);
      expect(course.weeksLabel, '1-3周');
    });

    test('a one-off lands in the week its own date falls in', () {
      final course = CustomCourse(
        id: 'b',
        name: '补课',
        time: const PeriodCourseTime(startPeriod: 5, endPeriod: 5),
        date: termBegin.add(const Duration(days: 22)), // week 4, Tuesday
      );

      expect(course.isOneOff, isTrue);
      expect(course.isActiveInWeek(4, termBegin), isTrue);
      expect(course.isActiveInWeek(3, termBegin), isFalse);
      expect(course.isActiveInWeek(5, termBegin), isFalse);
      expect(course.weeksLabel, '2026-09-29');
      expect(course.effectiveWeekdays, [2], reason: 'placed by its own date');
    });

    test('a one-off outside the term is in no week at all', () {
      final course = CustomCourse(
        id: 'c',
        name: '开学前',
        time: const PeriodCourseTime(startPeriod: 1, endPeriod: 1),
        date: termBegin.subtract(const Duration(days: 1)),
      );

      for (var week = 1; week <= 25; week++) {
        expect(course.isActiveInWeek(week, termBegin), isFalse);
      }
      expect(teachingWeekOf(course.date!, termBegin), isNull);
    });
  });

  group('columns', () {
    test('a session runs in every weekday it lists', () {
      const course = CustomCourse(
        id: 'a',
        name: '习题课',
        weekdays: [2, 4],
        time: PeriodCourseTime(startPeriod: 3, endPeriod: 3),
        weeks: [1],
      );

      expect(course.effectiveWeekdays, [2, 4]);
      expect(course.toCourses(), hasLength(2));
      expect(
        course.toCourses().map((c) => c.dayOfWeek),
        [2, 4],
        reason: 'one block per column, all pointing back at this session',
      );
      expect(course.toCourses().every((c) => c.customId == 'a'), isTrue);
    });

    test('a one-off ignores stored columns and uses its date', () {
      final course = CustomCourse(
        id: 'b',
        name: '补课',
        weekdays: [2, 4],
        time: const PeriodCourseTime(startPeriod: 1, endPeriod: 1),
        date: termBegin.add(const Duration(days: 2)), // Wednesday
      );

      expect(course.effectiveWeekdays, [3]);
      expect(course.toCourses(), hasLength(1));
    });
  });

  group('overlay onto a week', () {
    test('a week filter drops what does not run that week', () {
      const recurring = CustomCourse(
        id: 'a',
        name: '习题课',
        weekdays: [3],
        time: PeriodCourseTime(startPeriod: 3, endPeriod: 3),
        weeks: [2],
      );

      expect(withCustomCourses(const [], [recurring], 2, termBegin), hasLength(1));
      expect(withCustomCourses(const [], [recurring], 3, termBegin), isEmpty);
    });

    test('includeGhosts keeps it, faded, carrying its id', () {
      const recurring = CustomCourse(
        id: 'a',
        name: '习题课',
        weekdays: [3],
        time: PeriodCourseTime(startPeriod: 3, endPeriod: 3),
        weeks: [2],
      );

      final courses = withCustomCourses(
        const [],
        [recurring],
        3,
        termBegin,
        includeGhosts: true,
      );

      expect(courses, hasLength(1));
      expect(courses.single.isGhost, isTrue);
      expect(courses.single.customId, 'a');
      expect(courses.single.isCustom, isTrue);
    });

    test('a null week means no week filtering', () {
      const recurring = CustomCourse(
        id: 'a',
        name: '习题课',
        weekdays: [3],
        time: PeriodCourseTime(startPeriod: 3, endPeriod: 3),
        weeks: [2],
      );

      expect(withCustomCourses(const [], [recurring], null, termBegin), hasLength(1));
    });
  });

  group('json round trip', () {
    test('a recurring session survives', () {
      const course = CustomCourse(
        id: 'a',
        semesterId: 'sem-1',
        name: '习题课',
        location: '教1-101',
        teachers: '张老师',
        weekdays: [2, 4],
        time: PeriodCourseTime(startPeriod: 3, endPeriod: 4),
        weeks: [1, 3, 5],
        color: CourseColor.pink,
      );

      final restored = CustomCourse.fromJson(course.toJson());

      expect(restored.id, 'a');
      expect(restored.semesterId, 'sem-1');
      expect(restored.name, '习题课');
      expect(restored.location, '教1-101');
      expect(restored.teachers, '张老师');
      expect(restored.weekdays, [2, 4]);
      expect(restored.startPeriod, 3);
      expect(restored.endPeriod, 4);
      expect(restored.weeks, [1, 3, 5]);
      expect(restored.date, isNull);
      expect(restored.color, CourseColor.pink);
    });

    test('custom clock times survive', () {
      const course = CustomCourse(
        id: 'a',
        name: '习题课',
        weekdays: [3],
        time: ClockCourseTime(startTime: '19:00', endTime: '20:30'),
        weeks: [1],
      );

      final restored = CustomCourse.fromJson(course.toJson());

      expect(restored.startTime, '19:00');
      expect(restored.endTime, '20:30');
      expect(restored.startPeriod, isNull);
      expect(restored.endPeriod, isNull);
      expect(restored.toCourses().single.startTime, '19:00');
    });

    test('legacy clock records drop their old display-only periods', () {
      final restored = CustomCourse.fromJson({
        'id': 'legacy',
        'name': '晚间习题课',
        'weekdays': [3],
        'weeks': [1],
        'startPeriod': 1,
        'endPeriod': 1,
        'startTime': '19:00',
        'endTime': '20:30',
      });

      expect(restored.usesCustomTime, isTrue);
      expect(restored.startPeriod, isNull);
      expect(restored.endPeriod, isNull);
    });

    test('missing time data is rejected instead of becoming first period', () {
      expect(
        () => CustomCourse.fromJson({
          'id': 'broken',
          'name': 'broken',
          'weekdays': [1],
          'weeks': [1],
        }),
        throwsFormatException,
      );
    });

    test('a partial clock range does not fall back to stored periods', () {
      expect(
        () => CustomCourse.fromJson({
          'id': 'broken-clock',
          'name': 'broken',
          'weekdays': [1],
          'weeks': [1],
          'startPeriod': 1,
          'endPeriod': 1,
          'startTime': '19:00',
        }),
        throwsFormatException,
      );
    });

    test('a one-off survives, and a stale weeks list beside its date is dropped', () {
      final course = CustomCourse(
        id: 'b',
        name: '补课',
        time: const PeriodCourseTime(startPeriod: 5, endPeriod: 5),
        date: DateTime(2026, 9, 25),
      );

      final restored = CustomCourse.fromJson({
        ...course.toJson(),
        // The two are exclusive; a hand-edited blob must not draw it twice.
        'weeks': [1, 2, 3],
      });

      expect(restored.date, DateTime(2026, 9, 25));
      expect(restored.isOneOff, isTrue);
      expect(restored.weeks, isEmpty);
    });

    test('a record written before weekdays became a list still reads', () {
      final restored = CustomCourse.fromJson({
        'id': 'a',
        'name': 'x',
        'dayOfWeek': 4,
        'startPeriod': 1,
        'endPeriod': 1,
      });

      expect(restored.weekdays, [4]);
    });

    test('an unusable color falls back instead of throwing', () {
      final restored = CustomCourse.fromJson({
        'id': 'a',
        'name': 'x',
        'weekdays': [1],
        'startPeriod': 1,
        'endPeriod': 1,
        'color': 'not-a-color',
      });

      expect(restored.color, CourseColor.primary);
    });
  });

  test('weeks print as ranges', () {
    expect(formatWeekRanges([1, 2, 3, 4]), '1-4周');
    expect(formatWeekRanges([1, 3, 5]), '1, 3, 5周');
    expect(formatWeekRanges([1, 2, 4, 5, 6]), '1-2, 4-6周');
    expect(formatWeekRanges([]), '');
  });

  test('storage skips only an invalid record', () async {
    final valid = const CustomCourse(
      id: 'valid',
      name: '习题课',
      weekdays: [1],
      time: PeriodCourseTime(startPeriod: 1, endPeriod: 1),
      weeks: [1],
    ).toJson();
    SharedPreferences.setMockInitialValues({
      'schedule_custom_courses_semester': jsonEncode([
        {'id': 'broken', 'name': 'broken'},
        valid,
      ]),
    });
    final preferences = await SharedPreferences.getInstance();

    final courses = StorageService(preferences).loadCustomCourses('semester');

    expect(courses.map((course) => course.id), ['valid']);
  });
}
