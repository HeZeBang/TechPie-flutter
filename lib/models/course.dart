import 'package:flutter/material.dart';

sealed class CourseSource {
  const CourseSource();
}

final class EamsCourseSource extends CourseSource {
  const EamsCourseSource();
}

final class CustomCourseSource extends CourseSource {
  final String id;

  const CustomCourseSource(this.id);
}

final class ExamCourseSource extends CourseSource {
  final String id;

  const ExamCourseSource(this.id);
}

class Course {
  final String name;
  final String location;
  final int dayOfWeek; // 1=Mon, 7=Sun
  final CoursePlacement placement;
  final CourseColor color;
  final String? teachers;
  final String? weeksText;
  final DateTime? date;
  final bool isGhost; // non-current-week course shown transparently

  final CourseSource source;

  const Course({
    required this.name,
    required this.location,
    required this.dayOfWeek,
    required this.placement,
    this.color = CourseColor.primary,
    this.teachers,
    this.weeksText,
    this.date,
    this.isGhost = false,
    this.source = const EamsCourseSource(),
  });

  bool get isCustom => source is CustomCourseSource;
  String? get customId => switch (source) {
        CustomCourseSource(:final id) => id,
        _ => null,
      };

  bool occursOn(DateTime value) {
    final day = date;
    return day == null ||
        (day.year == value.year && day.month == value.month && day.day == value.day);
  }

  int get startPeriod => placement.startPeriod;
  int get endPeriod => placement.endPeriod;
  String get startTime => placement.startTime;
  String get endTime => placement.endTime;
  String get timeLabel => placement.label;
  double get gridStart => placement.gridStart;
  double get gridEnd => placement.gridEnd;
  bool get usesCustomTime => placement.usesCustomTime;

  static CourseColor colorFromIndex(int index) =>
      CourseColor.regularPalette[index % CourseColor.regularPalette.length];
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
  sky,
  coral,
  indigo,
  lime,
  plum,
  slate;

  /// Twelve regular course slots ordered for maximal hue separation around the
  /// OKLCH color wheel. [CourseColor.error] is reserved exclusively for exams
  /// so regular classes never collide with exam alerts.
  static const List<CourseColor> regularPalette = [
    CourseColor.primary,
    CourseColor.orange,
    CourseColor.secondary,
    CourseColor.tertiary,
    CourseColor.green,
    CourseColor.pink,
    CourseColor.sky,
    CourseColor.coral,
    CourseColor.indigo,
    CourseColor.lime,
    CourseColor.plum,
    CourseColor.slate,
  ];
}

final _trailingCourseCodePattern = RegExp(
  r'[(\（]\s*([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)?)\s*[)\）]\s*$',
);
final _validBaseCourseCodePattern = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z0-9_-]+$');
final _trailingSectionSuffixPattern = RegExp(r'-\d+[A-Za-z]?$');

