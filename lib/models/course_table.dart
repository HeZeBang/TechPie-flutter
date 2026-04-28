import 'course.dart';

class CoursePeriod {
  final int index;
  final String timeRange;

  const CoursePeriod({required this.index, required this.timeRange});

  factory CoursePeriod.fromEntry(MapEntry<String, dynamic> entry) {
    return CoursePeriod(
      index: int.parse(entry.key),
      timeRange: entry.value as String,
    );
  }

  Map<String, dynamic> toJson() => {'index': index, 'timeRange': timeRange};

  factory CoursePeriod.fromJson(Map<String, dynamic> json) => CoursePeriod(
    index: json['index'] as int,
    timeRange: json['timeRange'] as String,
  );

  Period toPeriod() {
    final parts = timeRange.split('-');
    return Period(
      number: index,
      startTime: parts.isNotEmpty ? parts[0].trim() : '',
      endTime: parts.length > 1 ? parts[1].trim() : '',
    );
  }
}

class EamsCourse {
  final String name;
  final String classroom;
  final String teachers;
  final String
  weeks; // binary string: "01111111111111111000..." (index 1 = week 1)
  final Map<int, List<int>>
  times; // { weekday(1-7): [period_numbers(1-based)] }

  const EamsCourse({
    required this.name,
    required this.classroom,
    required this.teachers,
    required this.weeks,
    required this.times,
  });

  bool isActiveInWeek(int week) {
    // Binary string is 0-indexed where index 0 is unused/week0,
    // index 1 = week 1, index 2 = week 2, etc.
    return week >= 0 && week < weeks.length && weeks[week] == '1';
  }

  /// Returns sorted list of active week numbers (1-based).
  List<int> _activeWeeks() {
    final result = <int>[];
    // Start from index 1 (week 1)
    for (int i = 1; i < weeks.length; i++) {
      if (weeks[i] == '1') result.add(i);
    }
    return result;
  }

  String get weeksText {
    final weekNums = _activeWeeks();
    if (weekNums.isEmpty) return '';
    return _numsToRanges(weekNums);
  }

  static String _numsToRanges(List<int> nums) {
    if (nums.isEmpty) return '';
    final ranges = <String>[];
    int start = nums[0];
    int end = nums[0];
    for (int i = 1; i < nums.length; i++) {
      if (nums[i] == end + 1) {
        end = nums[i];
      } else {
        ranges.add(start == end ? '$start' : '$start-$end');
        start = nums[i];
        end = nums[i];
      }
    }
    ranges.add(start == end ? '$start' : '$start-$end');
    return '${ranges.join(', ')}周';
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'classroom': classroom,
    'teachers': teachers,
    'weeks': weeks,
    'times': times.map((k, v) => MapEntry(k.toString(), v.join(','))),
  };

  factory EamsCourse.fromJson(Map<String, dynamic> json) {
    final rawTimes = json['times'] as Map<String, dynamic>? ?? {};
    final times = <int, List<int>>{};
    for (final entry in rawTimes.entries) {
      final day = int.tryParse(entry.key);
      if (day == null) continue;
      final periods = (entry.value as String)
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .where((p) => p > 0)
          .toList();
      times[day] = periods;
    }
    return EamsCourse(
      name: json['name'] as String? ?? '',
      classroom: json['classroom'] as String? ?? '',
      teachers: json['teachers'] as String? ?? '',
      weeks: json['weeks'] as String? ?? '',
      times: times,
    );
  }
}

class CourseTable {
  final List<CoursePeriod> periods;
  final List<EamsCourse> courses;

  const CourseTable({required this.periods, required this.courses});

  Map<String, dynamic> toJson() => {
    'periods': periods.map((p) => p.toJson()).toList(),
    'courses': courses.map((c) => c.toJson()).toList(),
  };

  factory CourseTable.fromJson(Map<String, dynamic> json) => CourseTable(
    periods: (json['periods'] as List<dynamic>? ?? [])
        .map((p) => CoursePeriod.fromJson(p as Map<String, dynamic>))
        .toList(),
    courses: (json['courses'] as List<dynamic>? ?? [])
        .map((c) => EamsCourse.fromJson(c as Map<String, dynamic>))
        .toList(),
  );

