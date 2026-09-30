import 'package:flutter/foundation.dart';

import '../../models/course.dart';
import '../../models/course_table.dart';
import '../../models/custom_course.dart';
import 'ics_file_saver.dart';

class StructuredLocation {
  final String keyword;
  final String title;
  final double latitude;
  final double longitude;

  const StructuredLocation({
    required this.keyword,
    required this.title,
    required this.latitude,
    required this.longitude,
  });
}

class _CalendarEventData {
  final String name;
  final String classroom;
  final String teachers;
  final String uidSeed;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final String location;
  final StructuredLocation? structuredLocation;

  const _CalendarEventData({
    required this.name,
    required this.classroom,
    required this.teachers,
    required this.uidSeed,
    required this.startDateTime,
    required this.endDateTime,
    required this.location,
    required this.structuredLocation,
  });
}

class IcsExportService {
  static const List<StructuredLocation> _structuredLocations = [
    StructuredLocation(
      keyword: '信息学院',
      title: '上海科技大学信息科学与技术学院',
      latitude: 31.18043,
      longitude: 121.5907,
    ),
    StructuredLocation(
      keyword: '创管学院',
      title: '上海科技大学创业与管理学院',
      latitude: 31.17872,
      longitude: 121.59061,
    ),
    StructuredLocation(
      keyword: '生命学院',
      title: '上海科技大学生命科学与技术学院',
      latitude: 31.1818,
      longitude: 121.59018,
    ),
    StructuredLocation(
      keyword: '物质学院',
      title: '上海科技大学物质科学与技术学院',
      latitude: 31.17894,
      longitude: 121.58821,
    ),
    StructuredLocation(
      keyword: '教学中心',
      title: '上海科技大学教学中心',
      latitude: 31.17772,
      longitude: 121.59093,
    ),
    StructuredLocation(
      keyword: '创艺学院',
      title: '上海科技大学创意与艺术学院',
      latitude: 31.17887,
      longitude: 121.58887,
    ),
    StructuredLocation(
      keyword: '生医工学院',
      title: '上海科技大学生物医学工程学院',
      latitude: 31.17997,
      longitude: 121.59122,
    ),
  ];

  static const String _structuredLocationAddress = '上海市浦东新区中科路1号';

