import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/course.dart';
import 'package:techpie/models/course_table.dart';
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

    test('today includes dated courses when the term start is unknown', () {
      final today = DateTime(2026, 9, 8);
      const time = PeriodCourseTime(startPeriod: 1, endPeriod: 1);
      final courses = withCustomCourses(
        const [],
        [
          CustomCourse(id: 'today', name: '今日课程', time: time, date: today),
          CustomCourse(id: 'tomorrow', name: '明日课程', time: time, date: DateTime(2026, 9, 9)),
          const CustomCourse(id: 'weekly', name: '周课', time: time, weekdays: [2], weeks: [1]),
        ],
        0,
        null,
        onDate: today,
      );
      expect(courses.map((course) => course.customId), ['today']);
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

  group('course color scheme and grouping', () {
    test('groups split sessions and recitations by base course code while separating labs', () {
      expect(courseColorKey('模拟电路(EE115A.02)'), 'code:EE115A');
      expect(courseColorKey('模拟电路(EE115A.02D)'), 'code:EE115A');
      expect(courseColorKey('模拟电路实验(EE115AL.01)'), 'code:EE115AL');
      expect(courseColorKey('面向对象编程(C++)'), 'name:面向对象编程(c++)');
      expect(courseColorKey('  机器学习  '), 'name:机器学习');
    });

    test('assigns 12 distinct non-error colors without collisions and stays stable across weeks',
        () {
      final courses = <EamsCourse>[
        // Same course split into two EAMS entries (lecture + recitation, different weeks).
        const EamsCourse(
          name: '模拟电路(EE115A.02)',
          classroom: '物质学院 1-501',
          teachers: '王浩宇',
          weeks: '01110',
          times: {2: [1, 2]},
        ),
        const EamsCourse(
          name: '模拟电路(EE115A.02D)',
          classroom: '教学中心 102',
          teachers: '助教',
          weeks: '01010',
          times: {4: [3, 4]},
        ),
        // 11 more distinct courses (12 unique courses total).
        for (var i = 1; i <= 11; i++)
          EamsCourse(
            name: '课程$i(CS${100 + i}.01)',
            classroom: 'Room $i',
            teachers: 'Teacher $i',
            weeks: '01110',
            times: {1: [1, 2]},
          ),
      ];

      final week1 = eamsToDisplayCourses(courses, 1);
      final week2 = eamsToDisplayCourses(courses, 2);

      final lectureW1 = week1.firstWhere((c) => c.name == '模拟电路(EE115A.02)');
      final recitationW1 = week1.firstWhere((c) => c.name == '模拟电路(EE115A.02D)');
      final lectureW2 = week2.firstWhere((c) => c.name == '模拟电路(EE115A.02)');

      expect(lectureW1.color, recitationW1.color);
      expect(lectureW1.color, lectureW2.color);

      final uniqueColors = week1.map((c) => c.color).toSet();
      expect(uniqueColors, hasLength(12));
      expect(uniqueColors, isNot(contains(CourseColor.error)));
    });

    test('every CourseColor clears WCAG AA contrast in both light and dark modes', () {
      double contrastRatio(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final lighter = la > lb ? la : lb;
        final darker = la > lb ? lb : la;
        return (lighter + 0.05) / (darker + 0.05);
      }

      for (final brightness in Brightness.values) {
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: brightness,
        );
        for (final color in CourseColor.values) {
          final ratio = contrastRatio(
            color.containerColor(scheme),
            color.onContainerColor(scheme),
          );
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${color.name} in $brightness had contrast ${ratio.toStringAsFixed(2)}',
          );
        }
      }
    });
  });
}
