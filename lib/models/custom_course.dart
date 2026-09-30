import 'course.dart';

/// A tutorial / recitation session the user entered by hand, stored locally
/// per semester next to the fetched course table.
///
/// When it runs is [weeks] for a recurring session or [date] for a one-off.
class CustomCourse {
  final String id;

  /// The semester this was entered for, so editing can move it to another.
  final String semesterId;

  final String name;
  final String location;
  final String teachers;

  /// Grid columns, 1=Mon … 7=Sun. Empty for a one-off, which uses [date].
  final List<int> weekdays;

  final CourseTime time;

  /// Teaching weeks, ascending. Empty for a one-off.
  final List<int> weeks;

  /// The single day a one-off falls on; null when [weeks] says when it runs.
  final DateTime? date;

  final CourseColor color;

  const CustomCourse({
    required this.id,
    this.semesterId = '',
    required this.name,
    this.location = '',
    this.teachers = '',
    this.weekdays = const [],
    required this.time,
    this.weeks = const [],
    this.date,
    this.color = CourseColor.primary,
  });

  bool get isOneOff => date != null;
  bool get usesPeriods => time is PeriodCourseTime;
  bool get usesCustomTime => time is ClockCourseTime;

  int? get startPeriod => switch (time) {
        PeriodCourseTime(:final startPeriod) => startPeriod,
        ClockCourseTime() => null,
      };
  int? get endPeriod => switch (time) {
        PeriodCourseTime(:final endPeriod) => endPeriod,
        ClockCourseTime() => null,
      };
  String? get startTime => switch (time) {
        ClockCourseTime(:final startTime) => startTime,
        PeriodCourseTime() => null,
      };
  String? get endTime => switch (time) {
        ClockCourseTime(:final endTime) => endTime,
        PeriodCourseTime() => null,
      };

  /// Whether this session belongs in [week]'s grid. A one-off resolves through
  /// its own date rather than a stored week number, so it does not move when
  /// the term calendar is re-fetched.
  bool isActiveInWeek(int week, DateTime? termBegin) {
    final day = date;
    if (day == null) return weeks.contains(week);
    return teachingWeekOf(day, termBegin) == week;
  }

  /// The columns to draw in: the picked weekdays, or a one-off's own date.
  List<int> get effectiveWeekdays {
    final day = date;
    if (day != null) return [day.weekday];
    return [...weekdays]..sort();
  }

  /// Shown as 周数 in the detail sheet: the week ranges, or the one-off's date.
  String get weeksLabel => date != null ? _formatDate(date!) : formatWeekRanges(weeks);

  /// One [Course] per weekday, each carrying this session's id so a tap on any
  /// of them reaches back here.
  List<Course> toCourses({
    bool isGhost = false,
    List<Period> periods = defaultPeriods,
  }) {
    final placement = time.resolve(periods);
    if (placement == null) return const [];
    return [
      for (final weekday in effectiveWeekdays)
        Course(
          name: name,
          location: location,
          dayOfWeek: weekday,
          placement: placement,
          color: color,
          teachers: teachers.isEmpty ? null : teachers,
          weeksText: weeksLabel,
          isGhost: isGhost,
          customId: id,
        ),
    ];
  }

  CustomCourse copyWith({String? semesterId}) => CustomCourse(
        id: id,
        semesterId: semesterId ?? this.semesterId,
        name: name,
        location: location,
        teachers: teachers,
        weekdays: weekdays,
        time: time,
        weeks: weeks,
        date: date,
        color: color,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (semesterId.isNotEmpty) 'semesterId': semesterId,
        'name': name,
        'location': location,
        'teachers': teachers,
        'weekdays': weekdays,
        if (time case PeriodCourseTime(:final startPeriod, :final endPeriod)) ...{
          'startPeriod': startPeriod,
          'endPeriod': endPeriod,
        },
        if (time case ClockCourseTime(:final startTime, :final endTime)) ...{
          'startTime': startTime,
          'endTime': endTime,
        },
        'weeks': weeks,
        if (date != null) 'date': date!.toIso8601String(),
        'color': color.name,
      };

  factory CustomCourse.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    if (id == null || id.trim().isEmpty || name == null || name.trim().isEmpty) {
      throw const FormatException('Custom course is missing its identity');
    }

    final rawDate = json['date'] as String?;
    final date = rawDate == null ? null : DateTime.tryParse(rawDate);
    if (rawDate != null && date == null) {
      throw const FormatException('Custom course has an invalid date');
    }
    final weeks = _positiveInts(json['weeks']);
    // A record written before the column became a list holds a single day.
    final weekdays = {
      ..._positiveInts(json['weekdays']),
      if (json['dayOfWeek'] is int) json['dayOfWeek'] as int,
    }..removeWhere((day) => day > 7);
    final startTime = json['startTime'] as String?;
    final endTime = json['endTime'] as String?;
    final hasAnyClockValue = startTime != null || endTime != null;
    final hasClockRange = startTime != null &&
        endTime != null &&
        ClockCourseTime(startTime: startTime, endTime: endTime).isValid;
    final startPeriod = json['startPeriod'] as int?;
    final endPeriod = json['endPeriod'] as int?;
    final hasPeriodRange =
        startPeriod != null && endPeriod != null && startPeriod > 0 && endPeriod >= startPeriod;
    if ((hasAnyClockValue && !hasClockRange) || (!hasClockRange && !hasPeriodRange)) {
      throw const FormatException('Custom course has no valid time range');
    }

    return CustomCourse(
      id: id,
      semesterId: json['semesterId'] as String? ?? '',
      name: name,
      location: json['location'] as String? ?? '',
      teachers: json['teachers'] as String? ?? '',
      weekdays: weekdays.toList()..sort(),
      // Clock time wins when reading legacy records that stored both modes.
      time: hasClockRange
          ? ClockCourseTime(startTime: startTime, endTime: endTime)
          : PeriodCourseTime(
              startPeriod: startPeriod!,
              endPeriod: endPeriod!,
            ),
      // The date wins; weeks left beside one are stale and would draw it twice.
      weeks: date == null ? weeks : const [],
      date: date,
      color: CourseColor.values.firstWhere(
        (value) => value.name == json['color'],
        orElse: () => CourseColor.primary,
      ),
    );
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}

List<int> _positiveInts(Object? raw) =>
    ((raw as List?) ?? const []).whereType<int>().where((value) => value > 0).toList()..sort();

/// The teaching week [date] falls in, 1-based; null before the term begins,
/// which keeps a one-off outside the term out of every week's grid.
int? teachingWeekOf(DateTime date, DateTime? termBegin) {
  if (termBegin == null) return null;
  final begin = DateTime(termBegin.year, termBegin.month, termBegin.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = day.difference(begin).inDays;
  if (days < 0) return null;
  return (days ~/ 7) + 1;
}

String _formatDate(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}'
    '-${date.day.toString().padLeft(2, '0')}';

/// Overlay the user's own sessions onto a week's display list. A null [week]
/// means no filtering, matching [eamsToDisplayCourses].
List<Course> withCustomCourses(
  List<Course> courses,
  List<CustomCourse> custom,
  int? week,
  DateTime? termBegin, {
  bool includeGhosts = false,
  List<Period> periods = defaultPeriods,
}) {
  final result = [...courses];
  for (final session in custom) {
    final active = week == null || session.isActiveInWeek(week, termBegin);
    if (!active && !includeGhosts) continue;
    result.addAll(session.toCourses(isGhost: !active, periods: periods));
  }
  return result;
}
