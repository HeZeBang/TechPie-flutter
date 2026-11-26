import '../../../models/course.dart';

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

String formatGlanceClock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

String formatGlanceWeekday(DateTime time) => '周${_weekdays[time.weekday - 1]}';

String formatGlanceMonthDay(DateTime time) =>
    '${time.month.toString().padLeft(2, '0')}/'
    '${time.day.toString().padLeft(2, '0')}';

/// `周三 · 10/28 · 第9周`; the week suffix disappears outside the term.
String formatGlanceDateLine({
  required DateTime now,
  required int? week,
  required bool inTerm,
}) {
  final parts = [
    formatGlanceWeekday(now),
    formatGlanceMonthDay(now),
    if (inTerm && week != null) '第$week周',
  ];
  return parts.join(' · ');
}

/// `今天 14:00`, `明天 09:00`, `10/30 23:59`.
String formatGlanceDue(DateTime due, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(due.year, due.month, due.day);
  final days = target.difference(today).inDays;
  final clock = formatGlanceClock(due);
  if (days <= 0) return '今天 $clock';
  if (days == 1) return '明天 $clock';
  return '${formatGlanceMonthDay(due)} $clock';
}

String formatGlanceCourseTime(Course course) =>
    '${course.startTime}–${course.endTime}';
