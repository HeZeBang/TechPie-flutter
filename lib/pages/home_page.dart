import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/campus_card/app/app_providers.dart';
import '../models/assignment.dart';
import '../models/course.dart';
import '../models/course_table.dart';
import '../models/custom_course.dart';
import '../models/exam_course.dart';
import '../models/feature.dart';
import '../services/assignment_service.dart';
import '../services/auth_service.dart';
import '../services/campus_card_service.dart';
import '../services/schedule_service.dart';
import '../services/service_provider.dart';
import '../services/storage_service.dart';
import '../theme/theme.dart';
import '../utils/adaptive_motion.dart';
import '../utils/haptics.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell/app_shell.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/page_refresh.dart';
import '../widgets/privacy_consent.dart';
import '../widgets/uni_auth_login.dart';
import 'campus_card_page.dart';
import 'custom_deadline_editor_page.dart';
import 'generic_webview_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late ScheduleService _schedule;
  late AssignmentService _assignments;
  late AuthService _auth;
  List<Course> _todayCourses = [];
  List<Period> _periods = defaultPeriods.toList();
  bool _initialized = false;
  bool _animationsEnabled = true;

  // Refresh every minute to update course now/past state and day changes.
  Timer? _refreshTimer;
  int _lastWeekday = DateTime.now().weekday;

  // Debug time override (only active when debugMode is on).
  DateTime? _debugNow;
  bool _debugPanelExpanded = false;

  // Staggered entrance animation for course items.
  AnimationController? _staggerController;
  List<Animation<double>> _itemSlides = [];
  List<Animation<double>> _itemFades = [];

  /// Returns the debug-overridden time or real time.
  DateTime get _now => _debugNow ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animationsEnabled = appAnimationsEnabled(context);
    if (_animationsEnabled != animationsEnabled) {
      _animationsEnabled = animationsEnabled;
      if (!animationsEnabled) {
        _staggerController?.dispose();
        _staggerController = null;
        _itemSlides = [];
        _itemFades = [];
      }
    }
    if (!_initialized) {
      _initialized = true;
      final sp = ServiceProvider.of(context);
      _schedule = sp.scheduleService;
      _assignments = sp.assignmentService;
      _auth = sp.authService;
      _schedule.addListener(_rebuild);
      _assignments.addListener(_onAssignmentsChanged);
      _auth.addListener(_onAuthChanged);
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
    _auth.removeListener(_onAuthChanged);
    _staggerController?.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  void _onAssignmentsChanged() {
    _rebuild();
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

  int _resolvedWeek(DateTime now) {
    final termBegin = _schedule.termBegin;
    if (_schedule.isGraduate) {
      return teachingWeekOf(now, termBegin) ?? 0;
    }
    return _schedule.currentWeek();
  }

  void _doRebuild() {
    final table = _schedule.fullCourseTable;
    if (table != null && table.periods.isNotEmpty) {
      _periods = table.periods.map((p) => p.toPeriod()).toList();
    }
    final termBegin = _schedule.termBegin;
    final now = _now;
    final week = _resolvedWeek(now);
    final timetableCourses = table?.courses ?? const <EamsCourse>[];
    final withCustom = withCustomCourses(
      eamsToDisplayCourses(
        timetableCourses,
        week,
        timetablePeriods: _periods,
        onDate: now,
      ),
      _schedule.customCourses,
      week,
      termBegin,
      periods: _periods,
      onDate: now,
    );
    final all = withExamCourses(
      withCustom,
      examsForSemester(_assignments.assignments, _schedule.selectedSemesterId),
      week,
      termBegin,
      periods: _periods,
    );
    final newCourses = all
        .where(
          (course) => course.dayOfWeek == now.weekday && course.occursOn(now),
        )
        .toList()
      ..sort((a, b) {
        final startA = parseClockMinutes(a.startTime) ?? 0;
        final startB = parseClockMinutes(b.startTime) ?? 0;
        return startA.compareTo(startB);
      });

    final previousCount = _todayCourses.length;
    setState(() {
      _todayCourses = newCourses;
    });

    if (previousCount == 0 && newCourses.isNotEmpty) {
      _runStaggerAnimation(newCourses.length);
    }
  }

  void _runStaggerAnimation(int count) {
    _staggerController?.dispose();
    if (!_animationsEnabled) {
      _staggerController = null;
      _itemSlides = [];
      _itemFades = [];
      return;
    }
    _staggerController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + count * 60),
    );

    _itemSlides = [];
    _itemFades = [];
    for (int i = 0; i < count; i++) {
      final start = (i * 0.12).clamp(0.0, 0.6);
      final end = (start + 0.5).clamp(start + 0.1, 1.0);
      final interval = Interval(
        start,
        end,
        curve: appAnimationCurve(Curves.easeOutCubic),
      );
      _itemSlides.add(
        Tween<double>(begin: 20.0, end: 0.0).animate(
          CurvedAnimation(parent: _staggerController!, curve: interval),
        ),
      );
      _itemFades.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _staggerController!, curve: interval),
        ),
      );
    }

    unawaited(_staggerController!.forward());
  }

  _CourseStatus _courseStatus(Course course) {
    final nowMinutes = _now.hour * 60 + _now.minute;
    final start = _parseMinutes(course.startTime);
    final end = _parseMinutes(course.endTime);
    if (start != null && end != null) {
      if (nowMinutes > end) return _CourseStatus.past;
      if (nowMinutes >= start && nowMinutes <= end) {
        return _CourseStatus.ongoing;
      }
      final diff = start - nowMinutes;
      return diff > 0 && diff <= 15
          ? _CourseStatus.soon
          : _CourseStatus.upcoming;
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

  static String _greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 6) return '夜深了';
    if (hour < 11) return '早上好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  static String _greetingTitle(DateTime now, AuthService auth) {
    final base = _greeting(now);
    final session = auth.session;
    if (!auth.isLoggedIn || session == null) return base;
    final name = session.userName.trim().isNotEmpty
        ? session.userName.trim()
        : session.userId.trim();
    if (name.isEmpty) return base;
    return '$base，$name';
  }

  static String _avatarLabel(AuthService auth) {
    if (!auth.isLoggedIn) return 'GP';
    final name = auth.session?.userName.trim() ?? '';
    if (name.isEmpty) return 'GP';
    final runes = name.runes.toList();
    if (runes.first > 127) {
      return String.fromCharCode(runes.first);
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
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

  Future<void> _refreshHome() async {
    final sp = ServiceProvider.of(context);
    final tasks = <Future<void>>[
      sp.campusCardService.refreshAccount(),
    ];
    if (sp.thirdPartyAuthService.hasIdsBinding) {
      tasks.add(sp.scheduleService.fetchAll());
    }
    if (sp.authService.isLoggedIn ||
        sp.thirdPartyAuthService.boundPlatforms.isNotEmpty) {
      tasks.add(sp.assignmentService.fetchAssignments());
    }
    await Future.wait(tasks);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    // Subscribe to TickerMode so switching back to Home after toggling
    // privacy blur or debug mode in Settings immediately refreshes the view.
    // ignore: deprecated_member_use
    TickerMode.of(context);
    final colors = context.tpColors;
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final storage = sp.storageService;
    final campusCard = sp.campusCardService;
    final isDebug = storage.debugMode;
    final now = _now;
    final week = _resolvedWeek(now);
    final dateSubtitle =
        '${now.month}月${now.day}日 星期${_dayLabels[now.weekday - 1]}'
        '${week > 0 ? ' · 第 $week 周' : ''}';

    final isBento =
        MediaQuery.sizeOf(context).width >= TpTokens.bentoBreakpoint;
    final horizontalPadding = isBento
        ? TpTokens.pageHorizontalPaddingWide
        : TpTokens.pageHorizontalPadding;

    final header = TpPageHeader(
      key: const ValueKey('home.greeting-header'),
      subtitle: dateSubtitle,
      title: _greetingTitle(now, auth),
      trailing: TpAvatarBadge(
        key: const ValueKey('home.avatar'),
        text: _avatarLabel(auth),
        tooltip: auth.isLoggedIn ? '我的' : '登录',
        onTap: () {
          if (auth.isLoggedIn) {
            appShellPendingTab.value = 3;
          } else {
            unawaited(startUniAuthLogin(context));
          }
        },
      ),
    );
    final campusCardStrip = _buildCampusCardStrip(
      campusCard,
      storage,
      expandedCard: isBento,
    );
    final todayClasses = _buildTodayClasses(colors, auth.isLoggedIn);
    final deadlines = _buildPendingAssignments(colors);
    final quickActions = _buildQuickActions();
    final debugPanel = isDebug ? _buildDebugPanel(colors) : null;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: PageRefreshIndicator(
          onRefresh: _refreshHome,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              isBento ? TpTokens.space5 : TpTokens.space3,
              horizontalPadding,
              AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              TpPageBody(
                maxWidth: isBento ? 1120 : TpTokens.singleColumnMaxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    SizedBox(
                      height: isBento ? TpTokens.space4 : TpTokens.sectionGap,
                    ),
                    if (isBento)
                      TpBentoGrid(
                        primaryColumn: [
                          todayClasses,
                          deadlines,
                          if (debugPanel != null) debugPanel,
                        ],
                        secondaryColumn: [
                          campusCardStrip,
                          quickActions,
                        ],
                      )
                    else ...[
                      campusCardStrip,
                      const SizedBox(height: TpTokens.sectionGap),
                      todayClasses,
                      const SizedBox(height: TpTokens.sectionGap),
                      deadlines,
                      const SizedBox(height: TpTokens.sectionGap),
                      quickActions,
                      if (debugPanel != null) ...[
                        const SizedBox(height: TpTokens.sectionGap),
                        debugPanel,
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCampusCardStrip(
    CampusCardService campusCard,
    StorageService storage, {
    required bool expandedCard,
  }) {
    return ListenableBuilder(
      listenable: campusCard,
      builder: (context, _) {
        final balance = campusCard.cachedBalance;
        final balanceText =
            balance == null ? null : '¥ ${balance.toYuanFixed()}';
        return TpCampusCardStrip(
          configured: campusCard.configured,
          balanceText: balanceText,
          hideBalance: storage.hideCampusCardBalance,
          onToggleHideBalance: () {
            unawaited(AppHaptics.play(AppHaptics.selection));
            unawaited(
              storage.setHideCampusCardBalance(!storage.hideCampusCardBalance),
            );
            setState(() {});
          },
          expandedCard: expandedCard,
          onOpenPayCode: () {
            unawaited(AppHaptics.play(AppHaptics.lightImpact));
            unawaited(
              pushAdaptivePage<void>(
                context,
                builder: (_) => const CampusCardPage(
                  entry: CampusCardEntry.paymentCode,
                ),
              ),
            );
          },
          onOpenCard: () => unawaited(
            pushAdaptivePage<void>(
              context,
              builder: (_) => CampusCardPage(
                entry: campusCard.configured
                    ? CampusCardEntry.cardManagement
                    : CampusCardEntry.paymentCode,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    // Campus Card already has its own dedicated hero card directly above.
    final quickFeatures = featureEntries
        .where((feature) => feature.id != 'campus_card')
        .toList(growable: false);
    return TpCard(
      key: const ValueKey('home.quick-actions'),
      title: '快捷功能',
      child: AppCard(
        features: quickFeatures,
        rows: 2,
        columns: 3,
        onFeatureTap: _handleFeatureTap,
      ),
    );
  }

  void _handleFeatureTap(Feature feature) {
    unawaited(AppHaptics.play(AppHaptics.selection));
    if (!ServiceProvider.of(context).authService.isLoggedIn) {
      unawaited(startUniAuthLogin(context));
      return;
    }
    switch (feature.mode) {
      case FeatureMode.native:
        feature.nativeEntry?.call(context);
        break;
      case FeatureMode.webviewWithCookie:
        if (feature.url != null) {
          unawaited(
            pushAdaptivePage<void>(
              context,
              builder: (_) => GenericWebViewPage(
                title: feature.description,
                url: feature.url!,
                cookieType: feature.cookieType,
              ),
            ),
          );
        }
        break;
    }
  }

  Widget _buildTodayClasses(TpColors colors, bool isLoggedIn) {
    final String trailingText;
    Widget content;
    if (!isLoggedIn) {
      trailingText = '未登录';
      content = _buildCompactEmpty(
        key: const ValueKey('not-logged-in'),
        colors: colors,
        icon: TpIcons.login,
        title: '登录以查看今日课程',
        subtitle: '连接你的教务系统账号',
        actionLabel: '登录',
        actionSfSymbol: 'person.crop.circle.badge.checkmark',
        footer: const PrivacyNotice(),
        onTap: () async {
          await startUniAuthLogin(context);
          if (!mounted) return;
          setState(() {});
        },
      );
    } else if (_todayCourses.isEmpty) {
      trailingText = '0 节';
      content = _buildCompactEmpty(
        key: ValueKey('no-courses-${_now.weekday}'),
        colors: colors,
        icon: TpIcons.sun,
        title: '今天没有课程',
        subtitle: '享受你的自由时间吧',
      );
    } else {
      trailingText = '${_todayCourses.length} 节';
      content = _buildCourseContent(
        key: ValueKey('courses-${_now.weekday}'),
        colors: colors,
      );
    }

    return TpCard(
      key: const ValueKey('home.today-courses'),
      title: '今日课程',
      trailing: Text(trailingText),
      child: AnimatedSize(
        duration: appAnimationDuration(context, TpTokens.durationSlow),
        curve: appAnimationCurve(Curves.easeOutCubic),
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: appAnimationDuration(context, TpTokens.durationNormal),
          switchInCurve: appAnimationCurve(Curves.easeOutCubic),
          switchOutCurve: appAnimationCurve(
            Curves.easeInCubic,
            iosCurve: Curves.easeInOut,
          ),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: content,
        ),
      ),
    );
  }

  Widget _buildCourseContent({required Key key, required TpColors colors}) {
    final hasStagger = _staggerController != null &&
        _itemSlides.length == _todayCourses.length;

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: TpTokens.space1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _todayCourses.length; i++)
            if (hasStagger)
              AnimatedBuilder(
                animation: _staggerController!,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _itemSlides[i].value),
                    child: Opacity(opacity: _itemFades[i].value, child: child),
                  );
                },
                child: _buildCourseItem(colors, _todayCourses[i], i),
              )
            else
              _buildCourseItem(colors, _todayCourses[i], i),
        ],
      ),
    );
  }

  Widget _buildCourseItem(TpColors colors, Course course, int index) {
    final status = _courseStatus(course);
    final isActive = status == _CourseStatus.ongoing;
    final isSoon = status == _CourseStatus.soon;
    final isPast = status == _CourseStatus.past;

    final isExam = course.source is ExamCourseSource;
    final barColor = isExam
        ? colors.dangerRed
        : course.color.accentColor(colors.brightness);

    final subtitle = course.location.isNotEmpty
        ? '${course.timeLabel} · ${course.location}'
        : course.timeLabel;

    Widget? trailing;
    if (isActive) {
      trailing = const TpBadge(label: '进行中', tone: TpBadgeTone.brand);
    } else if (isSoon) {
      trailing = const TpBadge(label: '即将开始', tone: TpBadgeTone.success);
    } else if (isExam) {
      trailing = const TpBadge(label: '考试', tone: TpBadgeTone.danger);
    }

    return TpAccentRow(
      accentColor: barColor,
      title: course.name,
      subtitle: subtitle,
      trailing: trailing,
      boldTitle: isActive,
      opacity: isPast ? 0.45 : 1.0,
      showDivider: index < _todayCourses.length - 1,
      onTap: () => appShellPendingTab.value = 1,
    );
  }

  Widget _buildPendingAssignments(TpColors colors) {
    final now = _now;
    DateTime activeDueOf(Assignment a) =>
        (a.effectiveLateDue != null && a.due.isBefore(now))
            ? a.effectiveLateDue!
            : a.due;
    final pending = _assignments.visibleAssignments
        .where(
          (a) => !_assignments.isCompleted(a) && !a.effectiveDue.isBefore(now),
        )
        .toList()
      ..sort((a, b) => activeDueOf(a).compareTo(activeDueOf(b)));

    final showCount = pending.length.clamp(0, 4);
    final overflow = pending.length - showCount;

    final String trailingText =
        pending.isEmpty ? '0 项' : '${pending.length} 项待完成';

    Widget content;
    if (pending.isEmpty) {
      content = _buildCompactEmpty(
        key: const ValueKey('no-pending'),
        colors: colors,
        icon: TpIcons.checkCircle,
        title: '没有待办事项',
        subtitle: 'All caught up!',
      );
    } else {
      content = Padding(
        key: ValueKey('pending-${pending.length}-${now.day}-${now.hour}'),
        padding: const EdgeInsets.only(bottom: TpTokens.space1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < showCount; i++)
              _buildPendingItem(
                colors,
                pending[i],
                now,
                showDivider: i < showCount - 1,
              ),
            if (overflow > 0)
              InkWell(
                onTap: () => appShellPendingDeadlines.value = true,
                hoverColor: colors.textPrimary.withValues(
                  alpha: colors.isDark ? 0.06 : 0.04,
                ),
                splashColor: colors.brandSoft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TpTokens.cardPaddingHorizontal,
                    TpTokens.space2,
                    TpTokens.cardPaddingHorizontal,
                    TpTokens.space3,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '还有 $overflow 项 · 前往 Deadlines 查看全部',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TpTypography.cardMeta(colors).copyWith(
                            color: colors.brandInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        TpIcons.chevronRight,
                        size: TpTokens.iconXs,
                        color: colors.brandInk,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return TpCard(
      key: const ValueKey('home.deadlines'),
      title: 'Deadlines',
      trailing: Text(trailingText),
      child: AnimatedSize(
        duration: appAnimationDuration(context, TpTokens.durationSlow),
        curve: appAnimationCurve(Curves.easeOutCubic),
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: appAnimationDuration(context, TpTokens.durationNormal),
          switchInCurve: appAnimationCurve(Curves.easeOutCubic),
          switchOutCurve: appAnimationCurve(
            Curves.easeInCubic,
            iosCurve: Curves.easeInOut,
          ),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: content,
        ),
      ),
    );
  }

  Widget _buildPendingItem(
    TpColors colors,
    Assignment a,
    DateTime now, {
    required bool showDivider,
  }) {
    final inLateWindow = a.effectiveLateDue != null && a.due.isBefore(now);
    final activeDue = inLateWindow ? a.effectiveLateDue! : a.due;
    final dueColor =
        inLateWindow ? colors.dangerRed : _dueColor(activeDue, now, colors);
    final dueLabel = inLateWindow
        ? '迟交${_dueLabel(activeDue, now)}'
        : _dueLabel(activeDue, now);
    final progress = inLateWindow ? 1.0 : _urgencyProgress(activeDue, now);
    final detail = switch (a) {
      ExamAssignment(:final location) => location.trim(),
      CustomDeadline(:final course, :final location) => [
          if (course.isNotEmpty) course,
          if (location.isNotEmpty) location,
        ].join(' · '),
      _ => [
          if (a.platform.isNotEmpty) a.platform,
          if (a.course.isNotEmpty) a.course,
        ].join(' · '),
    };

    return TpProgressRow(
      title: a.title,
      subtitle: detail,
      trailingLabel: dueLabel,
      progress: progress,
      color: dueColor,
      showDivider: showDivider,
      onTap: () => unawaited(
        a is CustomDeadline
            ? CustomDeadlineEditorPage.open(context, deadline: a)
            : _openAssignmentUrl(a),
      ),
    );
  }

  static double _urgencyProgress(DateTime due, DateTime now) {
    final hoursLeft = due.difference(now).inMinutes / 60.0;
    if (hoursLeft <= 0) return 1.0;
    // Maps a 7-day horizon (168h) onto [0.15, 0.95] so nearer deadlines fill
    // further across the bar.
    return (1.0 - hoursLeft / 168.0).clamp(0.15, 0.95);
  }

  static String _dueLabel(DateTime due, DateTime now) {
    final diff = due.difference(now);
    if (diff.inDays >= 3) {
      return '剩余 ${diff.inDays} 天';
    }
    if (diff.inDays >= 1) {
      final remHours = diff.inHours % 24;
      return remHours > 0
          ? '剩余 ${diff.inDays} 天 $remHours 小时'
          : '剩余 ${diff.inDays} 天';
    }
    if (diff.inHours >= 1) return '剩余 ${diff.inHours} 小时';
    final minutes = diff.inMinutes;
    if (minutes >= 1) return '剩余 $minutes 分钟';
    return '< 1 分钟';
  }

  static Color _dueColor(DateTime due, DateTime now, TpColors colors) {
    final diff = due.difference(now);
    if (diff.inHours < 24) return colors.dangerRed;
    if (diff.inDays < 3) return colors.warningAmber;
    return colors.infoBlue;
  }

  Future<void> _openAssignmentUrl(Assignment a) async {
    final url = a.url;
    if (url == null || url.isEmpty) {
      final itemLabel = a.kind == DeadlineKind.exam ? '考试' : '作业';
      showAdaptiveFeedback(
        context: context,
        message: '该$itemLabel没有可打开的链接',
        style: AdaptiveFeedbackStyle.info,
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildCompactEmpty({
    required Key key,
    required TpColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    String? actionSfSymbol,
    VoidCallback? onTap,
    Widget? footer,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(
        TpTokens.cardPaddingHorizontal,
        TpTokens.space1,
        TpTokens.cardPaddingHorizontal,
        TpTokens.cardPaddingVertical,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(TpTokens.radiusS),
                ),
                child: Icon(
                  icon,
                  size: TpTokens.iconM - 2,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(width: TpTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TpTypography.itemTitle(colors),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TpTypography.itemMeta(colors),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onTap != null && actionLabel != null) ...[
            const SizedBox(height: TpTokens.space3),
            AdaptiveButton(
              label: actionLabel,
              icon: icon,
              sfSymbol: actionSfSymbol ?? 'arrow.right',
              role: AdaptiveButtonRole.prominent,
              height: 44,
              onPressed: onTap,
              accessibilityLabel: actionLabel,
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: TpTokens.space3),
            footer,
          ],
        ],
      ),
    );
  }

  // ── Debug Panel ──

  static const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  Widget _buildDebugPanel(TpColors colors) {
    final now = _now;
    final minutes = now.hour * 60.0 + now.minute;
    final isOverriding = _debugNow != null;
    final timeFormatted =
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes.toInt() % 60).toString().padLeft(2, '0')}';

    return TpCard(
      borderColor: colors.dangerRed.withValues(alpha: 0.35),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TpListRow(
            icon: TpIcons.bug,
            iconColor: colors.dangerRed,
            title: 'Debug: Time Override',
            subtitle: isOverriding
                ? '周${_dayLabels[now.weekday - 1]} $timeFormatted'
                : 'Real time',
            trailing: Icon(
              _debugPanelExpanded ? TpIcons.close : TpIcons.sliders,
              size: TpTokens.iconS,
              color: colors.textMuted,
            ),
            onTap: () => setState(() {
              _debugPanelExpanded = !_debugPanelExpanded;
            }),
          ),
          AnimatedCrossFade(
            duration: appAnimationDuration(context, TpTokens.durationNormal),
            crossFadeState: _debugPanelExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                TpTokens.cardPaddingHorizontal,
                0,
                TpTokens.cardPaddingHorizontal,
                TpTokens.cardPaddingHorizontal,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(height: 1, thickness: 0.5, color: colors.divider),
                  const SizedBox(height: TpTokens.space3),
                  Text('Time of day', style: TpTypography.cardMeta(colors)),
                  Row(
                    children: [
                      Text(
                        timeFormatted,
                        style: TpTypography.itemTitle(colors).copyWith(
                          fontFeatures: TpTypography.tabularFigures,
                        ),
                      ),
                      const SizedBox(width: TpTokens.space2),
                      Expanded(
                        child: Slider(
                          value: minutes,
                          min: 0,
                          max: 1439,
                          divisions: 1439,
                          onChanged: _debugSetTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: TpTokens.space2),
                  Text(
                    'Day (周${_dayLabels[now.weekday - 1]} ${DateFormat('MM/dd').format(now)})',
                    style: TpTypography.cardMeta(colors),
                  ),
                  const SizedBox(height: TpTokens.space2),
                  Wrap(
                    spacing: TpTokens.space2,
                    runSpacing: TpTokens.space2,
                    children: [
                      _DebugChip(
                        label: '- Day',
                        icon: TpIcons.chevronLeft,
                        onPressed: () => _debugShiftDay(-1),
                      ),
                      _DebugChip(
                        label: '+ Day',
                        icon: TpIcons.chevronRight,
                        onPressed: () => _debugShiftDay(1),
                      ),
                      _DebugChip(
                        label: 'Replay',
                        icon: TpIcons.refresh,
                        onPressed: _debugReplayStagger,
                      ),
                      _DebugChip(
                        label: 'Reset',
                        icon: TpIcons.close,
                        onPressed: _debugReset,
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
      avatar: Icon(icon, size: TpTokens.iconS),
      label: Text(label),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
    );
  }
}
