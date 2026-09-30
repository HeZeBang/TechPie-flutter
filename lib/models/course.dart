import 'package:flutter/material.dart';

class Course {
  final String name;
  final String location;
  final int dayOfWeek; // 1=Mon, 7=Sun
  final CoursePlacement placement;
  final CourseColor color;
  final String? teachers;
  final String? weeksText;
  final bool isGhost; // non-current-week course shown transparently

  /// Set only on a user-entered session, whose block in the grid is a tap into
  /// the editor for it.
  final String? customId;

  const Course({
    required this.name,
    required this.location,
    required this.dayOfWeek,
    required this.placement,
    this.color = CourseColor.primary,
    this.teachers,
    this.weeksText,
    this.isGhost = false,
    this.customId,
  });

  bool get isCustom => customId != null;
  int get startPeriod => placement.startPeriod;
  int get endPeriod => placement.endPeriod;
  String get startTime => placement.startTime;
  String get endTime => placement.endTime;
  String get timeLabel => placement.label;
  double get gridStart => placement.gridStart;
  double get gridEnd => placement.gridEnd;
  bool get usesCustomTime => placement.usesCustomTime;

  static CourseColor colorFromIndex(int index) =>
      CourseColor.values[index % CourseColor.values.length];
}

/// How a course specifies its time before it is placed on the timetable.
sealed class CourseTime {
  const CourseTime();

  (String, String)? clockRange(List<Period> periods);
  CoursePlacement? resolve(List<Period> periods);
}

class PeriodCourseTime extends CourseTime {
  final int startPeriod;
  final int endPeriod;

  const PeriodCourseTime({
    required this.startPeriod,
    required this.endPeriod,
  });

  @override
  (String, String)? clockRange(List<Period> periods) {
    Period? start;
    Period? end;
    for (final period in periods) {
      if (period.number == startPeriod) start = period;
      if (period.number == endPeriod) end = period;
    }
    if (start == null || end == null || endPeriod < startPeriod) return null;
    return (start.startTime, end.endTime);
  }

  @override
  CoursePlacement? resolve(List<Period> periods) {
    final clock = clockRange(periods);
    if (clock == null) return null;
    final startIndex = periods.indexWhere((period) => period.number == startPeriod);
    final endIndex = periods.indexWhere((period) => period.number == endPeriod);
    if (startIndex < 0 || endIndex < startIndex) return null;
    return CoursePlacement(
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      gridStart: startIndex.toDouble(),
      gridEnd: (endIndex + 1).toDouble(),
      usesCustomTime: false,
      startTime: clock.$1,
      endTime: clock.$2,
      label: '${clock.$1} – ${clock.$2}  '
          '(第$startPeriod-$endPeriod节)',
    );
  }
}

class ClockCourseTime extends CourseTime {
  final String startTime;
  final String endTime;

  const ClockCourseTime({required this.startTime, required this.endTime});

  bool get isValid {
    final start = parseClockMinutes(startTime);
    final end = parseClockMinutes(endTime);
    return start != null && end != null && end > start;
  }

  @override
  (String, String)? clockRange(List<Period> periods) => isValid ? (startTime, endTime) : null;

  @override
  CoursePlacement? resolve(List<Period> periods) {
    final startMinutes = parseClockMinutes(startTime);
    final endMinutes = parseClockMinutes(endTime);
    if (startMinutes == null ||
        endMinutes == null ||
        endMinutes <= startMinutes ||
        periods.isEmpty) {
      return null;
    }

    final gridStart = _gridPositionForMinutes(periods, startMinutes, isEnd: false);
    var gridEnd = _gridPositionForMinutes(periods, endMinutes, isEnd: true);
    if (gridEnd < gridStart) gridEnd = gridStart;
    final startIndex = gridStart.floor().clamp(0, periods.length - 1);
    final endIndex = (gridEnd.ceil() - 1).clamp(startIndex, periods.length - 1);
    return CoursePlacement(
      startPeriod: periods[startIndex].number,
      endPeriod: periods[endIndex].number,
      gridStart: gridStart,
      gridEnd: gridEnd,
      usesCustomTime: true,
      startTime: startTime,
      endTime: endTime,
      label: '$startTime – $endTime',
    );
  }
}