  String buildCalendar({
    required CourseTable table,
    required DateTime termBegin,
    String calendarName = '课表',
    List<CustomCourse> customCourses = const [],
  }) {
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//TechPie//Schedule Export//CN')
      ..writeln('CALSCALE:GREGORIAN')
      ..writeln('METHOD:PUBLISH')
      ..writeln('X-WR-CALNAME:${_escapeText(calendarName)}')
      ..writeln('X-WR-TIMEZONE:Asia/Shanghai');

    for (final event in _expandCalendarEvents(table, termBegin, customCourses)) {
      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('UID:${_buildUid(event)}');
      buffer.writeln(
        'DTSTAMP:${_formatUtcTimestamp(DateTime.now().toUtc())}',
      );
      buffer.writeln(
        'DTSTART;TZID=Asia/Shanghai:${_formatDateTimeForIcs(event.startDateTime)}',
      );
      buffer.writeln(
        'DTEND;TZID=Asia/Shanghai:${_formatDateTimeForIcs(event.endDateTime)}',
      );
      buffer.writeln('SUMMARY:${_escapeText(event.name)}');
      buffer.writeln('LOCATION-TYPE:SCHOOL');
      buffer.writeln('LOCATION:${_escapeText(event.location)}');
      final structuredLocation = event.structuredLocation;
      if (structuredLocation != null) {
        buffer.writeln(
          'GEO:${structuredLocation.latitude};${structuredLocation.longitude}',
        );
        buffer.writeln(
          'X-APPLE-STRUCTURED-LOCATION;VALUE=URI;X-ADDRESS="${_escapeAppleText(_structuredLocationAddress)}";X-APPLE-RADIUS=200;X-TITLE="${_escapeAppleText(structuredLocation.title)}":geo:${structuredLocation.latitude},${structuredLocation.longitude}',
        );
      }
      if (event.teachers.trim().isNotEmpty) {
        buffer.writeln('DESCRIPTION:${_escapeText(event.teachers)}');
      }
      buffer.writeln('SEQUENCE:0');
      buffer.writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  Future<SavedIcsFile> saveCalendar({
    required CourseTable table,
    required DateTime termBegin,
    required String fileName,
    required IcsSaveLocation location,
    String calendarName = 'Course Table',
    List<CustomCourse> customCourses = const [],
  }) async {
    final content = await compute(_buildCalendarInBackground, {
      'table': table.toJson(),
      'termBegin': termBegin.toIso8601String(),
      'calendarName': calendarName,
      'customCourses': customCourses.map((c) => c.toJson()).toList(),
    });
    return saveIcsFile(fileName, content, location: location);
  }

  Future<List<Map<String, Object?>>> buildCalendarEventPayloads({
    required CourseTable table,
    required DateTime termBegin,
    List<CustomCourse> customCourses = const [],
  }) {
    return compute(_buildCalendarEventPayloadsInBackground, {
      'table': table.toJson(),
      'termBegin': termBegin.toIso8601String(),
      'customCourses': customCourses.map((c) => c.toJson()).toList(),
    });
  }

  StructuredLocation? _findStructuredLocation(String classroom) {
    for (final candidate in _structuredLocations) {
      if (classroom.contains(candidate.keyword)) {
        return candidate;
      }
    }
    return null;
  }

  String _buildUid(_CalendarEventData event) {
    return '${Uri.encodeComponent(event.uidSeed)}@techpie';
  }

  Iterable<_CalendarEventData> _expandCalendarEvents(
    CourseTable table,
    DateTime termBegin,
    List<CustomCourse> customCourses,
  ) sync* {
    final mondayOfWeekOne = termBegin.subtract(
      Duration(days: termBegin.weekday - 1),
    );
    final periodsByIndex = {
      for (final period in table.periods) period.index: period.toPeriod(),
    };

    DateTime mondayOf(int week) => mondayOfWeekOne.add(Duration(days: (week - 1) * 7));

    for (final course in table.courses) {
      for (int week = 1; week < course.weeks.length; week++) {
        if (course.weeks[week] != '1') continue;

        final monday = mondayOf(week);
        for (final entry in course.times.entries) {
          final periods = [...entry.value]..sort();
          if (periods.isEmpty) continue;

          final startPeriodIndex = periods.first;
          final endPeriodIndex = periods.last;
          final startPeriod = periodsByIndex[startPeriodIndex];
          final endPeriod = periodsByIndex[endPeriodIndex];
          if (startPeriod == null || endPeriod == null) continue;

          final classDate = monday.add(Duration(days: entry.key - 1));
          final classroom = course.classroom.trim();
          final location = classroom.isEmpty ? '上海科技大学' : '$classroom 上海科技大学';
          yield _CalendarEventData(
            name: course.name,
            classroom: classroom,
            teachers: course.teachers,
            // Preserve the existing UID scheme for fetched courses.
            uidSeed: '${course.name}-$classroom-$week-${entry.key}'
                '-$startPeriodIndex-$endPeriodIndex',
            startDateTime: _combineDateAndTime(classDate, startPeriod.startTime),
            endDateTime: _combineDateAndTime(classDate, endPeriod.endTime),
            location: location,
            structuredLocation: _findStructuredLocation(classroom),
          );
        }
      }
    }

    for (final custom in customCourses) {
      final weeks = custom.isOneOff
          ? [teachingWeekOf(custom.date!, termBegin)].whereType<int>()
          : custom.weeks;
      for (final week in weeks) {
        for (final day in custom.effectiveWeekdays) {
          final classDate = mondayOf(week).add(Duration(days: day - 1));
          final times = _customEventTimes(custom, periodsByIndex);
          if (times == null) continue;

          final classroom = custom.location.trim();
          yield _CalendarEventData(
            name: custom.name,
            classroom: classroom,
            teachers: custom.teachers,
            uidSeed: 'custom-${custom.id}-${_formatDateForUid(classDate)}',
            startDateTime: _combineDateAndTime(classDate, times.$1),
            endDateTime: _combineDateAndTime(classDate, times.$2),
            location: classroom.isEmpty ? '上海科技大学' : '$classroom 上海科技大学',
            structuredLocation: _findStructuredLocation(classroom),
          );
        }
      }
    }
  }

  /// The session's own clock times, else the ones its periods carry.
  (String, String)? _customEventTimes(
    CustomCourse course,
    Map<int, Period> periodsByIndex,
  ) {
    return course.time.clockRange(periodsByIndex.values.toList());
  }

  String _formatDateTimeForIcs(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}'
        '${dateTime.month.toString().padLeft(2, '0')}'
        '${dateTime.day.toString().padLeft(2, '0')}'
        'T'
        '${dateTime.hour.toString().padLeft(2, '0')}'
        '${dateTime.minute.toString().padLeft(2, '0')}'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _formatUtcTimestamp(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}'
        'T'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}'
        '${date.second.toString().padLeft(2, '0')}Z';
  }

