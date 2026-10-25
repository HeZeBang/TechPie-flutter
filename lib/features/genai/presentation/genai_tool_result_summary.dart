/// Summaries preserve partial/cache warnings; raw results remain available below.
String genAiToolResultSummary(String name, Map<String, Object?>? result) {
  final error = result?['error'];
  if (error is Map && error['message'] is String) return error['message'] as String;
  if (result?['ok'] != true || result?['result'] is! Map) return '';
  final payload = result!['result'] as Map;
  String text(Object? value) => value?.toString() ?? '';
  List<Map<Object?, Object?>> rows(String key) => (payload[key] is List)
      ? (payload[key] as List).whereType<Map<Object?, Object?>>().toList()
      : [];
  String date(Object? value) {
    final parsed = DateTime.tryParse(text(value));
    if (parsed == null) return text(value);
    final campus = parsed.toUtc().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${campus.month}/${campus.day} ${two(campus.hour)}:${two(campus.minute)}';
  }

  final lines = <String>[];
  switch (name) {
    case 'get_current_time':
      lines.add('${date(payload['campus_time'])} · 校园时间');
    case 'get_semesters':
      lines.addAll(rows('semesters').map((row) => text(row['label'])));
    case 'get_week_schedule':
      if (payload['week'] != null) lines.add('第 ${payload['week']} 周');
      final courses = rows('courses');
      if (courses.isEmpty) lines.add('此范围内没有课程');
      for (final row in courses) {
        final day = row['weekday'];
        final weekday = day is int && day >= 1 && day <= 7 ? '周${'一二三四五六日'[day - 1]}' : '';
        lines.add(
          '${text(row['name'])} · $weekday ${text(row['start_time'])}–${text(row['end_time'])} '
                  '${text(row['location'])}'
              .trim(),
        );
      }
    case 'get_assignments':
      final assignments = rows('assignments');
      if (assignments.isEmpty) lines.add('此范围内没有作业');
      for (final row in assignments) {
        lines.add('${text(row['title'])} · ${text(row['course'])}\n'
            '${row['completed'] == true ? '已完成' : '截止'} ${date(row['due'])}（校园时间）');
      }
    case 'reserve_court':
      if (payload['status'] == 'availability') {
        for (final row in rows('availability')) {
          final courts = row['available_courts'];
          final labels = courts is List
              ? courts
                  .whereType<Map<Object?, Object?>>()
                  .map((court) => text(court['label']))
                  .join('、')
              : '';
          lines.add('${text(row['date'])} ${text(row['time_range'])} · '
              '${labels.isEmpty ? '无可用场地' : labels}');
        }
      } else {
        lines.add(
          payload['success'] == true && payload['status'] == 'booked' ? '预约成功' : '未确认预约成功，请查看场馆记录',
        );
        lines.add('${text(payload['date'])} · ${text(payload['court_number'])} 号场');
      }
    case 'generate_image':
      lines.add('${text(payload['model'])} · ${text(payload['size'])}');
    default:
      if (payload['message'] is String) lines.add(payload['message'] as String);
  }
  if (payload['source'] == 'techpie_cache') lines.add('来自 TechPie 缓存');
  if (payload['partial'] == true || payload['refresh_failed'] == true) {
    lines.add('部分数据未能刷新，结果可能不完整');
  }
  if (payload['loading'] == true) lines.add('数据仍在更新');
  if (payload['truncated'] == true) lines.add('还有更多结果');
  return lines.where((line) => line.trim().isNotEmpty).join('\n');
}
