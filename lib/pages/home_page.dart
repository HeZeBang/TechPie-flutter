import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/campus_card/app/app_providers.dart';
import '../models/assignment.dart';
import '../models/course.dart';
import '../models/course_table.dart';
import '../models/custom_course.dart';
import '../models/exam_course.dart';
import '../models/feature.dart';
import '../models/home_layout.dart';
import '../services/assignment_service.dart';
import '../services/auth_service.dart';
import '../services/campus_card_service.dart';
import '../services/schedule_service.dart';
import '../services/service_provider.dart';
import '../services/storage_service.dart';
import '../services/third_party_auth_service.dart';
import '../theme/theme.dart';
import '../utils/adaptive_layout.dart';
import '../utils/adaptive_motion.dart';
import '../utils/haptics.dart';
import '../utils/user_display_name.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_slider.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell/app_shell.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/app_shell/desktop/desktop_shell.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/home/home_bento_editor.dart';
import '../widgets/home/home_campus_service_widgets.dart';
import '../widgets/home/home_mobile_reorder_list.dart';
import '../widgets/home/home_widget_chrome.dart';
import '../widgets/home/home_widget_gallery_sheet.dart';
import '../widgets/page_refresh.dart';
import '../widgets/privacy_consent.dart';
import '../widgets/uni_auth_login.dart';
import 'campus_card_page.dart';
import 'campus_feature_navigation.dart';
import 'campus_services_page.dart';
import 'custom_deadline_editor_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late ScheduleService _schedule;
  late AssignmentService _assignments;
  late AuthService _auth;
  late ThirdPartyAuthService _tpAuth;
  late CampusCardService _campusCard;
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

  // Customizable dashboard layout state (mobile & desktop stored independently).
  late StorageService _storage;
  HomeMobileLayout _mobileLayout = HomeMobileLayout.defaults();
  HomeDesktopLayout _desktopLayout = HomeDesktopLayout.defaults();
  bool _isEditing = false;
  bool _pendingEditAfterMobileDrag = false;
  bool _mobileDragEndedNaturally = false;
  final ValueNotifier<HomeGalleryState> _galleryState = ValueNotifier(
    const HomeGalleryState(
      visibleIds: {
        HomeWidgetId.campusCard,
        HomeWidgetId.todayCourses,
        HomeWidgetId.deadlines,
        HomeWidgetId.quickActions,
      },
      campusCardStyle: HomeCampusCardStyle.compact,
    ),
  );

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
      _tpAuth = sp.thirdPartyAuthService;
      _campusCard = sp.campusCardService;
      _storage = sp.storageService;
      _mobileLayout = _storage.homeMobileLayout;
      _desktopLayout = _storage.homeDesktopLayout;
      _schedule.addListener(_rebuild);
      _assignments.addListener(_onAssignmentsChanged);
      _auth.addListener(_onAuthChanged);
      _tpAuth.addListener(_onAuthChanged);
      _campusCard.addListener(_onAuthChanged);
      _storage.pinnedQuickFeaturesVersion.addListener(_onQuickShortcutsChanged);
      appShellPendingHomeEdit.addListener(_onPendingHomeEdit);
      HardwareKeyboard.instance.addHandler(_handleHardwareKey);
      _doRebuild();
      _refreshTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _onTimerTick(),
      );
      _consumePendingHomeEdit();
    } else {
      _consumePendingHomeEdit();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _schedule.removeListener(_rebuild);
    _assignments.removeListener(_onAssignmentsChanged);
    _auth.removeListener(_onAuthChanged);
    _tpAuth.removeListener(_onAuthChanged);
    _campusCard.removeListener(_onAuthChanged);
    _storage.pinnedQuickFeaturesVersion.removeListener(_onQuickShortcutsChanged);
    appShellPendingHomeEdit.removeListener(_onPendingHomeEdit);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _galleryState.dispose();
    _staggerController?.dispose();
    super.dispose();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted || !_isEditing) return false;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    _exitEditMode();
    return true;
  }

  void _onPendingHomeEdit() {
    _consumePendingHomeEdit();
  }

  void _consumePendingHomeEdit() {
    if (!appShellPendingHomeEdit.value) return;
    appShellPendingHomeEdit.value = false;
    if (!mounted || _isEditing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isEditing) return;
      final isBento =
          MediaQuery.sizeOf(context).width >= TpTokens.bentoBreakpoint;
      _enterEditMode(isBento);
    });
  }

  void _syncGalleryNotifier(bool isBento) {
    _galleryState.value = isBento
        ? HomeGalleryState(
            visibleIds: {
              ..._desktopLayout.primary,
              ..._desktopLayout.secondary,
            },
            campusCardStyle: _desktopLayout.campusCardStyle,
          )
        : HomeGalleryState(
            visibleIds: _mobileLayout.order.toSet(),
            campusCardStyle: _mobileLayout.campusCardStyle,
          );
  }

  void _enterEditMode(bool isBento) {
    _syncGalleryNotifier(isBento);
    if (mounted) {
      setState(() => _isEditing = true);
    }
  }

  void _exitEditMode() {
    if (!mounted || !_isEditing) return;
    setState(() => _isEditing = false);
  }

  void _updateMobileLayout(HomeMobileLayout next) {
    if (next == _mobileLayout) return;
    setState(() => _mobileLayout = next);
    _syncGalleryNotifier(false);
    unawaited(_storage.setHomeMobileLayout(next));
  }

  void _updateDesktopLayout(HomeDesktopLayout next) {
    if (next == _desktopLayout) return;
    setState(() => _desktopLayout = next);
    _syncGalleryNotifier(true);
    unawaited(_storage.setHomeDesktopLayout(next));
  }

  void _onMobileReorderStart(int index) {
    unawaited(AppHaptics.play(AppHaptics.tabHold));
    // Defer entering Edit Mode until the overlay proxy unmounts after drop so
    // the pinned edit bar & card chrome never jump the list mid-gesture.
    _pendingEditAfterMobileDrag = !_isEditing;
    _mobileDragEndedNaturally = false;
  }

  void _onMobileReorderEnd(int index) {
    _mobileDragEndedNaturally = true;
  }

  void _handleMobileDragProxyDisposed() {
    final shouldEnterEdit =
        _pendingEditAfterMobileDrag && _mobileDragEndedNaturally;
    _pendingEditAfterMobileDrag = false;
    _mobileDragEndedNaturally = false;
    if (!shouldEnterEdit || !mounted || _isEditing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isEditing) return;
      final isBento =
          MediaQuery.sizeOf(context).width >= TpTokens.bentoBreakpoint;
      if (!isBento) {
        _enterEditMode(false);
      }
    });
  }

  Widget _buildMobileReorderProxy(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    final id = (index >= 0 && index < _mobileLayout.order.length)
        ? _mobileLayout.order[index]
        : null;
    return HomeMobileDragProxy(
      key: id == null ? null : ValueKey('home.mobile-drag-proxy-${id.key}'),
      animation: animation,
      onDisposed: _handleMobileDragProxyDisposed,
      child: child,
    );
  }

  void _onMobileReorder(int oldIndex, int newIndex) {
    final next = _mobileLayout.reorder(oldIndex, newIndex);
    if (next == _mobileLayout) return;
    unawaited(AppHaptics.play(AppHaptics.selection));
    _updateMobileLayout(next);
  }

  void _setCampusCardStyle(
    HomeCampusCardStyle style, {
    required bool isBento,
  }) {
    if (isBento) {
      _updateDesktopLayout(_desktopLayout.copyWith(campusCardStyle: style));
    } else {
      _updateMobileLayout(_mobileLayout.copyWith(campusCardStyle: style));
    }
  }

  void _removeWidget(
    HomeWidgetId id, {
    required bool isBento,
    bool showFeedback = true,
  }) {
    final previousMobile = _mobileLayout;
    final previousDesktop = _desktopLayout;
    if (isBento) {
      final next = _desktopLayout.removeWidget(id);
      if (next == _desktopLayout) return;
      _updateDesktopLayout(next);
    } else {
      final next = _mobileLayout.removeWidget(id);
      if (next == _mobileLayout) return;
      _updateMobileLayout(next);
    }
    if (!showFeedback) return;
    showAdaptiveFeedback(
      context: context,
      message: '已移除「${homeWidgetMetaFor(id).title}」',
      actionLabel: '撤销',
      onAction: () {
        if (!mounted) return;
        if (isBento) {
          _updateDesktopLayout(previousDesktop);
        } else {
          _updateMobileLayout(previousMobile);
        }
      },
    );
  }

  void _addWidget(HomeWidgetId id, {required bool isBento}) {
    if (isBento) {
      _updateDesktopLayout(_desktopLayout.addWidget(id));
    } else {
      _updateMobileLayout(_mobileLayout.addWidget(id));
    }
  }

  void _resetLayout(bool isBento) {
    final previousMobile = _mobileLayout;
    final previousDesktop = _desktopLayout;
    if (isBento) {
      final defaults = HomeDesktopLayout.defaults();
      if (defaults == _desktopLayout) return;
      _updateDesktopLayout(defaults);
    } else {
      final defaults = HomeMobileLayout.defaults();
      if (defaults == _mobileLayout) return;
      _updateMobileLayout(defaults);
    }
    showAdaptiveFeedback(
      context: context,
      message: '已恢复默认主页布局',
      actionLabel: '撤销',
      onAction: () {
        if (!mounted) return;
        if (isBento) {
          _updateDesktopLayout(previousDesktop);
        } else {
          _updateMobileLayout(previousMobile);
        }
      },
    );
  }

  void _openWidgetGallery(bool isBento) {
    _syncGalleryNotifier(isBento);
    unawaited(
      showHomeWidgetGallery(
        context: context,
        stateListenable: _galleryState,
        onAddWidget: (id) => _addWidget(id, isBento: isBento),
        onRemoveWidget: (id) =>
            _removeWidget(id, isBento: isBento, showFeedback: false),
        onChangeCampusCardStyle: (style) =>
            _setCampusCardStyle(style, isBento: isBento),
        onResetDefaults: () => _resetLayout(isBento),
      ),
    );
  }

  Future<void> _openMoreCampusServices(StorageService storage) async {
    final inDesktopShell = usesDesktopSidebarShell(context) &&
        context.findAncestorWidgetOfExactType<DesktopShell>() != null;
    if (inDesktopShell) {
      appShellPendingTab.value = AppShell.campusServicesTabIndex;
      return;
    }
    context
        .getInheritedWidgetOfExactType<ServiceProvider>()
        ?.telemetry
        ?.featureOpened('campus_services');
    await pushAdaptivePage<void>(
      context,
      builder: (_) => CampusServicesPage(storage: storage),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openQuickActionsEditor(StorageService storage) async {
    await pushAdaptivePage<void>(
      context,
      builder: (_) => HomeShortcutEditorPage(storage: storage),
    );
    if (mounted) setState(() {});
  }

  void _onQuickShortcutsChanged() {
    if (mounted) setState(() {});
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

  static String _resolvedName(
    AuthService auth,
    ThirdPartyAuthService tpAuth,
    CampusCardService campusCard,
  ) {
    if (!auth.isLoggedIn || auth.session == null) return '';
    return resolveUserDisplayName(
      session: auth.session,
      idsRealName: tpAuth.idsAccount?.name,
      campusCardOwnerName: campusCard.cachedOwnerName,
    );
  }

  static String _greetingTitle(
    DateTime now,
    AuthService auth,
    ThirdPartyAuthService tpAuth,
    CampusCardService campusCard,
  ) {
    final base = _greeting(now);
    final name = _resolvedName(auth, tpAuth, campusCard);
    if (name.isEmpty) return base;
    return '$base，$name';
  }

  static String _avatarLabel(
    AuthService auth,
    ThirdPartyAuthService tpAuth,
    CampusCardService campusCard,
  ) {
    final name = _resolvedName(auth, tpAuth, campusCard);
    return userAvatarLabel(name);
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
    final tpAuth = sp.thirdPartyAuthService;
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

    final showHeaderAvatar = !(usesDesktopSidebarShell(context) &&
        context.findAncestorWidgetOfExactType<DesktopShell>() != null);

    final header = TpPageHeader(
      key: const ValueKey('home.greeting-header'),
      subtitle: dateSubtitle,
      subtitleWidget: showHeaderAvatar
          ? Row(
              key: const ValueKey('home.brand-bar'),
              children: [
                const TpBrandMark(size: 15),
                const SizedBox(width: 5),
                Text(
                  'TechPie',
                  style: TpTypography.pageSubtitle(colors).copyWith(
                    fontFamily: TpBrandWordmark.brandFontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                    color: colors.textPrimary,
                  ),
                ),
                Flexible(
                  child: Text(
                    ' · $dateSubtitle',
                    style: TpTypography.pageSubtitle(colors),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : null,
      title: _greetingTitle(now, auth, tpAuth, campusCard),
      trailing: _isEditing
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HomeHeaderEditButton(
                  key: const ValueKey('home.edit-toggle'),
                  onPressed: () => _enterEditMode(isBento),
                ),
                if (showHeaderAvatar) ...[
                  const SizedBox(width: TpTokens.space1),
                  TpAvatarBadge(
                    key: const ValueKey('home.avatar'),
                    text: _avatarLabel(auth, tpAuth, campusCard),
                    tooltip: auth.isLoggedIn ? '我的' : '登录',
                    onTap: () {
                      if (auth.isLoggedIn) {
                        appShellPendingTab.value = 3;
                      } else {
                        unawaited(startUniAuthLogin(context));
                      }
                    },
                  ),
                ],
              ],
            ),
    );
    final effectiveCardStyle = isBento
        ? _desktopLayout.campusCardStyle
        : _mobileLayout.campusCardStyle;

    final showMobileGlanceRow = !isBento &&
        !_isEditing &&
        auth.isLoggedIn &&
        _todayCourses.isEmpty &&
        _mobileLayout.order.contains(HomeWidgetId.deadlines);

    Widget buildWidgetCard(HomeWidgetId id) => switch (id) {
          HomeWidgetId.campusCard => _buildCampusCardStrip(
              campusCard,
              storage,
              expandedCard: effectiveCardStyle == HomeCampusCardStyle.full,
            ),
          HomeWidgetId.todayCourses => showMobileGlanceRow
              ? _buildMobileGlanceRow(colors)
              : _buildTodayClasses(colors, auth.isLoggedIn),
          HomeWidgetId.deadlines => _buildPendingAssignments(colors),
          HomeWidgetId.quickActions => _buildQuickActions(),
          _ => buildCampusServiceHomeWidget(
              context,
              id,
              todayCourses: _todayCourses,
            ),
        };

    final debugPanel = isDebug ? _buildDebugPanel(colors) : null;
    final maxBodyWidth = isBento ? 1120.0 : TpTokens.singleColumnMaxWidth;
    final isLayoutEmpty =
        isBento ? _desktopLayout.isEmpty : _mobileLayout.isEmpty;

    return PopScope(
      canPop: !_isEditing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isEditing) {
          _exitEditMode();
        }
      },
      child: Scaffold(
        backgroundColor: colors.canvas,
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sidePad = math.max(
                horizontalPadding,
                (constraints.maxWidth - maxBodyWidth) / 2,
              );
              final topPad = isBento ? TpTokens.space5 : TpTokens.space3;
              final bottomPad = AppShellMetrics.bottomContentPaddingOf(context);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isEditing)
                    Padding(
                      key: const ValueKey('home.edit-bar-slot'),
                      padding: EdgeInsets.fromLTRB(
                        sidePad,
                        topPad,
                        sidePad,
                        TpTokens.space2,
                      ),
                      child: _HomeEditBar(
                        isBento: isBento,
                        onOpenGallery: () => _openWidgetGallery(isBento),
                        onDone: _exitEditMode,
                      ),
                    ),
                  Expanded(
                    key: const ValueKey('home.scroll-body'),
                    child: PageRefreshIndicator(
                      onRefresh: _refreshHome,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              sidePad,
                              _isEditing ? TpTokens.space1 : topPad,
                              sidePad,
                              0,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  header,
                                  SizedBox(
                                    height: isBento
                                        ? TpTokens.space4
                                        : TpTokens.sectionGap,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      if (isLayoutEmpty)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            sidePad,
                            0,
                            sidePad,
                            debugPanel != null ? TpTokens.sectionGap : bottomPad,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: TpStateCard.empty(
                              key: const ValueKey('home.empty-widgets'),
                              icon: TpIcons.dashboard,
                              title: '主页暂无组件',
                              message: '可从组件库重新添加所需模块，或一键恢复默认布局。',
                              primaryActionLabel: '添加组件',
                              primaryActionIcon: TpIcons.add,
                              primaryActionSfSymbol: 'plus',
                              onPrimaryAction: () => _openWidgetGallery(isBento),
                              secondaryActionLabel: '恢复默认',
                              secondaryActionIcon: TpIcons.reset,
                              secondaryActionSfSymbol: 'arrow.counterclockwise',
                              onSecondaryAction: () => _resetLayout(isBento),
                            ),
                          ),
                        )
                      else if (isBento)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            sidePad,
                            0,
                            sidePad,
                            bottomPad,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: HomeBentoEditor(
                              layout: _desktopLayout,
                              isEditing: _isEditing,
                              cardBuilder: buildWidgetCard,
                              onMoveToSlot: (id, col, slot) =>
                                  _updateDesktopLayout(
                                _desktopLayout.moveToSlot(id, col, slot),
                              ),
                              onMoveBy: (id, delta) => _updateDesktopLayout(
                                _desktopLayout.moveBy(id, delta),
                              ),
                              onSwapColumn: (id) => _updateDesktopLayout(
                                _desktopLayout.swapColumn(id),
                              ),
                              onRemove: (id) => _removeWidget(id, isBento: true),
                              onEnterEditMode: () => _enterEditMode(true),
                              onCampusCardStyleChanged: (style) =>
                                  _setCampusCardStyle(style, isBento: true),
                              onConfigureQuickActions: () =>
                                  _openQuickActionsEditor(storage),
                              footerWidget: debugPanel,
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            sidePad,
                            0,
                            sidePad,
                            debugPanel != null ? 0 : bottomPad,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: HomeMobileReorderList(
                              itemCount: _mobileLayout.order.length,
                              onReorder: _onMobileReorder,
                              onReorderStart: _onMobileReorderStart,
                              onReorderEnd: _onMobileReorderEnd,
                              proxyDecorator: _buildMobileReorderProxy,
                              itemBuilder: (context, index) {
                              final id = _mobileLayout.order[index];
                              final isLast =
                                  index == _mobileLayout.order.length - 1;
                              return Padding(
                                key: ValueKey('home.mobile-item-${id.key}'),
                                padding: EdgeInsets.only(
                                  bottom: isLast ? 0 : TpTokens.sectionGap,
                                ),
                                child: HomeEditableCardFrame(
                                  id: id,
                                  index: index,
                                  itemCount: _mobileLayout.order.length,
                                  isEditing: _isEditing,
                                  isDesktopMode: false,
                                  enableReorderDragHandle: _isEditing,
                                  campusCardStyle:
                                      id == HomeWidgetId.campusCard
                                          ? _mobileLayout.campusCardStyle
                                          : null,
                                  onCampusCardStyleChanged: (style) =>
                                      _setCampusCardStyle(
                                    style,
                                    isBento: false,
                                  ),
                                  onConfigureQuickActions:
                                      id == HomeWidgetId.quickActions
                                          ? () =>
                                              _openQuickActionsEditor(storage)
                                          : null,
                                  onEnterEditMode: () => _enterEditMode(false),
                                  onRemove: () =>
                                      _removeWidget(id, isBento: false),
                                  child: buildWidgetCard(id),
                                ),
                              );
                            },
                            ),
                          ),
                        ),
                      if (debugPanel != null && (!isBento || isLayoutEmpty))
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            sidePad,
                            TpTokens.sectionGap,
                            sidePad,
                            bottomPad,
                          ),
                          sliver: SliverToBoxAdapter(child: debugPanel),
                        ),
                    ],
                  ),
                ),
              ),
                ],
              );
            },
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
        );
      },
    );
  }

  Widget _buildQuickActions() {
    final storage = ServiceProvider.of(context).storageService;
    return TpCard(
      key: const ValueKey('home.quick-actions'),
      title: '快捷功能',
      child: AppCard(
        features: [...homeQuickFeatures(storage.pinnedQuickFeatureIds), moreFeature],
        rows: 2,
        columns: 3,
        onFeatureTap: (feature) async {
          if (feature != moreFeature) {
            await openCampusFeature(context, feature);
            return;
          }
          await _openMoreCampusServices(storage);
        },
      ),
    );
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
        useBrandAccent: true,
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

  static DateTime _activeDueOf(Assignment a, DateTime now) =>
      (a.effectiveLateDue != null && a.due.isBefore(now))
          ? a.effectiveLateDue!
          : a.due;

  List<Assignment> _activePendingAssignments(DateTime now) {
    return _assignments.visibleAssignments
        .where(
          (a) =>
              !_assignments.isCompleted(a) &&
              !a.isExpiredAt(now) &&
              (!a.canBeOverdue || !a.effectiveDue.isBefore(now)),
        )
        .toList()
      ..sort((a, b) => _activeDueOf(a, now).compareTo(_activeDueOf(b, now)));
  }

  Widget _buildMobileGlanceRow(TpColors colors) {
    final now = _now;
    final pending = _activePendingAssignments(now);
    final urgentCount = pending.where((a) {
      final isExamInProgress = a is ExamAssignment && a.isInProgressAt(now);
      final inLateWindow = a.effectiveLateDue != null && a.due.isBefore(now);
      final due = inLateWindow ? a.effectiveLateDue! : a.due;
      return isExamInProgress ||
          inLateWindow ||
          due.difference(now).inHours < 24;
    }).length;

    final String statusText;
    if (urgentCount > 0) {
      statusText = '$urgentCount 项 <24h';
    } else if (pending.isEmpty) {
      statusText = '全部完成';
    } else {
      final nearest = _dueLabel(_activeDueOf(pending.first, now), now)
          .replaceFirst('剩余 ', '');
      statusText = '最近 $nearest';
    }

    final metaStyle = TpTypography.cardMeta(colors);
    final unitStyle = metaStyle.copyWith(color: colors.textSecondary);
    final countStyle = TpTypography.numericDisplay(colors).copyWith(fontSize: 24);

    final todayTile = TpCard(
      onTap: () => appShellPendingTab.value = 1,
      padding: const EdgeInsets.all(TpTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('今日课程', style: metaStyle, maxLines: 1),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('0', style: countStyle),
              const SizedBox(width: 3),
              Text('节', style: unitStyle),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '休息日',
            style: metaStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    final deadlinesTile = TpCard(
      key: const ValueKey('home.deadlines-glance'),
      onTap: () => appShellPendingDeadlines.value = true,
      padding: const EdgeInsets.all(TpTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Deadlines', style: metaStyle, maxLines: 1),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${pending.length}', style: countStyle),
              const SizedBox(width: 3),
              Text('项', style: unitStyle),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            style: metaStyle.copyWith(
              color: urgentCount > 0 ? colors.dangerRed : colors.textMuted,
              fontWeight: urgentCount > 0 ? FontWeight.w600 : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return IntrinsicHeight(
      key: const ValueKey('home.today-courses'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: todayTile),
          const SizedBox(width: TpTokens.sectionGap),
          Expanded(child: deadlinesTile),
        ],
      ),
    );
  }

  Widget _buildPendingAssignments(TpColors colors) {
    final now = _now;
    final pending = _activePendingAssignments(now);

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

  static String _formatPlatformLabel(String raw) => switch (raw.toLowerCase()) {
        'blackboard' => 'Blackboard',
        'gradescope' => 'Gradescope',
        'hydro' => 'Hydro',
        'custom' => '自定义',
        _ => raw,
      };

  Widget _buildPendingItem(
    TpColors colors,
    Assignment a,
    DateTime now, {
    required bool showDivider,
  }) {
    final isExamInProgress = a is ExamAssignment && a.isInProgressAt(now);
    final inLateWindow = a.effectiveLateDue != null && a.due.isBefore(now);
    final activeDue = inLateWindow ? a.effectiveLateDue! : a.due;
    final visuals = _dueVisuals(
      activeDue,
      now,
      colors,
      forceUrgent: isExamInProgress || inLateWindow,
    );
    final dueLabel = isExamInProgress
        ? '考试中'
        : (inLateWindow
            ? '迟交${_dueLabel(activeDue, now)}'
            : _dueLabel(activeDue, now));
    final progress = (isExamInProgress || inLateWindow)
        ? 1.0
        : _urgencyProgress(activeDue, now);
    final detail = switch (a) {
      ExamAssignment(:final location) => location.trim(),
      CustomDeadline(:final course, :final location) => [
          if (course.isNotEmpty) course,
          if (location.isNotEmpty) location,
        ].join(' · '),
      _ => [
          if (a.platform.isNotEmpty) _formatPlatformLabel(a.platform),
          if (a.course.isNotEmpty) a.course,
        ].join(' · '),
    };

    return TpProgressRow(
      title: a.title,
      subtitle: detail,
      trailingLabel: dueLabel,
      progress: progress,
      color: visuals.barColor,
      trailingColor: visuals.trailingColor,
      highlightTrailing: visuals.highlightTrailing,
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

  static ({Color barColor, Color trailingColor, bool highlightTrailing})
      _dueVisuals(
    DateTime due,
    DateTime now,
    TpColors colors, {
    bool forceUrgent = false,
  }) {
    final diff = due.difference(now);
    if (forceUrgent || diff.inHours < 24) {
      return (
        barColor: colors.dangerRed,
        trailingColor: colors.dangerRed,
        highlightTrailing: true,
      );
    }
    if (diff.inDays < 3) {
      return (
        barColor: colors.warningAmber,
        trailingColor: colors.warningAmber,
        highlightTrailing: false,
      );
    }
    return (
      barColor: colors.textPrimary.withValues(alpha: colors.isDark ? 0.30 : 0.28),
      trailingColor: colors.textMuted,
      highlightTrailing: false,
    );
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
    bool useBrandAccent = false,
    Widget? leading,
    String? actionLabel,
    String? actionSfSymbol,
    VoidCallback? onTap,
    Widget? footer,
  }) {
    final resolvedBadge = leading ??
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: useBrandAccent ? colors.brandSoft : colors.surfaceSubtle,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: TpTokens.iconS + 1,
            color: useBrandAccent ? colors.brandInk : colors.textMuted,
          ),
        );

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
              resolvedBadge,
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
                        child: AdaptiveSlider(
                          value: minutes,
                          min: 0,
                          max: 1439,
                          divisions: 1439,
                          semanticLabel: 'Time of day',
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

class _HomeHeaderEditButton extends StatelessWidget {
  const _HomeHeaderEditButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    const label = '定制主页';

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: TpPressScale(
              pressedScale: 0.92,
              child: Material(
                color: colors.textPrimary.withValues(
                  alpha: colors.isDark ? 0.08 : 0.055,
                ),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: TpTapSurface(
                  style: TpTapFeedbackStyle.button,
                  customBorder: const CircleBorder(),
                  enablePressScale: false,
                  onTap: onPressed,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      TpIcons.dashboard,
                      size: TpTokens.iconS,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeEditBar extends StatelessWidget {
  const _HomeEditBar({
    required this.isBento,
    required this.onOpenGallery,
    required this.onDone,
  });

  final bool isBento;
  final VoidCallback onOpenGallery;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return TpCard(
      key: const ValueKey('home.edit-bar'),
      padding: const EdgeInsets.symmetric(
        horizontal: TpTokens.space3,
        vertical: TpTokens.space2,
      ),
      child: Row(
        children: [
          Icon(TpIcons.dashboard, size: TpTokens.iconS, color: colors.brandInk),
          const SizedBox(width: TpTokens.space2),
          Expanded(
            child: isBento
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '编辑主页',
                        style: TpTypography.itemTitle(colors)
                            .copyWith(fontSize: 13.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '拖动卡片调整栏位与顺序',
                        style: TpTypography.itemMeta(colors),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  )
                : Text(
                    '编辑主页',
                    style: TpTypography.itemTitle(colors)
                        .copyWith(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const SizedBox(width: TpTokens.space2),
          _HomeEditPillButton(
            key: const ValueKey('home.open-gallery'),
            icon: TpIcons.add,
            label: '组件',
            onTap: onOpenGallery,
          ),
          const SizedBox(width: TpTokens.space2),
          _HomeEditPillButton(
            key: const ValueKey('home.edit-done'),
            label: '完成',
            primary: true,
            onTap: onDone,
          ),
        ],
      ),
    );
  }
}

class _HomeEditPillButton extends StatelessWidget {
  const _HomeEditPillButton({
    super.key,
    this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final fg = primary ? colors.onBrand : colors.textPrimary;
    final bg = primary ? colors.brandInk : colors.surfaceSubtle;

    return Semantics(
      button: true,
      label: label,
      child: TpPressScale(
        pressedScale: 0.94,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(TpTokens.radiusPill),
          clipBehavior: Clip.antiAlias,
          child: TpTapSurface(
            style: TpTapFeedbackStyle.button,
            borderRadius: BorderRadius.circular(TpTokens.radiusPill),
            pressedColor: primary ? colors.onBrand : null,
            enablePressScale: false,
            onTap: () {
              unawaited(AppHaptics.play(AppHaptics.lightImpact));
              onTap();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TpTokens.space3,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 13, color: fg),
                      const SizedBox(width: TpTokens.space1),
                    ],
                    Text(label, style: TpTypography.badge(fg)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
