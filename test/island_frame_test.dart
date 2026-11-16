import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course.dart';
import 'package:techpie/models/island_frame.dart';

Course _course({
  required String name,
  required String start,
  required String end,
  String location = 'D202',
}) {
  return Course(
    name: name,
    location: location,
    dayOfWeek: 1,
    placement: CoursePlacement(
      startPeriod: 1,
      endPeriod: 2,
      gridStart: 0,
      gridEnd: 2,
      usesCustomTime: true,
      startTime: start,
      endTime: end,
      label: '$start – $end',
    ),
  );
}

Assignment _deadline({
  required String title,
  required DateTime due,
  String course = '离散数学',
}) {
  return Assignment(
    id: title,
    platform: 'blackboard',
    title: title,
    course: course,
    due: due,
  );
}

void main() {
  test('deadlines have native events even without classes', () {
    final now = DateTime(2026, 11, 15, 8);
    final due = DateTime(2026, 11, 16, 12);
    final timeline = buildIslandTimeline(
      coursesForDay: (_) => [],
      deadlines: [_deadline(title: 'Report', due: due)],
      now: now,
    );
    expect(
      timeline[due.subtract(deadlineLead).millisecondsSinceEpoch]?.title,
      'Report',
    );
    expect(timeline.containsKey(due.millisecondsSinceEpoch), isTrue);
    expect(timeline[due.millisecondsSinceEpoch], isNull);
    expect(timeline.values.last, isNull);
  });
  test(
    'next-day frames are computed from that day rather than the current week',
    () {
      final now = DateTime(2026, 11, 15, 20);
      final timeline = buildIslandTimeline(
        coursesForDay: (day) => day.day == 16
            ? [_course(name: 'Monday only', start: '08:15', end: '09:55')]
            : [],
        deadlines: [],
        now: now,
      );
      expect(
        timeline[DateTime(2026, 11, 16, 8, 15).millisecondsSinceEpoch]?.title,
        'Monday only',
      );
      expect(
        timeline[DateTime(2026, 11, 16, 9, 55).millisecondsSinceEpoch],
        isNull,
      );
    },
  );
  final mondayMorning = DateTime(2026, 3, 9, 9, 30);

  test('a running class owns the island', () {
    final frame = buildIslandFrame(
      dayCourses: [
        _course(name: '高等数学', start: '08:15', end: '09:55'),
        _course(name: '线性代数', start: '10:15', end: '11:55'),
      ],
      upcomingDeadlines: [
        _deadline(
          title: '作业 3',
          due: mondayMorning.add(const Duration(hours: 2)),
        ),
      ],
      now: mondayMorning,
    );

    expect(frame, isNotNull);
    expect(frame!.kind, 'class');
    expect(frame.title, '高等数学');
    expect(frame.statusLine, '上课中');
    expect(frame.subTitle, '08:15–09:55');
    expect(frame.detail, 'D202');
  });

  test('a class starting soon beats a deadline', () {
    final frame = buildIslandFrame(
      dayCourses: [_course(name: '线性代数', start: '10:15', end: '11:55')],
      upcomingDeadlines: [
        _deadline(
          title: '作业 3',
          due: mondayMorning.add(const Duration(hours: 3)),
        ),
      ],
      now: mondayMorning,
    );

    expect(frame?.kind, 'class');
    expect(frame?.statusLine, '45 分钟后开始');
  });

  test('a class further out is shown by its start time', () {
    final frame = buildIslandFrame(
      dayCourses: [_course(name: '大学英语', start: '11:00', end: '11:55')],
      upcomingDeadlines: const [],
      now: mondayMorning,
    );

    expect(frame?.statusLine, '11:00 开始');
  });

  test('a class more than 90 minutes away leaves the island empty', () {
    final frame = buildIslandFrame(
      dayCourses: [_course(name: '大学英语', start: '14:00', end: '15:00')],
      upcomingDeadlines: const [],
      now: mondayMorning,
    );

    expect(frame, isNull);
  });

  test('a deadline due today is shown when there is no class', () {
    final frame = buildIslandFrame(
      dayCourses: const [],
      upcomingDeadlines: [
        _deadline(title: '期中论文', due: DateTime(2026, 3, 9, 23, 59)),
      ],
      now: mondayMorning,
    );

    expect(frame?.kind, 'deadline');
    expect(frame?.statusLine, '今天截止 23:59');
    expect(frame?.detail, '离散数学 · 作业');
  });

  test('the soonest deadline wins and tomorrow is named', () {
    final frame = buildIslandFrame(
      dayCourses: const [],
      upcomingDeadlines: [
        _deadline(title: '实验报告', due: DateTime(2026, 3, 11, 10, 0)),
        _deadline(title: 'Reading quiz', due: DateTime(2026, 3, 10, 8, 0)),
      ],
      now: mondayMorning,
    );

    expect(frame?.title, 'Reading quiz');
    expect(frame?.statusLine, '明天截止 08:00');
  });

  test('a deadline beyond the window is not shown', () {
    final frame = buildIslandFrame(
      dayCourses: const [],
      upcomingDeadlines: [_deadline(title: '期末', due: DateTime(2026, 3, 20))],
      now: mondayMorning,
    );

    expect(frame, isNull);
  });

  test('the frame serializes the keys the platform reads', () {
    final frame = buildIslandFrame(
      dayCourses: [_course(name: '高等数学', start: '09:00', end: '10:00')],
      upcomingDeadlines: const [],
      now: mondayMorning,
    );

    expect(frame!.toJson().keys.toList(), [
      'kind',
      'title',
      'statusLine',
      'subTitle',
      'detail',
      'expiresAt',
    ]);
  });

  test('a running class expires when it ends', () {
    final frame = buildIslandFrame(
      dayCourses: [_course(name: '高等数学', start: '08:15', end: '09:55')],
      upcomingDeadlines: const [],
      now: mondayMorning,
    );

    expect(frame!.expiresAt, DateTime(2026, 3, 9, 9, 55));
  });

  test('an upcoming class expires when it starts', () {
    final frame = buildIslandFrame(
      dayCourses: [_course(name: '线性代数', start: '10:15', end: '11:55')],
      upcomingDeadlines: const [],
      now: mondayMorning,
    );

    expect(frame!.expiresAt, DateTime(2026, 3, 9, 10, 15));
  });

  test('a deadline frame expires at its due time', () {
    final due = DateTime(2026, 3, 9, 23, 59);
    final frame = buildIslandFrame(
      dayCourses: const [],
      upcomingDeadlines: [_deadline(title: '期中论文', due: due)],
      now: mondayMorning,
    );

    expect(frame!.expiresAt, due);
  });
}