  factory CourseTable.fromApiResponse(Map<String, dynamic> data) {
    final rawPeriods = data['periods'] as List<dynamic>? ?? [];
    final periods = <CoursePeriod>[];
    for (final item in rawPeriods) {
      final map = item as Map<String, dynamic>;
      for (final entry in map.entries) {
        periods.add(CoursePeriod.fromEntry(entry));
      }
    }
    periods.sort((a, b) => a.index.compareTo(b.index));

    final rawCourses = data['courses'] as List<dynamic>? ?? [];
    final courses = rawCourses
        .map((c) => EamsCourse.fromJson(c as Map<String, dynamic>))
        .toList();

    return CourseTable(periods: periods, courses: courses);
  }
}

class SemesterInfo {
  final Map<String, Map<String, String>> semesters;
  final String defaultSemester;
  final String tableId;

  const SemesterInfo({
    required this.semesters,
    required this.defaultSemester,
    required this.tableId,
  });

  Map<String, dynamic> toJson() => {
    'semesters': semesters,
    'defaultSemester': defaultSemester,
    'tableId': tableId,
  };

  factory SemesterInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['semesters'] as Map<String, dynamic>? ?? {};
    final semesters = <String, Map<String, String>>{};
    for (final entry in raw.entries) {
      final inner = entry.value as Map<String, dynamic>? ?? {};
      semesters[entry.key] = inner.map((k, v) => MapEntry(k, v.toString()));
    }
    return SemesterInfo(
      semesters: semesters,
      defaultSemester: json['defaultSemester'] as String? ?? '',
      tableId: json['tableId']?.toString() ?? '',
    );
  }

  String? findSemesterLabel(String semesterId) {
    for (final yearEntry in semesters.entries) {
      for (final semEntry in yearEntry.value.entries) {
        if (semEntry.value == semesterId) {
          return '${yearEntry.key} ${semEntry.key}学期';
        }
      }
    }
    return null;
  }

  List<MapEntry<String, String>> get allSemesters {
    final result = <MapEntry<String, String>>[];
    for (final yearEntry in semesters.entries) {
      for (final semEntry in yearEntry.value.entries) {
        result.add(
          MapEntry(semEntry.value, '${yearEntry.key} ${semEntry.key}学期'),
        );
      }
    }
    return result;
  }
}

/// Convert EamsCourse list to display Course list, grouping consecutive periods.
/// When [includeGhosts] is true, non-current-week courses are included with
/// [Course.isGhost] = true instead of being filtered out.
List<Course> eamsToDisplayCourses(
  List<EamsCourse> eamsCourses,
  int? weekFilter, {
  bool includeGhosts = false,
}) {
  final result = <Course>[];
  for (int i = 0; i < eamsCourses.length; i++) {
    final eams = eamsCourses[i];
    final active = weekFilter == null || eams.isActiveInWeek(weekFilter);
    if (!active && !includeGhosts) continue;

    final color = CourseColor.values[i % CourseColor.values.length];
    for (final entry in eams.times.entries) {
      final day = entry.key;
      final periods = entry.value..sort();
      if (periods.isEmpty) continue;

      // Group consecutive periods into blocks
      // API times values are already 1-based
      int start = periods[0];
      int end = periods[0];
      for (int j = 1; j < periods.length; j++) {
        if (periods[j] == end + 1) {
          end = periods[j];
        } else {
          result.add(
            Course(
              name: eams.name,
              location: eams.classroom,
              dayOfWeek: day,
              startPeriod: start,
              endPeriod: end,
              color: color,
              teachers: eams.teachers,
              weeksText: eams.weeksText,
              isGhost: !active,
            ),
          );
          start = periods[j];
          end = periods[j];
        }
      }
      result.add(
        Course(
          name: eams.name,
          location: eams.classroom,
          dayOfWeek: day,
          startPeriod: start,
          endPeriod: end,
          color: color,
          teachers: eams.teachers,
          weeksText: eams.weeksText,
          isGhost: !active,
        ),
      );
    }
  }
  return result;
}
