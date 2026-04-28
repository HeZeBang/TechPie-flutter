import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/course_table.dart';
import '../services/schedule_service.dart';
import '../services/service_provider.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late ScheduleService _schedule;
  List<Course> _courses = [];
  List<Period> _periods = defaultPeriods.toList();
  int _currentWeek = 1;
  bool _initialized = false;

  // Settings
  bool _showSaturday = true;
  bool _showSunday = true;
  bool _showGhostCourses = false;

  // Animation: track slide direction for week transitions
  // 1 = forward (next week), -1 = backward (previous week), 0 = no slide
  int _slideDirection = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final sp = ServiceProvider.of(context);
      _schedule = sp.scheduleService;
      _schedule.addListener(_onScheduleChanged);
      _loadData();
    }
  }

  @override
  void dispose() {
    _schedule.removeListener(_onScheduleChanged);
    super.dispose();
  }

  void _onScheduleChanged() {
    _rebuildCourses();
  }

  void _loadData() {
    _rebuildCourses();
  }

  Future<void> _refresh() async {
    final auth = ServiceProvider.of(context).authService;
    if (auth.isLoggedIn) {
      await _schedule.fetchAll();
    }
  }

  void _rebuildCourses() {
    if (!mounted) return;
    setState(() {
      _currentWeek = _schedule.currentWeek();
      final table = _schedule.courseTable;
      if (table != null) {
        if (table.periods.isNotEmpty) {
          _periods = table.periods.map((p) => p.toPeriod()).toList();
        }
        _courses = eamsToDisplayCourses(
          table.courses,
          _currentWeek,
          includeGhosts: _showGhostCourses,
        );
      } else {
        _courses = [];
      }
    });
  }

  void _previousWeek() {
    final old = _currentWeek;
    setState(() {
      _currentWeek = (_currentWeek - 1).clamp(1, 25);
      _slideDirection = _currentWeek < old ? -1 : 0;
      _filterCoursesForWeek();
    });
  }

  void _nextWeek() {
    final old = _currentWeek;
    setState(() {
      _currentWeek = (_currentWeek + 1).clamp(1, 25);
      _slideDirection = _currentWeek > old ? 1 : 0;
      _filterCoursesForWeek();
    });
  }

  void _goToCurrentWeek() {
    final old = _currentWeek;
    setState(() {
      _currentWeek = _schedule.currentWeek();
      _slideDirection = _currentWeek > old ? 1 : (_currentWeek < old ? -1 : 0);
      _filterCoursesForWeek();
    });
  }

  void _filterCoursesForWeek() {
    final table = _schedule.courseTable;
    if (table != null) {
      _courses = eamsToDisplayCourses(
        table.courses,
        _currentWeek,
        includeGhosts: _showGhostCourses,
      );
    }
  }

  void _showSemesterPicker() {
    final info = _schedule.semesterInfo;
    if (info == null) return;
    final allSemesters = info.allSemesters;
    if (allSemesters.isEmpty) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return RadioGroup<String>(
          groupValue: _schedule.selectedSemesterId,
          onChanged: (value) {
            Navigator.pop(context);
            if (value != null) _schedule.selectSemester(value);
          },
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  '选择学期',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final entry in allSemesters)
                ListTile(
                  leading: Radio<String>(value: entry.key),
                  title: Text(entry.value),
                  onTap: () {
                    Navigator.pop(context);
                    _schedule.selectSemester(entry.key);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showWeekPicker() {
    final computedWeek = _schedule.currentWeek();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final sheetTheme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '第$_currentWeek周',
                        style: sheetTheme.textTheme.headlineSmall,
                      ),
                      FilledButton.tonal(
                        onPressed: () {
                          final old = _currentWeek;
                          setState(() {
                            _currentWeek = computedWeek;
                            _slideDirection = computedWeek > old
                                ? 1
                                : (computedWeek < old ? -1 : 0);
                            _filterCoursesForWeek();
                          });
                          setModalState(() {});
                        },
                        child: const Text('回到本周'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: _currentWeek.toDouble(),
                    min: 1,
                    max: 25,
                    divisions: 24,
                    label: '第$_currentWeek周',
                    onChanged: (value) {
                      final week = value.round();
                      final old = _currentWeek;
                      setState(() {
                        _currentWeek = week;
                        _slideDirection = week > old
                            ? 1
                            : (week < old ? -1 : 0);
                        _filterCoursesForWeek();
                      });
                      setModalState(() {});
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '1',
                          style: sheetTheme.textTheme.labelSmall?.copyWith(
                            color: sheetTheme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '25',
                          style: sheetTheme.textTheme.labelSmall?.copyWith(
                            color: sheetTheme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<int> get _visibleDayIndices {
    final days = <int>[1, 2, 3, 4, 5];
    if (_showSaturday) days.add(6);
    if (_showSunday) days.add(7);
    return days;
  }

  DateTime get _weekStart {
    final termBegin = _schedule.termBegin;
    if (termBegin != null) {
      final weekStartDate = termBegin.add(
        Duration(days: (_currentWeek - 1) * 7),
      );
      return weekStartDate.subtract(Duration(days: weekStartDate.weekday - 1));
    }
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  String get _semesterLabel {
    final info = _schedule.semesterInfo;
    final id = _schedule.selectedSemesterId;
    if (info != null && id != null) {
      return info.findSemesterLabel(id) ?? '';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final auth = ServiceProvider.of(context).authService;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showWeekPicker,
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: Offset(
                                  0,
                                  _slideDirection >= 0 ? 0.3 : -0.3,
                                ),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          '第 $_currentWeek 周',
                          key: ValueKey<int>(_currentWeek),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  if (_semesterLabel.isNotEmpty)
                    Text(
                      _semesterLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.unfold_more,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'This week',
            onPressed: _goToCurrentWeek,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous week',
            onPressed: _previousWeek,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next week',
            onPressed: _nextWeek,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenuSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'semester',
                child: ListTile(
                  leading: Icon(Icons.swap_horiz),
                  title: Text('切换学期'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: 'saturday',
                checked: _showSaturday,
                child: const Text('显示周六'),
              ),
              CheckedPopupMenuItem(
                value: 'sunday',
                checked: _showSunday,
                child: const Text('显示周日'),
              ),
              CheckedPopupMenuItem(
                value: 'ghost',
                checked: _showGhostCourses,
                child: const Text('显示非本周课程'),
              ),
            ],
          ),
        ],
      ),
      body: !auth.isLoggedIn
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.login,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '登录以查看课表',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : _schedule.loading && _courses.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _schedule.error != null && _courses.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '加载失败',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _refresh,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: Column(
                children: [
                  _DayHeader(
                    weekStart: _weekStart,
                    today: today,
                    visibleDays: _visibleDayIndices,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child:
                          _courses
                              .where(
                                (c) => _visibleDayIndices.contains(c.dayOfWeek),
                              )
                              .isEmpty
                          ? ListView(
                              key: ValueKey<String>('empty-$_currentWeek'),
                              children: [
                                SizedBox(
                                  height: 300,
                                  child: Center(
                                    child: Text(
                                      '本周没有课程',
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _TimetableGrid(
                              key: ValueKey<int>(_currentWeek),
                              courses: _courses,
                              periods: _periods,
                              weekStart: _weekStart,
                              today: today,
                              visibleDays: _visibleDayIndices,
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'semester':
        _showSemesterPicker();
      case 'saturday':
        setState(() => _showSaturday = !_showSaturday);
      case 'sunday':
        setState(() => _showSunday = !_showSunday);
      case 'ghost':
        setState(() {
          _showGhostCourses = !_showGhostCourses;
          _filterCoursesForWeek();
        });
    }
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime weekStart;
  final DateTime today;
  final List<int> visibleDays;

  const _DayHeader({
    required this.weekStart,
    required this.today,
    required this.visibleDays,
  });

  static const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 68,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  '${weekStart.month}\n月',
                  key: ValueKey<String>('${weekStart.year}-${weekStart.month}'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          for (final day in visibleDays)
            Expanded(
              child: _DayHeaderCell(
                dayLabel: _dayLabels[day - 1],
                date: weekStart.add(Duration(days: day - 1)),
                isToday: _isSameDay(
                  weekStart.add(Duration(days: day - 1)),
                  today,
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayHeaderCell extends StatelessWidget {
  final String dayLabel;
  final DateTime date;
  final bool isToday;

  const _DayHeaderCell({
    required this.dayLabel,
    required this.date,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          dayLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isToday
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Container(
            key: ValueKey<String>('${date.year}-${date.month}-${date.day}'),
            width: 28,
            height: 28,
            decoration: isToday
                ? BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  )
                : null,
            alignment: Alignment.center,
            child: Text(
              '${date.day}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: isToday
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimetableGrid extends StatelessWidget {
  final List<Course> courses;
  final List<Period> periods;
  final DateTime weekStart;
  final DateTime today;
  final List<int> visibleDays;

  const _TimetableGrid({
    super.key,
    required this.courses,
    required this.periods,
    required this.weekStart,
    required this.today,
    required this.visibleDays,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 48,
              child: Column(
                children: [
                  for (final period in periods) _PeriodLabel(period: period),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            for (int i = 0; i < visibleDays.length; i++)
              Expanded(
                child: _DayColumn(
                  dayOfWeek: visibleDays[i],
                  courses: courses
                      .where((c) => c.dayOfWeek == visibleDays[i])
                      .toList(),
                  periods: periods,
                  isToday: _isSameDay(
                    weekStart.add(Duration(days: visibleDays[i] - 1)),
                    today,
                  ),
                  isLastColumn: i == visibleDays.length - 1,
                  theme: theme,
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _PeriodLabel extends StatelessWidget {
  final Period period;

  const _PeriodLabel({required this.period});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _kPeriodHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${period.number}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            period.startTime,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
          Text(
            period.endTime,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

const double _kPeriodHeight = 100.0;

class _DayColumn extends StatelessWidget {
  final int dayOfWeek;
  final List<Course> courses;
  final List<Period> periods;
  final bool isToday;
  final bool isLastColumn;
  final ThemeData theme;

  const _DayColumn({
    required this.dayOfWeek,
    required this.courses,
    required this.periods,
    required this.isToday,
    required this.isLastColumn,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Sort: ghost courses first (behind), then active courses on top
    final sorted = [...courses]
      ..sort((a, b) {
        if (a.isGhost != b.isGhost) return a.isGhost ? -1 : 1;
        return 0;
      });

    return Stack(
      children: [
        Column(
          children: [
            for (int i = 0; i < periods.length; i++)
              Container(
                height: _kPeriodHeight,
                decoration: BoxDecoration(
                  color: isToday
                      ? theme.colorScheme.primaryContainer.withAlpha(25)
                      : null,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withAlpha(80),
                      width: 0.5,
                    ),
                    right: isLastColumn
                        ? BorderSide.none
                        : BorderSide(
                            color: theme.colorScheme.outlineVariant.withAlpha(
                              80,
                            ),
                            width: 0.5,
                          ),
                  ),
                ),
              ),
          ],
        ),
        for (final course in sorted)
          Positioned(
            top: (course.startPeriod - 1) * _kPeriodHeight + 2,
            left: 2,
            right: 2,
            height:
                (course.endPeriod - course.startPeriod + 1) * _kPeriodHeight -
                4,
            child: _CourseBlock(course: course, periods: periods),
          ),
      ],
    );
  }
}

class _CourseBlock extends StatelessWidget {
  final Course course;
  final List<Period> periods;

  const _CourseBlock({required this.course, required this.periods});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final containerColor = course.color.containerColor(colorScheme);
    final textColor = course.color.onContainerColor(colorScheme);

    return Opacity(
      opacity: course.isGhost ? 0.3 : 1.0,
      child: Material(
        color: containerColor,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showCourseDetail(context),
          borderRadius: BorderRadius.circular(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxH = constraints.maxHeight - 8; // account for padding
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Course name: up to 70% of block height
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxH * 0.7),
                      child: Text(
                        course.name,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: (maxH * 0.7 / 14.4).floor().clamp(1, 20),
                      ),
                    ),
                    if (course.teachers != null &&
                        course.teachers!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        course.teachers!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: textColor,
                          fontSize: 12,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (course.location.isNotEmpty) ...[
                      const Spacer(),
                      Text(
                        course.location,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: textColor,
                          fontSize: 10,
                          height: 1.2,
                        ),
                        maxLines: (maxH * 0.2 / 12).floor().clamp(1, 5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showCourseDetail(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(course.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              if (course.location.isNotEmpty)
                _DetailRow(
                  icon: Icons.location_on_outlined,
                  text: course.location,
                  color: colorScheme.onSurfaceVariant,
                ),
              _DetailRow(
                icon: Icons.schedule_outlined,
                text: _timeRange(),
                color: colorScheme.onSurfaceVariant,
              ),
              _DetailRow(
                icon: Icons.calendar_today_outlined,
                text: _dayName(),
                color: colorScheme.onSurfaceVariant,
              ),
              if (course.teachers != null && course.teachers!.isNotEmpty)
                _DetailRow(
                  icon: Icons.person_outlined,
                  text: course.teachers!,
                  color: colorScheme.onSurfaceVariant,
                ),
              if (course.weeksText != null && course.weeksText!.isNotEmpty)
                _DetailRow(
                  icon: Icons.date_range_outlined,
                  text: course.weeksText!,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        );
      },
    );
  }

  String _timeRange() {
    if (course.startPeriod - 1 < periods.length &&
        course.endPeriod - 1 < periods.length) {
      final start = periods[course.startPeriod - 1];
      final end = periods[course.endPeriod - 1];
      return '${start.startTime} – ${end.endTime}  (第${course.startPeriod}-${course.endPeriod}节)';
    }
    return '第${course.startPeriod}-${course.endPeriod}节';
  }

  String _dayName() {
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (course.dayOfWeek >= 1 && course.dayOfWeek <= 7) {
      return days[course.dayOfWeek - 1];
    }
    return '';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _DetailRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
