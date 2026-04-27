import 'dart:async';

import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/course_table.dart';
import '../services/schedule_service.dart';
import '../services/service_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late ScheduleService _schedule;
  List<Course> _todayCourses = [];
  List<Period> _periods = defaultPeriods.toList();
  bool _initialized = false;

  // Refresh every minute to update course now/past state and day changes
  Timer? _refreshTimer;
  int _lastWeekday = DateTime.now().weekday;

  // Staggered entrance animation for course items
  AnimationController? _staggerController;
  List<Animation<double>> _itemSlides = [];
  List<Animation<double>> _itemFades = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _schedule = ServiceProvider.of(context).scheduleService;
      _schedule.addListener(_rebuild);
      _doRebuild();
      _refreshTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _onTimerTick(),
      );
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _schedule.removeListener(_rebuild);
    _staggerController?.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _doRebuild();
    });
  }

  void _onTimerTick() {
    if (!mounted) return;
    final now = DateTime.now().weekday;
    if (now != _lastWeekday) {
      // Day changed — rebuild course list for the new day
      _lastWeekday = now;
      _doRebuild();
    } else {
      // Same day — just repaint to update now/past state
      setState(() {});
    }
  }

  void _doRebuild() {
    final table = _schedule.courseTable;
    List<Course> newCourses;
    if (table != null) {
      if (table.periods.isNotEmpty) {
        _periods = table.periods.map((p) => p.toPeriod()).toList();
      }
      final week = _schedule.currentWeek();
      final today = DateTime.now().weekday;
      final all = eamsToDisplayCourses(table.courses, week);
      newCourses = all.where((c) => c.dayOfWeek == today).toList()
        ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    } else {
      newCourses = [];
    }

    final previousCount = _todayCourses.length;
    setState(() {
      _todayCourses = newCourses;
    });

    // Run stagger animation when courses appear for the first time
    if (previousCount == 0 && newCourses.isNotEmpty) {
      _runStaggerAnimation(newCourses.length);
    }
  }

  void _runStaggerAnimation(int count) {
    _staggerController?.dispose();
    _staggerController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + count * 60),
    );

    _itemSlides = [];
    _itemFades = [];
    for (int i = 0; i < count; i++) {
      final start = (i * 0.12).clamp(0.0, 0.6);
      final end = (start + 0.5).clamp(start + 0.1, 1.0);
      final interval = Interval(start, end, curve: Curves.easeOutCubic);
      _itemSlides.add(
        Tween<double>(begin: 24.0, end: 0.0).animate(
          CurvedAnimation(parent: _staggerController!, curve: interval),
        ),
      );
      _itemFades.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _staggerController!, curve: interval),
        ),
      );
    }

    _staggerController!.forward();
  }

  String _timeForCourse(Course course) {
    if (course.startPeriod - 1 < _periods.length &&
        course.endPeriod - 1 < _periods.length) {
      final start = _periods[course.startPeriod - 1];
      final end = _periods[course.endPeriod - 1];
      return '${start.startTime} – ${end.endTime}';
    }
    return '第${course.startPeriod}-${course.endPeriod}节';
  }

  bool _isCourseNow(Course course) {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    if (course.startPeriod - 1 >= _periods.length) return false;
    if (course.endPeriod - 1 >= _periods.length) return false;
    final start = _periods[course.startPeriod - 1];
    final end = _periods[course.endPeriod - 1];
    final startMin = _parseMinutes(start.startTime);
    final endMin = _parseMinutes(end.endTime);
    if (startMin == null || endMin == null) return false;
    return nowMinutes >= startMin && nowMinutes <= endMin;
  }

  bool _isCoursePast(Course course) {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    if (course.endPeriod - 1 >= _periods.length) return false;
    final end = _periods[course.endPeriod - 1];
    final endMin = _parseMinutes(end.endTime);
    if (endMin == null) return false;
    return nowMinutes > endMin;
  }

  static int? _parseMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ServiceProvider.of(context).authService;

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome to TechPie',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your academic dashboard at a glance.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildTodayClasses(theme, auth.isLoggedIn),
          const SizedBox(height: 8),
          Card.outlined(
            child: ListTile(
              leading: Icon(
                Icons.assignment_outlined,
                color: theme.colorScheme.tertiary,
              ),
              title: const Text('Pending assignments'),
              subtitle: const Text('All caught up!'),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayClasses(ThemeData theme, bool isLoggedIn) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1.0,
            child: child,
          ),
        );
      },
      child: !isLoggedIn
          ? _buildEmptyState(
              key: const ValueKey('not-logged-in'),
              theme: theme,
              icon: Icons.login_rounded,
              title: '登录以查看今日课程',
              subtitle: '连接你的教务系统账号',
            )
          : _todayCourses.isEmpty
          ? _buildEmptyState(
              key: const ValueKey('no-courses'),
              theme: theme,
              icon: Icons.wb_sunny_outlined,
              title: '今天没有课程',
              subtitle: '享受你的自由时间吧',
            )
          : _buildCourseList(theme),
    );
  }

  Widget _buildEmptyState({
    required Key key,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Card.outlined(
      key: key,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseList(ThemeData theme) {
    final hasStagger =
        _staggerController != null &&
        _itemSlides.length == _todayCourses.length;

    return Card.outlined(
      key: const ValueKey('courses'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('今日课程', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '${_todayCourses.length}节课',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (int i = 0; i < _todayCourses.length; i++) ...[
            if (hasStagger)
              AnimatedBuilder(
                animation: _staggerController!,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _itemSlides[i].value),
                    child: Opacity(opacity: _itemFades[i].value, child: child),
                  );
                },
                child: _buildCourseItem(theme, _todayCourses[i]),
              )
            else
              _buildCourseItem(theme, _todayCourses[i]),
            if (i < _todayCourses.length - 1)
              const Divider(height: 1, indent: 56),
          ],
        ],
      ),
    );
  }

  Widget _buildCourseItem(ThemeData theme, Course course) {
    final isNow = _isCourseNow(course);
    final isPast = _isCoursePast(course);
    final containerColor = course.color.containerColor(theme.colorScheme);
    final onContainerColor = course.color.onContainerColor(theme.colorScheme);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      opacity: isPast ? 0.5 : 1.0,
      child: ListTile(
        leading: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(isNow ? 12 : 8),
          ),
          alignment: Alignment.center,
          child: Text(
            '${course.startPeriod}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: onContainerColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          course.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isNow
              ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
              : null,
        ),
        subtitle: Text(
          '${_timeForCourse(course)}'
          '${course.location.isNotEmpty ? '  ${course.location}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: isNow
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '进行中',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