  String _escapeText(String value) {
    return value
        .replaceAll(r'', r'')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\n', r'\n');
  }

  String _escapeAppleText(String value) {
    return value.replaceAll(r'', r'').replaceAll('"', r'\"');
  }
}

String _formatDateForUid(DateTime date) => '${date.year.toString().padLeft(4, '0')}'
    '${date.month.toString().padLeft(2, '0')}'
    '${date.day.toString().padLeft(2, '0')}';

List<CustomCourse> _customCoursesFromPayload(Map<String, Object?> payload) =>
    ((payload['customCourses'] as List?) ?? const [])
        .map((e) => CustomCourse.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

String _buildCalendarInBackground(Map<String, Object?> payload) {
  final table = CourseTable.fromJson(
    (payload['table'] as Map<Object?, Object?>).cast<String, dynamic>(),
  );
  final termBegin = DateTime.parse(payload['termBegin'] as String);
  final calendarName = payload['calendarName'] as String? ?? '课表';

  return IcsExportService().buildCalendar(
    table: table,
    termBegin: termBegin,
    calendarName: calendarName,
    customCourses: _customCoursesFromPayload(payload),
  );
}

List<Map<String, Object?>> _buildCalendarEventPayloadsInBackground(
  Map<String, Object?> payload,
) {
  final table = CourseTable.fromJson(
    (payload['table'] as Map<Object?, Object?>).cast<String, dynamic>(),
  );
  final termBegin = DateTime.parse(payload['termBegin'] as String);
  final service = IcsExportService();
  final customCourses = _customCoursesFromPayload(payload);
  return service._expandCalendarEvents(table, termBegin, customCourses).map((event) {
    final payload = <String, Object?>{
      'title': event.name,
      'location': event.location,
      'notes': event.teachers.trim(),
      'startMillis': event.startDateTime.millisecondsSinceEpoch,
      'endMillis': event.endDateTime.millisecondsSinceEpoch,
    };
    final structuredLocation = event.structuredLocation;
    if (structuredLocation != null) {
      payload.addAll({
        'structuredLocationTitle': event.location,
        'structuredLocationAddress':
            '${structuredLocation.title} ${IcsExportService._structuredLocationAddress}',
        'structuredLocationLatitude': structuredLocation.latitude,
        'structuredLocationLongitude': structuredLocation.longitude,
      });
    }
    return payload;
  }).toList(growable: false);
}

DateTime _combineDateAndTime(DateTime date, String hhmm) {
  final parts = hhmm.split(':');
  final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return DateTime(date.year, date.month, date.day, hour, minute);
}
