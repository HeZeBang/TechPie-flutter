import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../models/course_table.dart';
import '../models/feature.dart';
import '../services/assignment_service.dart';
import '../services/schedule_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/app_card.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import 'generic_webview_page.dart';
import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late ScheduleService _schedule;
  late AssignmentService _assignments;
  List<Course> _todayCourses = [];
  List<Period> _periods = defaultPeriods.toList();
  bool _initialized = false;

  // Refresh every minute to update course now/past state and day changes
  Timer? _refreshTimer;
  int _lastWeekday = DateTime.now().weekday;

  // Debug time override (only active when debugMode is on)
  DateTime? _debugNow;
  bool _debugPanelExpanded = false;

  // Staggered entrance animation for course items
  AnimationController? _staggerController;
  List<Animation<double>> _itemSlides = [];
  List<Animation<double>> _itemFades = [];

  /// Returns the debug-overridden time or real time.
  DateTime get _now => _debugNow ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _schedule = ServiceProvider.of(context).scheduleService;
      _assignments = ServiceProvider.of(context).assignmentService;
      _schedule.addListener(_rebuild);
      _assignments.addListener(_onAssignmentsChanged);
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
    _assignments.removeListener(_onAssignmentsChanged);
    _staggerController?.dispose();
    super.dispose();
  }

  void _onAssignmentsChanged() {
    if (!mounted) return;
    setState(() {});
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
    if (_debugNow != null) return; // paused in debug mode
    final now = DateTime.now().weekday;
    if (now != _lastWeekday) {
      _lastWeekday = now;
      _doRebuild();
    } else {
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
      final today = _now.weekday;
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

  _CourseStatus _courseStatus(Course course) {
    final nowMinutes = _now.hour * 60 + _now.minute;

    // Past?
    if (course.endPeriod - 1 < _periods.length) {
      final endMin = _parseMinutes(_periods[course.endPeriod - 1].endTime);
      if (endMin != null && nowMinutes > endMin) return _CourseStatus.past;
    }

    // Ongoing?
    if (course.startPeriod - 1 < _periods.length &&
        course.endPeriod - 1 < _periods.length) {
      final startMin = _parseMinutes(
        _periods[course.startPeriod - 1].startTime,
      );
      final endMin = _parseMinutes(_periods[course.endPeriod - 1].endTime);
      if (startMin != null &&
          endMin != null &&
          nowMinutes >= startMin &&
          nowMinutes <= endMin) {
        return _CourseStatus.ongoing;
      }
    }

    // Starting soon (within 15 minutes)?
    if (course.startPeriod - 1 < _periods.length) {
      final startMin = _parseMinutes(
        _periods[course.startPeriod - 1].startTime,
      );
      if (startMin != null) {
        final diff = startMin - nowMinutes;
        if (diff > 0 && diff <= 15) return _CourseStatus.soon;
      }
    }

    return _CourseStatus.upcoming;
  }

  static int? _parseMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  // ── Debug controls ──

  void _debugSetTime(double minuteOfDay) {
    final base = _debugNow ?? DateTime.now();
    setState(() {
      _debugNow = DateTime(
        base.year,
        base.month,
        base.day,
        minuteOfDay ~/ 60,
        minuteOfDay.toInt() % 60,
      );
    });
  }

  void _debugShiftDay(int delta) {
    final base = _debugNow ?? DateTime.now();
    final newDay = base.add(Duration(days: delta));
    setState(() {
      _debugNow = newDay;
      _lastWeekday = newDay.weekday;
    });
    _doRebuild();
  }

  void _debugReset() {
    setState(() {
      _debugNow = null;
      _debugPanelExpanded = false;
      _lastWeekday = DateTime.now().weekday;
    });
    _doRebuild();
  }

  void _debugReplayStagger() {
    if (_todayCourses.isNotEmpty) {
      _runStaggerAnimation(_todayCourses.length);
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final isDebug = sp.storageService.debugMode;
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 16.0
        : 16 + adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? const IosNativeNavigationBar(title: 'Home', largeTitleMode: true)
          : const BlurredAppBar(title: Text('Home')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          topInset,
          16,
          120,
        ),
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
          _buildAppCard(featureEntries),
          const SizedBox(height: 16),
          _buildTodayClasses(theme, auth.isLoggedIn),
          const SizedBox(height: 8),
          _buildPendingAssignments(theme),
          if (isDebug) ...[const SizedBox(height: 16), _buildDebugPanel(theme)],
        ],
      ),
    );
  }

  Widget _buildAppCard(
    List<Feature> features, {
    int rows = 2,
  }) {
    final theme = Theme.of(context);

    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          key: ValueKey('apps-${features.length}-$rows'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.apps_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text('应用', style: theme.textTheme.titleSmall),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppCard(
                features: features,
                rows: rows,
                onFeatureTap: _handleFeatureTap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleFeatureTap(Feature feature) {
    switch (feature.mode) {
      case FeatureMode.native:
        feature.nativeEntry?.call(context);
        break;
      case FeatureMode.webviewWithCookie:
        final cookies = _buildCookiesForFeature(feature.cookieType);
        if (feature.url != null) {
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GenericWebViewPage(
                  title: feature.description,
                  url: feature.url!,
                  cookies: cookies,
                ),
              ),
            ),
          );
        }
        break;
    }
  }

  List<WebViewCookie> _buildCookiesForFeature(CookieType? cookieType) {
    final cookies = <WebViewCookie>[];
    if (cookieType == null) return cookies;

    final sp = ServiceProvider.of(context);
    // ecourse and student-leave both authenticate against the eGate/IDS
    // SSO, so they share the eGate binding's CpDaily cookies (which always
    // include CASTGC via [ThirdPartyAuthService.egateCookies]). Without an
    // eGate binding there is nothing to inject and the webview opens
    // unauthenticated — the UI should steer the user to bind eGate first.
    final String rawCookies = sp.thirdPartyAuthService.egateCookies();
    if (rawCookies.isEmpty) return cookies;

    final domain = 'ids.shanghaitech.edu.cn';

    for (final part in rawCookies.split(';')) {
      final idx = part.indexOf('=');
      if (idx > 0) {
        final key = part.substring(0, idx).trim();
        final value = part.substring(idx + 1).trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          cookies.add(
            WebViewCookie(
              name: key,
              value: value,
              domain: domain,
              path: '/',
            ),
          );
        }
      }
    }

    return cookies;
  }

  Widget _buildTodayClasses(ThemeData theme, bool isLoggedIn) {
    Widget content;
    if (!isLoggedIn) {
      content = _buildEmptyContent(
        key: const ValueKey('not-logged-in'),
        theme: theme,
        icon: Icons.login_rounded,
        title: '登录以查看今日课程',
        subtitle: '连接你的教务系统账号',
        onTap: () async {
          await presentLoginPage(context);
          if (!mounted) return;
          setState(() {});
        },
      );
    } else if (_todayCourses.isEmpty) {
      content = _buildEmptyContent(
        key: ValueKey('no-courses-${_now.weekday}'),
        theme: theme,
        icon: Icons.wb_sunny_outlined,
        title: '今天没有课程',
        subtitle: '享受你的自由时间吧',
      );
    } else {
      content = _buildCourseContent(
        key: ValueKey('courses-${_now.weekday}'),
        theme: theme,
      );
    }

    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.topCenter,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child: content,
        ),
      ),
    );
  }

  Widget _buildPendingAssignments(ThemeData theme) {
    final now = _now;
    final pending = _assignments.visibleAssignments
        .where((a) => !_assignments.isCompleted(a) && a.due.isAfter(now))
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    final showCount = pending.length.clamp(0, 5);
    final overflow = pending.length - showCount;

    Widget content;
    if (pending.isEmpty) {
      content = _buildEmptyContent(
        key: const ValueKey('no-pending'),
        theme: theme,
        icon: Icons.assignment_turned_in_outlined,
        title: '没有待办事项',
        subtitle: 'All caught up!',
      );
    } else {
      content = Column(
        key: ValueKey('pending-${pending.length}-${now.day}-${now.hour}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.event_note_outlined,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Text('待办事项', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '${pending.length} 项',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (int i = 0; i < showCount; i++) ...[
            _buildPendingItem(theme, pending[i], now),
            if (i < showCount - 1) const Divider(height: 1),
          ],
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                '还有 $overflow 项,前往 Deadlines 查看全部',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      );
    }

    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.topCenter,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child: content,
        ),
      ),
    );
  }

  Widget _buildPendingItem(ThemeData theme, Assignment a, DateTime now) {
    final scheme = theme.colorScheme;
    final dueColor = _dueColor(a.due, now, scheme);
    final dueLabel = _dueLabel(a.due, now);

    return InkWell(
      onTap: () => unawaited(_openAssignmentUrl(a)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    a.course,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: dueColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                dueLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: dueColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dueLabel(DateTime due, DateTime now) {
    final diff = due.difference(now);
    if (diff.inDays >= 3) {
      return DateFormat('MM/dd HH:mm').format(due);
    }
    if (diff.inDays >= 1) return '${diff.inDays} 天内';
    if (diff.inHours >= 1) return '${diff.inHours} 小时内';
    final minutes = diff.inMinutes;
    if (minutes >= 1) return '$minutes 分钟内';
    return '< 1 分钟';
  }

  Color _dueColor(DateTime due, DateTime now, ColorScheme scheme) {
    final diff = due.difference(now);
    if (diff.inHours < 24) return scheme.error;
    if (diff.inDays < 3) return Colors.orange.shade700;
    return scheme.onSurfaceVariant;
  }

  Future<void> _openAssignmentUrl(Assignment a) async {
    final url = a.url;
    if (url == null || url.isEmpty) {
      final itemLabel = a.kind == DeadlineKind.exam ? '考试' : '作业';
      if (isIos()) {
        await showAdaptiveAlertDialog<void>(
          context: context,
          title: '无法打开$itemLabel',
          message: '这个$itemLabel没有可打开的链接。',
          actions: const [
            AdaptiveAlertAction<void>(label: 'Done', isDefault: true),
          ],
        );
      } else {
        showAdaptiveFeedback(
          context: context,
          message: '该$itemLabel没有链接',
          style: AdaptiveFeedbackStyle.info,
        );
      }
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildEmptyContent({
    required Key key,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final inner = SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
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

    if (onTap != null) {
      return InkWell(
        key: key,
        onTap: onTap,
        child: inner,
      );
    }

    return Container(key: key, child: inner);
  }

  Widget _buildCourseContent({required Key key, required ThemeData theme}) {
    final hasStagger = _staggerController != null &&
        _itemSlides.length == _todayCourses.length;

    return Column(
      key: key,
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
                '${_todayCourses.length} 节课',
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
          if (i < _todayCourses.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }

  Widget _buildCourseItem(ThemeData theme, Course course) {
    final status = _courseStatus(course);
    final isActive = status == _CourseStatus.ongoing;
    final isPast = status == _CourseStatus.past;

    // Smooth title weight transition
    final titleStyle =
        (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
      color: theme.colorScheme.onSurface,
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      opacity: isPast ? 0.5 : 1.0,
      child: ListTile(
        title: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          style: titleStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: Text(course.name),
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
        trailing: _CourseBadge(status: status, theme: theme),
      ),
    );
  }

  // ── Debug Panel ──

  static const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  Widget _buildDebugPanel(ThemeData theme) {
    final now = _now;
    final minutes = now.hour * 60.0 + now.minute;
    final isOverriding = _debugNow != null;

    return Card(
      color: theme.colorScheme.errorContainer.withAlpha(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.error.withAlpha(80)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(
              Icons.bug_report,
              color: theme.colorScheme.error,
              size: 20,
            ),
            title: Text(
              'Debug: Time Override',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            subtitle: isOverriding
                ? Text(
                    '${_dayLabels[now.weekday - 1]}  '
                    '${now.hour.toString().padLeft(2, '0')}:'
                    '${now.minute.toString().padLeft(2, '0')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Text(
                    'Real time',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
            trailing: Icon(
              _debugPanelExpanded ? Icons.expand_less : Icons.expand_more,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onTap: () => setState(() {
              _debugPanelExpanded = !_debugPanelExpanded;
            }),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _debugPanelExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Time slider
                  Text(
                    'Time of day',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
                        '${(minutes.toInt() % 60).toString().padLeft(2, '0')}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          value: minutes,
                          min: 0,
                          max: 1439,
                          divisions: 1439,
                          onChanged: (v) => _debugSetTime(v),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Day shift buttons
                  Text(
                    'Day (周${_dayLabels[now.weekday - 1]}  '
                    '${now.month}/${now.day})',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _DebugChip(
                        label: '- Day',
                        icon: Icons.chevron_left,
                        onPressed: () => _debugShiftDay(-1),
                      ),
                      const SizedBox(width: 8),
                      _DebugChip(
                        label: '+ Day',
                        icon: Icons.chevron_right,
                        onPressed: () => _debugShiftDay(1),
                      ),
                      const SizedBox(width: 8),
                      _DebugChip(
                        label: 'Replay',
                        icon: Icons.replay,
                        onPressed: _debugReplayStagger,
                      ),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: _debugReset,
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Reset'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CourseStatus { upcoming, soon, ongoing, past }

/// Badge that smoothly transitions between states with slide + size animation.
class _CourseBadge extends StatelessWidget {
  final _CourseStatus status;
  final ThemeData theme;

  const _CourseBadge({required this.status, required this.theme});

  @override
  Widget build(BuildContext context) {
    final hasBadge =
        status == _CourseStatus.soon || status == _CourseStatus.ongoing;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.3, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: hasBadge
          ? _buildBadgeContent()
          : const SizedBox.shrink(key: ValueKey('none')),
    );
  }

  Widget _buildBadgeContent() {
    final isSoon = status == _CourseStatus.soon;
    final bgColor = isSoon
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.primaryContainer;
    final fgColor = isSoon
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onPrimaryContainer;
    final label = isSoon ? '即将开始' : '正在进行';

    return Container(
      key: ValueKey(status),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: fgColor),
      ),
    );
  }
}

class _DebugChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _DebugChip({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
    );
  }
}
