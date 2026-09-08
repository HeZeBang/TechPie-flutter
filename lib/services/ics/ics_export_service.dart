import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/course_table.dart';
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
  final EamsCourse course;
  final int week;
  final int day;
  final int startPeriodIndex;
  final int endPeriodIndex;
  final DateTime classDate;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final String location;
  final StructuredLocation? structuredLocation;

  const _CalendarEventData({
    required this.course,
    required this.week,
    required this.day,
    required this.startPeriodIndex,
    required this.endPeriodIndex,
    required this.classDate,
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
  }) {
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//TechPie//Schedule Export//CN')
      ..writeln('CALSCALE:GREGORIAN')
      ..writeln('METHOD:PUBLISH')
      ..writeln('X-WR-CALNAME:${_escapeText(calendarName)}')
      ..writeln('X-WR-TIMEZONE:Asia/Shanghai');

    for (final event in _expandCalendarEvents(table, termBegin)) {
      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln(
        'UID:${_buildUid(event.course, event.classDate, event.startPeriodIndex)}',
      );
      buffer.writeln(
        'DTSTAMP:${_formatUtcTimestamp(DateTime.now().toUtc())}',
      );
      buffer.writeln(
        'DTSTART;TZID=Asia/Shanghai:${_formatDateTimeForIcs(event.startDateTime)}',
      );
      buffer.writeln(
        'DTEND;TZID=Asia/Shanghai:${_formatDateTimeForIcs(event.endDateTime)}',
      );
      buffer.writeln('SUMMARY:${_escapeText(event.course.name)}');
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
      if (event.course.teachers.trim().isNotEmpty) {
        buffer.writeln('DESCRIPTION:${_escapeText(event.course.teachers)}');
      }
      buffer.writeln('SEQUENCE:0');
      buffer.writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');
    // RFC 5545 limits content lines to 75 octets, including continuation space.
    return '${buffer.toString().trimRight().split('\n').map((line) {
      final folded = StringBuffer();
      var bytes = 0;
      for (final rune in line.runes) {
        final character = String.fromCharCode(rune);
        final length = utf8.encode(character).length;
        if (bytes + length > 75) {
          folded.write('\r\n ');
          bytes = 1;
        }
        folded.write(character);
        bytes += length;
      }
      return folded.toString();
    }).join('\r\n')}\r\n';
  }

  Future<SavedIcsFile> saveCalendar({
    required CourseTable table,
    required DateTime termBegin,
    required String fileName,
    required IcsSaveLocation location,
    String calendarName = 'Course Table',
  }) async {
    final content = await compute(_buildCalendarInBackground, {
      'table': table.toJson(),
      'termBegin': termBegin.toIso8601String(),
      'calendarName': calendarName,
    });
    return saveIcsFile(fileName, content, location: location);
  }

  Future<List<Map<String, Object?>>> buildCalendarEventPayloads({
    required CourseTable table,
    required DateTime termBegin,
  }) {
    return compute(_buildCalendarEventPayloadsInBackground, {
      'table': table.toJson(),
      'termBegin': termBegin.toIso8601String(),
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

  String _buildUid(
    EamsCourse course,
    DateTime date,
    int startPeriod,
  ) {
    final seed =
        '${course.name}-${date.year}-${date.month}-${date.day}-$startPeriod';
    return '${Uri.encodeComponent(seed)}@techpie';
  }

  Iterable<_CalendarEventData> _expandCalendarEvents(
    CourseTable table,
    DateTime termBegin,
  ) sync* {
    final mondayOfWeekOne = termBegin.subtract(
      Duration(days: termBegin.weekday - 1),
    );
    final periodsByIndex = {
      for (final period in table.periods) period.index: period.toPeriod(),
    };

    for (final course in table.courses) {
      for (int week = 1; week < course.weeks.length; week++) {
        if (course.weeks[week] != '1') continue;

        final monday = mondayOfWeekOne.add(Duration(days: (week - 1) * 7));
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
            course: course,
            week: week,
            day: entry.key,
            startPeriodIndex: startPeriodIndex,
            endPeriodIndex: endPeriodIndex,
            classDate: classDate,
            startDateTime:
                _combineDateAndTime(classDate, startPeriod.startTime),
            endDateTime: _combineDateAndTime(classDate, endPeriod.endTime),
            location: location,
            structuredLocation: _findStructuredLocation(classroom),
          );
        }
      }
    }
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
        .replaceAll('\\', '\\\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\n', r'\n');
  }

  String _escapeAppleText(String value) {
    return _escapeText(value).replaceAll('"', r'\"');
  }
}

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
  return service._expandCalendarEvents(table, termBegin).map((event) {
    final payload = <String, Object?>{
      'title': event.course.name,
      'location': event.location,
      'notes': event.course.teachers.trim(),
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