/// Fully resolved information consumed by every schedule renderer.
class CoursePlacement {
  final int startPeriod;
  final int endPeriod;
  final double gridStart;
  final double gridEnd;
  final bool usesCustomTime;
  final String startTime;
  final String endTime;
  final String label;

  const CoursePlacement({
    required this.startPeriod,
    required this.endPeriod,
    required this.gridStart,
    required this.gridEnd,
    required this.usesCustomTime,
    required this.startTime,
    required this.endTime,
    required this.label,
  });
}

double _gridPositionForMinutes(
  List<Period> periods,
  int minutes, {
  required bool isEnd,
}) {
  for (var i = 0; i < periods.length; i++) {
    final start = parseClockMinutes(periods[i].startTime);
    final end = parseClockMinutes(periods[i].endTime);
    if (start == null || end == null || end <= start) continue;
    if (minutes < start) return i == 0 && isEnd ? 1 : i.toDouble();
    if (minutes <= end) {
      return i + (minutes - start) / (end - start);
    }
  }
  return isEnd ? periods.length.toDouble() : (periods.length - 1).toDouble();
}

int? parseClockMinutes(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

enum CourseColor {
  primary,
  secondary,
  tertiary,
  error,
  green,
  orange,
  pink,
}

class Period {
  final int number;
  final String startTime;
  final String endTime;

  const Period({
    required this.number,
    required this.startTime,
    required this.endTime,
  });

  String get label => '$startTime\n$endTime';
}

const List<Period> defaultPeriods = [
  Period(number: 1, startTime: '08:15', endTime: '09:00'),
  Period(number: 2, startTime: '09:10', endTime: '09:55'),
  Period(number: 3, startTime: '10:15', endTime: '11:00'),
  Period(number: 4, startTime: '11:10', endTime: '11:55'),
  Period(number: 5, startTime: '13:00', endTime: '13:45'),
  Period(number: 6, startTime: '13:55', endTime: '14:40'),
  Period(number: 7, startTime: '15:00', endTime: '15:45'),
  Period(number: 8, startTime: '15:55', endTime: '16:40'),
  Period(number: 9, startTime: '16:50', endTime: '17:35'),
  Period(number: 10, startTime: '18:00', endTime: '18:45'),
  Period(number: 11, startTime: '18:55', endTime: '19:40'),
  Period(number: 12, startTime: '19:50', endTime: '20:35'),
  Period(number: 13, startTime: '20:45', endTime: '21:30'),
];

/// Ascending week numbers as ranges: `[1,2,3,4,6]` → `1-4, 6周`.
String formatWeekRanges(List<int> weeks) {
  if (weeks.isEmpty) return '';
  final ranges = <String>[];
  int start = weeks[0];
  int end = weeks[0];
  for (int i = 1; i < weeks.length; i++) {
    if (weeks[i] == end + 1) {
      end = weeks[i];
    } else {
      ranges.add(start == end ? '$start' : '$start-$end');
      start = weeks[i];
      end = weeks[i];
    }
  }
  ranges.add(start == end ? '$start' : '$start-$end');
  return '${ranges.join(', ')}周';
}

extension CourseColorScheme on CourseColor {
  /// Seed color for generating a proper tonal [ColorScheme] per course color.
  /// Using [ColorScheme.fromSeed] ensures every container/onContainer pair
  /// meets MD3's contrast requirements (WCAG 4.5:1 for normal text).
  Color get _seed => switch (this) {
        CourseColor.primary => Colors.deepPurple,
        CourseColor.secondary => Colors.blueGrey,
        CourseColor.tertiary => Colors.teal,
        CourseColor.error => Colors.red,
        CourseColor.green => Colors.green,
        CourseColor.orange => Colors.deepOrange,
        CourseColor.pink => Colors.pink,
      };

  ColorScheme _scheme(Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

  Color containerColor(ColorScheme scheme) => _scheme(scheme.brightness).primaryContainer;

  Color onContainerColor(ColorScheme scheme) => _scheme(scheme.brightness).onPrimaryContainer;
}
