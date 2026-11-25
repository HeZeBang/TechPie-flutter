import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/course.dart';

void main() {
  final placement = const PeriodCourseTime(startPeriod: 1, endPeriod: 1).resolve(defaultPeriods)!;
  Course course(String name, [CourseSource source = const EamsCourseSource()]) {
    return Course(name: name, location: 'H101', dayOfWeek: 1, placement: placement, source: source);
  }

  test('presets preserve levels and leave other subjects and labs intact', () {
    for (final entry in {
      '普通物理': '普物',
      '普通物理学 II': '普物II',
      '线性代数': '线代',
      '大学物理（上）': '大物（上）',
      '高等数学（下）(MATH1002)': '高数（下）',
      '普通物理实验': '普通物理实验',
      'Unknown course': 'Unknown course',
    }.entries) {
      expect(course(entry.key).defaultShortName, entry.value);
    }
  });

  test('custom titles follow the session ID and exams keep their own titles', () {
    const first = CustomCourseSource('first');
    expect(course('普通物理', first).defaultShortName, '普通物理');
    expect(course('普通物理', first).shortNameKey, course('New title', first).shortNameKey);
    expect(course('普通物理', first).shortNameKey, isNot(course('普通物理').shortNameKey));
    expect(course('普通物理', const ExamCourseSource('final')).shortNameKey, isNull);
  });
}
