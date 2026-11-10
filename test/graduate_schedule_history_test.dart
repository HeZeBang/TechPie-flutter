import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/graduate_schedule.dart';

void main() {
  final course = {
    'KCMC': '历史课程',
    'BJDM': 'class-1',
    'XNXQDM': '20251',
    'XNXQMC': '2025-2026学年 第一学期',
  };
  final raw = {
    'results': <Map<String, dynamic>>[],
    'xkjgList': [
      {
        ...course,
        'PKSJDD': '1-3,5-12周 星期五[1-2节]甲教室;13-16周 星期五[1-2节]乙教室',
      },
      {
        ...course,
        'BJDM': null,
        'KCDM': 'H2',
        'PKSJDDMS': '3周 星期五[2节]丙教室<br>4周 星期日[1节]丁教室',
      },
      {...course, 'BJDM': null, 'KCDM': 'H3'},
      {...course, 'BJDM': 'later', 'XNXQDM': '20252', 'XNXQMC': '2025-2026学年 第二学期'},
    ],
    'ntkmdList': <Map<String, dynamic>>[],
    'mrjcfadm': 'A',
    'skjcList': [
      {'DM': 1, 'KSSJ': 815, 'JSSJ': 900, 'JCFADM': 'A'},
      {'DM': 2, 'KSSJ': 910, 'JSSJ': 955, 'JCFADM': 'A'},
    ],
  };
  const semester = 'graduate:20251';

  test('text-only enrollments preserve split rooms, sparse weeks and single meetings', () {
    final schedule = GraduateSchedule.fromJson(raw);
    final courses = schedule.tableFor(semester, schedule.defaultScheme(semester)).courses;
    expect(courses, hasLength(4));
    final early = courses.singleWhere((c) => c.classroom == '甲教室');
    expect(early.times, {5: [1, 2]});
    expect(early.isActiveInWeek(3), isTrue);
    expect(early.isActiveInWeek(4), isFalse);
    expect(early.isActiveInWeek(5), isTrue);
    expect(early.isActiveInWeek(13), isFalse);
    expect(courses.singleWhere((c) => c.classroom == '乙教室').weeksText, '13-16周');
    final sunday = courses.singleWhere((c) => c.classroom == '丁教室');
    expect(sunday.times, {7: [1]});
    expect(sunday.weeksText, '4周');
    expect(schedule.unarrangedFor(semester).single['KCDM'], 'H3');
  });

  test('existing structured meetings take precedence over enrollment descriptions', () {
    final schedule = GraduateSchedule.fromJson({
      ...raw,
      'results': [
        {...course, 'XQ': 1, 'KSJCDM': 1, 'JSJCDM': 2, 'ZCMC': '2周', 'JASMC': '结构化教室'},
      ],
    });
    final rooms = schedule.tableFor(semester, 'A').courses.map((c) => c.classroom);
    expect(rooms, unorderedEquals(['结构化教室', '丙教室', '丁教室']));
  });

  test('the common semester label adds the year and ordinal suffix exactly once', () {
    final info = GraduateSchedule.fromJson({...raw, 'currentTerm': '20251'}).semesterInfo;
    expect(info.findSemesterLabel(semester), '2025-2026 第一学期');
    expect(info.findSemesterLabel('graduate:20252'), '2025-2026 第二学期');
  });
}