/// Canonical grouping key so every session belonging to the same course shares
/// one color.
///
/// For EAMS courses with a trailing course code (e.g. `模拟电路(EE115A.02)` and
/// its recitation `模拟电路(EE115A.02D)`), strips the section suffix after `.`
/// so lecture + recitation + split room/week entries map to `code:EE115A`,
/// while independent lab courses with distinct codes (`EE115AL.01`) map to
/// `code:EE115AL`. Courses without a structured code (e.g. graduate or custom
/// courses) fall back to normalized course name.
String courseColorKey(String rawName) {
  final trimmed = rawName.trim();
  final match = _trailingCourseCodePattern.firstMatch(trimmed);
  if (match != null) {
    final fullCode = match.group(1)!;
    final dot = fullCode.indexOf('.');
    var base = dot > 0 ? fullCode.substring(0, dot) : fullCode;
    base = base.replaceFirst(_trailingSectionSuffixPattern, '');
    if (_validBaseCourseCodePattern.hasMatch(base)) {
      return 'code:${base.toUpperCase()}';
    }
  }
  final normalized = trimmed.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return 'name:$normalized';
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
  /// Curated 12+1 OKLCH perceptually uniform palette (Apple Calendar / Notion
  /// translucent aesthetic) calibrated for Light, Dark, and AMOLED canvases.
  /// Every (container, onContainer) pair clears WCAG AAA (>= 7.1:1 light,
  /// >= 9.8:1 dark) with uniform visual weight across hues.
  ({Color container, Color onContainer, Color accent}) _tokens(
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;
    return switch (this) {
      // Cobalt Blue (OKLCH h=252°)
      CourseColor.primary => isDark
          ? (
              container: const Color(0xFF102135),
              onContainer: const Color(0xFFA7D0FF),
              accent: const Color(0xFF5BA5F6),
            )
          : (
              container: const Color(0xFFE1EFFF),
              onContainer: const Color(0xFF004C8D),
              accent: const Color(0xFF217AD0),
            ),
      // Teal (OKLCH h=186°)
      CourseColor.secondary => isDark
          ? (
              container: const Color(0xFF042623),
              onContainer: const Color(0xFF88DFD4),
              accent: const Color(0xFF00BAAD),
            )
          : (
              container: const Color(0xFFD7F4F0),
              onContainer: const Color(0xFF005852),
              accent: const Color(0xFF008C82),
            ),
      // Violet (OKLCH h=296°)
      CourseColor.tertiary => isDark
          ? (
              container: const Color(0xFF221C33),
              onContainer: const Color(0xFFD1C1FF),
              accent: const Color(0xFFAA8EEE),
            )
          : (
              container: const Color(0xFFEEEAFF),
              onContainer: const Color(0xFF54378B),
              accent: const Color(0xFF8261C9),
            ),
      // Exam Danger Crimson (OKLCH h=24° — reserved for exams)
      CourseColor.error => isDark
          ? (
              container: const Color(0xFF351614),
              onContainer: const Color(0xFFFFB7B1),
              accent: const Color(0xFFF6736F),
            )
          : (
              container: const Color(0xFFFFE7E4),
              onContainer: const Color(0xFF8D121D),
              accent: const Color(0xFFCD3F41),
            ),
      // Emerald (OKLCH h=150°)
      CourseColor.green => isDark
          ? (
              container: const Color(0xFF102616),
              onContainer: const Color(0xFFA2DDAD),
              accent: const Color(0xFF5DB874),
            )
          : (
              container: const Color(0xFFDFF4E2),
              onContainer: const Color(0xFF005C26),
              accent: const Color(0xFF1D9046),
            ),
      // Amber (OKLCH h=74°)
      CourseColor.orange => isDark
          ? (
              container: const Color(0xFF2D1D05),
              onContainer: const Color(0xFFF2C385),
              accent: const Color(0xFFD59224),
            )
          : (
              container: const Color(0xFFFBEAD5),
              onContainer: const Color(0xFF684300),
              accent: const Color(0xFFA36C00),
            ),
      // Rose (OKLCH h=352°)
      CourseColor.pink => isDark
          ? (
              container: const Color(0xFF301822),
              onContainer: const Color(0xFFFBB4D2),
              accent: const Color(0xFFE07DAA),
            )
          : (
              container: const Color(0xFFFFE5EF),
              onContainer: const Color(0xFF7C2653),
              accent: const Color(0xFFB74E82),
            ),
      // Sky / Cerulean (OKLCH h=222°)
      CourseColor.sky => isDark
          ? (
              container: const Color(0xFF03252F),
              onContainer: const Color(0xFF87DAF6),
              accent: const Color(0xFF00B3DC),
            )
          : (
              container: const Color(0xFFD7F3FD),
              onContainer: const Color(0xFF00556A),
              accent: const Color(0xFF0086A6),
            ),
      // Apricot / Terracotta (OKLCH h=44°)
      CourseColor.coral => isDark
          ? (
              container: const Color(0xFF32190E),
              onContainer: const Color(0xFFFFBA9C),
              accent: const Color(0xFFE88254),
            )
          : (
              container: const Color(0xFFFFE8DE),
              onContainer: const Color(0xFF7F2E00),
              accent: const Color(0xFFC05319),
            ),
      // Indigo (OKLCH h=274°)
      CourseColor.indigo => isDark
          ? (
              container: const Color(0xFF1A1F35),
              onContainer: const Color(0xFFBCC9FF),
              accent: const Color(0xFF8799F8),
            )
          : (
              container: const Color(0xFFE7ECFF),
              onContainer: const Color(0xFF374194),
              accent: const Color(0xFF5E6ED3),
            ),
      // Moss / Olive (OKLCH h=122°)
      CourseColor.lime => isDark
          ? (
              container: const Color(0xFF1D230D),
              onContainer: const Color(0xFFC2D697),
              accent: const Color(0xFF94AE4E),
            )
          : (
              container: const Color(0xFFE9F1DA),
              onContainer: const Color(0xFF435400),
              accent: const Color(0xFF6B8500),
            ),
      // Orchid / Plum (OKLCH h=326°)
      CourseColor.plum => isDark
          ? (
              container: const Color(0xFF2B192B),
              onContainer: const Color(0xFFECB8EC),
              accent: const Color(0xFFCC83CE),
            )
          : (
              container: const Color(0xFFF9E6F9),
              onContainer: const Color(0xFF6E2D70),
              accent: const Color(0xFFA456A7),
            ),
      // Nordic Slate (OKLCH h=242°, low chroma)
      CourseColor.slate => isDark
          ? (
              container: const Color(0xFF1B2126),
              onContainer: const Color(0xFFBDCFDE),
              accent: const Color(0xFF8BA5BA),
            )
          : (
              container: const Color(0xFFE7EEF4),
              onContainer: const Color(0xFF384F60),
              accent: const Color(0xFF617D92),
            ),
    };
  }

  String get displayLabel => switch (this) {
        CourseColor.primary => '钴蓝',
        CourseColor.secondary => '青绿',
        CourseColor.tertiary => '紫罗兰',
        CourseColor.error => '警示红',
        CourseColor.green => '翠绿',
        CourseColor.orange => '琥珀',
        CourseColor.pink => '玫粉',
        CourseColor.sky => '天蓝',
        CourseColor.coral => '暖橘',
        CourseColor.indigo => '靛蓝',
        CourseColor.lime => '苔绿',
        CourseColor.plum => '梅紫',
        CourseColor.slate => '岩灰',
      };

  Color containerColor(ColorScheme scheme) => _tokens(scheme.brightness).container;

  Color onContainerColor(ColorScheme scheme) =>
      _tokens(scheme.brightness).onContainer;

  Color accentColor(Brightness brightness) => _tokens(brightness).accent;

  Color borderColor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return _tokens(brightness).accent.withValues(alpha: isDark ? 0.30 : 0.22);
  }
}
