import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/course.dart';
import '../models/course_table.dart';
import '../services/calendar/calendar_importer.dart';
import '../services/ics/ics_export_service.dart';
import '../services/ics/ics_file_saver.dart';
import '../services/schedule_service.dart';
import '../services/service_provider.dart';
import '../utils/adaptive_layout.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_text_input_dialog.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/course_detail_panel.dart';
import '../widgets/desktop_popup.dart';
import '../widgets/desktop_select_popover.dart';
import '../widgets/ios_liquid/ios_glass_button.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import '../widgets/ios_liquid/ios_platform_view_page_transitions.dart';
import 'login_page.dart';
import 'third_party_accounts_page.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final IcsExportService _icsExport = IcsExportService();
  late ScheduleService _schedule;
  List<Course> _courses = [];
  List<Period> _periods = defaultPeriods.toList();
  int _currentWeek = 1;
  bool _initialized = false;
  bool _exportingCalendar = false;

  // Settings
  bool _showSaturday = true;
  bool _showSunday = true;
  bool _showGhostCourses = false;

  // Animation: track slide direction for week transitions
  // 1 = forward (next week), -1 = backward (previous week), 0 = no slide
  int _slideDirection = 0;
  final PageController _weekPageController = PageController();
  final GlobalKey _viewSettingsAnchorKey = GlobalKey();

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
    _weekPageController.dispose();
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
    if (!auth.isLoggedIn) return;
    await _schedule.fetchAll();
    if (!mounted) return;
    final hasError = _schedule.error != null;
    showAdaptiveFeedback(
      context: context,
      message: hasError ? '刷新失败' : '已刷新',
      style: hasError
          ? AdaptiveFeedbackStyle.error
          : AdaptiveFeedbackStyle.success,
      duration: const Duration(seconds: 2),
    );
  }

  void _rebuildCourses() {
    if (!mounted) return;
    setState(() {
      _currentWeek = _schedule.currentWeek().clamp(1, 25).toInt();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_weekPageController.hasClients) return;
      _weekPageController.jumpToPage(_currentWeek - 1);
    });
  }

  void _previousWeek() {
    _setWeek(_currentWeek - 1);
  }

  void _nextWeek() {
    _setWeek(_currentWeek + 1);
  }

  void _goToCurrentWeek() {
    final computedWeek = _schedule.currentWeek().clamp(1, 25).toInt();

    _setWeek(computedWeek);
  }

  void _setWeek(int week) {
    _setCurrentWeek(week);
    if (!_weekPageController.hasClients) return;
    unawaited(
      _weekPageController.animateToPage(
        _currentWeek - 1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _setCurrentWeek(int week) {
    final old = _currentWeek;
    setState(() {
      _currentWeek = week.clamp(1, 25).toInt();
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

  List<Course> _coursesForWeek(int week) {
    final table = _schedule.courseTable;
    if (table == null) return const [];

    return eamsToDisplayCourses(
      table.courses,
      week.clamp(1, 25).toInt(),
      includeGhosts: _showGhostCourses,
    );
  }

  DateTime _weekStartForWeek(int week) {
    final termBegin = _schedule.termBegin;
    if (termBegin != null) {
      final weekStartDate = termBegin.add(
        Duration(days: (week.clamp(1, 25).toInt() - 1) * 7),
      );
      return weekStartDate.subtract(Duration(days: weekStartDate.weekday - 1));
    }
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  void _showSemesterPicker() {
    final info = _schedule.semesterInfo;
    if (info == null) return;
    final allSemesters = info.allSemesters;
    if (allSemesters.isEmpty) return;

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return ListView(
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
                  leading: Radio<String>(
                    value: entry.key,
                    groupValue: _schedule.selectedSemesterId,
                    onChanged: (value) {
                      Navigator.pop(context);
                      if (value != null) {
                        unawaited(_schedule.selectSemester(value));
                      }
                    },
                  ),
                  title: Text(entry.value),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_schedule.selectSemester(entry.key));
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  void _showWeekPicker() {
    // Desktop is handled directly by _DesktopWeekTitleMenu.
    if (usesSidebarLayout(context)) return;

    final computedWeek = _schedule.currentWeek().clamp(1, 25).toInt();

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          final sheetTheme = Theme.of(context);

          return StatefulBuilder(
            builder: (context, setModalState) {
              final isViewingCurrentWeek = _currentWeek == computedWeek;

              void selectWeek(int week) {
                _setWeek(week);
                setModalState(() {});
                Navigator.pop(context);
              }

              void goToCurrentWeek() {
                _setWeek(computedWeek);
                setModalState(() {});
                Navigator.pop(context);
              }

              return SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '选择周数',
                              style: sheetTheme.textTheme.titleLarge,
                            ),
                          ),
                          if (!isViewingCurrentWeek)
                            FilledButton.tonalIcon(
                              onPressed: goToCurrentWeek,
                              icon: const Icon(Icons.today_outlined, size: 18),
                              label: const Text('回到本周'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: 25,
                          itemBuilder: (context, index) {
                            final week = index + 1;
                            final selected = week == _currentWeek;
                            final isActualCurrentWeek = week == computedWeek;

                            return ListTile(
                              selected: selected,
                              leading: selected
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: sheetTheme.colorScheme.primary,
                                    )
                                  : const SizedBox(width: 24),
                              title: Text('第 $week 周'),
                              subtitle:
                                  isActualCurrentWeek ? const Text('本周') : null,
                              onTap: () => selectWeek(week),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  List<int> get _visibleDayIndices {
    final days = <int>[1, 2, 3, 4, 5];
    if (_showSaturday) days.add(6);
    if (_showSunday) days.add(7);
    return days;
  }

  String get _semesterLabel {
    final info = _schedule.semesterInfo;
    final id = _schedule.selectedSemesterId;
    if (info != null && id != null) {
      return info.findSemesterLabel(id) ?? '';
    }
    return '';
  }

  String get _icsFileName {
    final semesterId = _schedule.selectedSemesterId ?? 'schedule';
    final safe = semesterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'course_table_$safe.ics';
  }

  String get _defaultCalendarName =>
      _semesterLabel.isEmpty ? '课程表' : _semesterLabel;

  void _startExportCalendar() {
    if (_exportingCalendar) return;
    unawaited(_exportCalendar());
  }

  Future<SavedIcsFile> _saveCalendarFile(
    IcsSaveLocation location, {
    required String calendarName,
  }) {
    final table = _schedule.courseTable!;
    final termBegin = _schedule.termBegin!;
    return _icsExport.saveCalendar(
      table: table,
      termBegin: termBegin,
      fileName: _icsFileName,
      location: location,
      calendarName: calendarName,
    );
  }

  Future<void> _exportCalendar() async {
    final table = _schedule.courseTable;
    final termBegin = _schedule.termBegin;
    if (table == null || termBegin == null || _exportingCalendar) return;

    final calendarName = (isIos() || isAndroid())
        ? await _promptCalendarName(initialValue: _defaultCalendarName)
        : _defaultCalendarName;
    if (calendarName == null || calendarName.trim().isEmpty) return;

    setState(() {
      _exportingCalendar = true;
    });
    await WidgetsBinding.instance.endOfFrame;

    try {
      if (isIos() || isAndroid()) {
        try {
          final events = await _icsExport.buildCalendarEventPayloads(
            table: table,
            termBegin: termBegin,
          );
          final imported = await CalendarImporter.importCalendarEvents(
            events,
            calendarName: calendarName,
          );
          if (!mounted) return;
          showAdaptiveFeedback(
            context: context,
            message:
                imported > 0 ? '已导入 $imported 个日程到“$calendarName”' : '没有可导入的日程',
            style: imported > 0
                ? AdaptiveFeedbackStyle.success
                : AdaptiveFeedbackStyle.info,
          );
          return;
        } catch (_) {
          final fallbackFile = await _saveCalendarFile(
            IcsSaveLocation.downloads,
            calendarName: calendarName,
          );
          if (!mounted) return;
          showAdaptiveFeedback(
            context: context,
            message: fallbackFile.filePath != null
                ? '导入失败，已导出到下载目录: ${fallbackFile.filePath}'
                : '导入失败，ICS 文件已创建。',
            style: AdaptiveFeedbackStyle.info,
          );
          return;
        }
      }

      final saved = await _saveCalendarFile(
        IcsSaveLocation.temporary,
        calendarName: calendarName,
      );

      bool launched = false;
      if (saved.filePath != null) {
        try {
          final result = await OpenFilex.open(
            saved.filePath!,
            type: 'text/calendar',
          );
          launched = result.type == ResultType.done;
        } catch (e) {
          launched = false;
        }
      }

      if (!launched && saved.launchUri != null) {
        try {
          launched = await launchUrl(
            saved.launchUri!,
            mode: LaunchMode.externalApplication,
          );
        } catch (e) {
          launched = false;
        }
      }

      if (!launched && mounted) {
        SavedIcsFile fallbackFile = saved;
        try {
          fallbackFile = await _saveCalendarFile(
            IcsSaveLocation.downloads,
            calendarName: calendarName,
          );
        } catch (_) {
          fallbackFile = saved;
        }
        if (!mounted) return;

        showAdaptiveFeedback(
          context: context,
          message: fallbackFile.filePath != null
              ? '已导出到下载目录: ${fallbackFile.filePath}'
              : 'ICS 文件已创建。',
          style: AdaptiveFeedbackStyle.info,
        );
        return;
      }

      if (!mounted) return;
      showAdaptiveFeedback(
        context: context,
        message: '课表导出操作成功',
        style: AdaptiveFeedbackStyle.success,
      );
    } catch (_) {
      if (!mounted) return;
      showAdaptiveFeedback(
        context: context,
        message: '导出课表失败',
        style: AdaptiveFeedbackStyle.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingCalendar = false;
        });
      }
    }
  }

  Future<String?> _promptCalendarName({required String initialValue}) async {
    return showAdaptiveTextInputDialog(
      context: context,
      title: '请输入日历名称',
      fieldLabel: '日历名',
      hintText: '例如：2025-2026 春季学期',
      initialValue: initialValue,
      confirmLabel: '导入',
      trimResult: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final tpAuth = sp.thirdPartyAuthService;
    final actualCurrentWeek = _schedule.currentWeek().clamp(1, 25).toInt();
    final isViewingCurrentWeek = _currentWeek == actualCurrentWeek;
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: '第 $_currentWeek 周',
              subtitle: _semesterLabel.isEmpty ? null : _semesterLabel,
              largeTitleMode: true,
              trailingItems: [
                IosNativeNavigationBarItem(
                  id: 'settings',
                  sfSymbol: 'ellipsis',
                  accessibilityLabel: '视图设置',
                  menuItems: [
                    IosNativeNavigationBarMenuItem(
                      value: 'semester',
                      title: '切换学期',
                      children: [
                        for (final entry
                            in _schedule.semesterInfo?.allSemesters ??
                                const <MapEntry<String, String>>[])
                          IosNativeNavigationBarMenuItem(
                            value: 'semester:${entry.key}',
                            title: entry.value,
                            checked: _schedule.selectedSemesterId == entry.key,
                          ),
                      ],
                    ),
                    IosNativeNavigationBarMenuItem(
                      value: 'saturday',
                      title: '显示周六',
                      checked: _showSaturday,
                    ),
                    IosNativeNavigationBarMenuItem(
                      value: 'sunday',
                      title: '显示周日',
                      checked: _showSunday,
                    ),
                    IosNativeNavigationBarMenuItem(
                      value: 'ghost',
                      title: '显示非本周课程',
                      checked: _showGhostCourses,
                    ),
                    IosNativeNavigationBarMenuItem(
                      value: '__export_section__',
                      title: '',
                      displayInline: true,
                      children: [
                        IosNativeNavigationBarMenuItem(
                          value: 'exportCalendar',
                          title: _exportingCalendar ? '正在导出…' : '导出课表',
                          sfSymbol: _exportingCalendar
                              ? 'arrow.triangle.2.circlepath'
                              : 'square.and.arrow.up',
                        ),
                      ],
                    ),
                  ],
                ),
                IosNativeNavigationBarItem(
                  id: 'currentWeek',
                  sfSymbol: 'calendar.badge.clock',
                  hidden: isViewingCurrentWeek,
                  accessibilityLabel: '回到本周',
                  placementGroup: 'week-actions',
                ),
              ],
              onItemPressed: (id) {
                if (id == 'currentWeek') {
                  _goToCurrentWeek();
                }
              },
              onMenuSelected: (_, value) => _onMenuSelected(value),
            )
          : BlurredAppBar(
              titleSpacing: 16,
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (usesSidebarLayout(context))
                    _DesktopWeekTitleMenu(
                      currentWeek: _currentWeek,
                      semesterLabel: _semesterLabel,
                      slideDirection: _slideDirection,
                      onWeekChanged: _setWeek,
                    )
                  else
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _showWeekPicker,
                      child: _WeekTitleContent(
                        currentWeek: _currentWeek,
                        semesterLabel: _semesterLabel,
                        slideDirection: _slideDirection,
                        trailingIcon: Icons.unfold_more,
                      ),
                    ),
                  if (usesSidebarLayout(context) && !isViewingCurrentWeek) ...[
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: _goToCurrentWeek,
                      icon: const Icon(Icons.today_outlined, size: 18),
                      label: const Text('回到本周'),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
              actions: [
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
                IconButton(
                  tooltip: _exportingCalendar ? '正在导出课表' : '导出课表',
                  onPressed: _exportingCalendar ? null : _startExportCalendar,
                  icon: _exportingCalendar
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_rounded),
                ),
                if (usesSidebarLayout(context))
                  IconButton(
                    key: _viewSettingsAnchorKey,
                    icon: const Icon(Icons.more_vert),
                    tooltip: '视图设置',
                    onPressed: _showViewSettingsMenu,
                  )
                else
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: '视图设置',
                    onSelected: _onMenuSelected,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'semester',
                        child: Text('切换学期'),
                      ),
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
      body: Padding(
        padding: EdgeInsets.only(
          top: useIosChrome || useLegacyIosChrome
              ? 0
              : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top,
        ),
        child: !auth.isLoggedIn || !tpAuth.hasEgateBinding
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
                      auth.isLoggedIn ? '绑定 eGate 以查看课表' : '登录以查看课表',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    IosGlassButton(
                      label: auth.isLoggedIn ? '去绑定 eGate' : '登录',
                      icon: auth.isLoggedIn
                          ? Icons.account_tree_outlined
                          : Icons.login,
                      sfSymbol: auth.isLoggedIn
                          ? 'person.crop.circle.badge.plus'
                          : 'person.crop.circle.badge.checkmark',
                      role: IosNativeButtonRole.prominent,
                      width: 220,
                      onPressed: () {
                        if (auth.isLoggedIn) {
                          unawaited(
                            pushPlatformViewPage<void>(
                              context,
                              builder: (_) => const ThirdPartyAccountsPage(),
                            ),
                          );
                        } else {
                          unawaited(presentLoginPage(context));
                        }
                      },
                      accessibilityLabel:
                          auth.isLoggedIn ? '绑定 eGate 账号' : '登录 TechPie',
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _refresh,
                child: useIosChrome
                    ? PageView.builder(
                        controller: _weekPageController,
                        itemCount: 25,
                        onPageChanged: (index) {
                          _setCurrentWeek(index + 1);
                        },
                        itemBuilder: (context, index) {
                          final week = index + 1;
                          return _buildScheduleWeek(
                            context,
                            theme,
                            today,
                            week,
                            _coursesForWeek(week),
                          );
                        },
                      )
                    : _buildScheduleWeek(
                        context,
                        theme,
                        today,
                        _currentWeek,
                        _courses,
                        animated: true,
                      ),
              ),
      ),
    );
  }

  Widget _buildScheduleWeek(
    BuildContext context,
    ThemeData theme,
    DateTime today,
    int week,
    List<Course> courses, {
    bool animated = false,
  }) {
    final visibleDays = _visibleDayIndices;
    final visibleCourses = courses
        .where((course) => visibleDays.contains(course.dayOfWeek))
        .toList();

    final content = visibleCourses.isEmpty
        ? ListView(
            key: ValueKey<String>('empty-$week'),
            children: [
              SizedBox(
                height: 300,
                child: Center(
                  child: Text(
                    '本周没有课程',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          )
        : _TimetableGrid(
            key: ValueKey<int>(week),
            courses: courses,
            periods: _periods,
            weekStart: _weekStartForWeek(week),
            today: today,
            visibleDays: visibleDays,
          );

    return Column(
      children: [
        _DayHeader(
          weekStart: _weekStartForWeek(week),
          today: today,
          visibleDays: visibleDays,
        ),
        const Divider(height: 1),
        Expanded(
          child: animated
              ? AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: content,
                )
              : content,
        ),
      ],
    );
  }

  void _onMenuSelected(String value) {
    if (value.startsWith('semester:')) {
      final semesterId = value.substring('semester:'.length);
      if (semesterId.isNotEmpty) {
        unawaited(_schedule.selectSemester(semesterId));
      }
      return;
    }

    switch (value) {
      case 'currentWeek':
        _goToCurrentWeek();
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
      case 'exportCalendar':
        _startExportCalendar();
    }
  }

  void _showViewSettingsMenu() {
    final anchorContext = _viewSettingsAnchorKey.currentContext;
    if (anchorContext == null) return;

    showDesktopPopover(
      anchorContext: anchorContext,
      width: 260,
      placement: DesktopPopoverPlacement.belowEnd,
      offset: const Offset(-12, 8),
      builder: (context, close) {
        final theme = Theme.of(context);
        return DesktopPopoverSurface(
          child: StatefulBuilder(
            builder: (context, setPopoverState) {
              void toggle(String value) {
                _onMenuSelected(value);
                setPopoverState(() {});
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Text('视图设置', style: theme.textTheme.titleSmall),
                  ),
                  const Divider(height: 1),
                  _DesktopSemesterSelectButton(
                    semesters: _schedule.semesterInfo?.allSemesters ?? const [],
                    selectedSemesterId: _schedule.selectedSemesterId,
                    onChanged: (semesterId) {
                      close();
                      unawaited(_schedule.selectSemester(semesterId));
                    },
                  ),
                  const Divider(height: 1),
                  DesktopMenuRow(
                    leading: Icon(
                      _showSaturday
                          ? Icons.check
                          : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    title: Text('显示周六', style: theme.textTheme.bodyMedium),
                    onTap: () => toggle('saturday'),
                  ),
                  DesktopMenuRow(
                    leading: Icon(
                      _showSunday ? Icons.check : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    title: Text('显示周日', style: theme.textTheme.bodyMedium),
                    onTap: () => toggle('sunday'),
                  ),
                  DesktopMenuRow(
                    leading: Icon(
                      _showGhostCourses
                          ? Icons.check
                          : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    title: Text('显示非本周课程', style: theme.textTheme.bodyMedium),
                    onTap: () => toggle('ghost'),
                  ),
                  const Divider(height: 1),
                  DesktopMenuRow(
                    leading: _exportingCalendar
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded, size: 20),
                    title: Text('导出课表', style: theme.textTheme.bodyMedium),
                    onTap: _exportingCalendar
                        ? null
                        : () {
                            close();
                            _startExportCalendar();
                          },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _DesktopSemesterSelectButton extends StatelessWidget {
  final List<MapEntry<String, String>> semesters;
  final String? selectedSemesterId;
  final ValueChanged<String> onChanged;

  const _DesktopSemesterSelectButton({
    required this.semesters,
    required this.selectedSemesterId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedId = selectedSemesterId;
    final currentValue =
        selectedId != null && semesters.any((entry) => entry.key == selectedId)
            ? selectedId
            : (semesters.isNotEmpty ? semesters.first.key : '');

    if (semesters.isEmpty || currentValue.isEmpty) {
      return DesktopMenuRow(
        leading: const Icon(Icons.swap_horiz, size: 20),
        title: Text('切换学期', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return DesktopSelectPopover<String>(
      items: semesters.map((entry) => entry.key).toList(growable: false),
      value: currentValue,
      onChanged: onChanged,
      labelBuilder: (semesterId) {
        return semesters.firstWhere((entry) => entry.key == semesterId).value;
      },
      leadingBuilder: (context, item, selected) {
        return Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 22,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        );
      },
      width: 280,
      itemHeight: 56,
      visibleItemCount: 5,
      anchorBuilder: (context, isOpen, toggle) {
        return DesktopMenuRow(
          leading: const Icon(Icons.swap_horiz, size: 20),
          title: Text('切换学期', style: Theme.of(context).textTheme.bodyMedium),
          onTap: toggle,
        );
      },
    );
  }
}

class _DesktopWeekTitleMenu extends StatelessWidget {
  final int currentWeek;
  final String semesterLabel;
  final int slideDirection;
  final ValueChanged<int> onWeekChanged;

  const _DesktopWeekTitleMenu({
    required this.currentWeek,
    required this.semesterLabel,
    required this.slideDirection,
    required this.onWeekChanged,
  });

  static final List<int> _weeks = List<int>.generate(25, (index) => index + 1);

  @override
  Widget build(BuildContext context) {
    return DesktopSelectPopover<int>(
      items: _weeks,
      value: currentWeek,
      onChanged: onWeekChanged,
      labelBuilder: (week) => '第 $week 周',
      width: 200,
      itemHeight: 56,
      visibleItemCount: 5,
      anchorBuilder: (context, isOpen, toggle) {
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _WeekTitleContent(
              currentWeek: currentWeek,
              semesterLabel: semesterLabel,
              slideDirection: slideDirection,
              trailingIcon: isOpen
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
          ),
        );
      },
    );
  }
}

class _WeekTitleContent extends StatelessWidget {
  final int currentWeek;
  final String semesterLabel;
  final int slideDirection;
  final IconData trailingIcon;

  const _WeekTitleContent({
    required this.currentWeek,
    required this.semesterLabel,
    required this.slideDirection,
    required this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0, slideDirection >= 0 ? 0.3 : -0.3),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                '第 $currentWeek 周',
                key: ValueKey<int>(currentWeek),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (semesterLabel.isNotEmpty)
              Text(
                semesterLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
        Icon(trailingIcon, size: 20, color: theme.colorScheme.onSurfaceVariant),
      ],
    );
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
      padding: EdgeInsets.only(
        bottom: AppShellMetrics.bottomContentPaddingOf(context),
      ),
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
    final sorted = [...courses]..sort((a, b) {
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
    if (usesSidebarLayout(context)) {
      showDesktopPopover(
        anchorContext: context,
        width: 360,
        placement: DesktopPopoverPlacement.rightTop,
        offset: const Offset(12, 0),
        builder: (context, close) {
          return DesktopPopoverSurface(
            padding: EdgeInsets.zero,
            child: CourseDetailContent(
              course: course,
              periods: periods,
              compact: true,
            ),
          );
        },
      );
      return;
    }

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return CourseDetailContent(
            course: course,
            periods: periods,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          );
        },
      ),
    );
  }
}
