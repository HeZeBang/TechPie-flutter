import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../features/campus_card/app/app_providers.dart';
import '../../models/feature.dart';
import '../../pages/assignments_page.dart';
import '../../pages/campus_card_page.dart';
import '../../pages/campus_feature_navigation.dart';
import '../../pages/campus_services_page.dart';
import '../../pages/home_page.dart';
import '../../pages/schedule_page.dart';
import '../../pages/settings_page.dart';
import '../../services/assignment_service.dart';
import '../../services/service_provider.dart';
import '../../services/theme_service.dart';
import '../../theme/tp_icons.dart';
import '../../utils/adaptive_layout.dart';
import '../../utils/motion.dart';
import '../../utils/platform.dart';
import '../../utils/user_display_name.dart';
import '../../widgets/adaptive_feedback.dart';
import '../../widgets/adaptive_page_navigation.dart';
import 'app_destination.dart';
import 'desktop/desktop_command_palette.dart';
import 'desktop/desktop_shell.dart';
import 'desktop/desktop_sidebar_tokens.dart';
import 'desktop/desktop_workbench_chrome.dart';
import 'desktop/macos_window_drag.dart';
import 'mobile_shell.dart';

/// Computes the live desktop sidebar badge for the Deadlines tab.
///
/// Counts uncompleted upcoming items (including those currently inside their
/// late-submission window). Marks the badge urgent when any item is inside its
/// late window or due within 24 hours.
SidebarBadgeData? computeDeadlineSidebarBadge(
  AssignmentService service, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  var count = 0;
  var urgent = false;
  for (final item in service.visibleAssignments) {
    if (service.isCompleted(item)) continue;
    if (item.effectiveDue.isBefore(current)) continue;
    count++;
    final inLateWindow =
        item.effectiveLateDue != null && item.due.isBefore(current);
    final remaining = item.effectiveDue.difference(current);
    if (inLateWindow || remaining < const Duration(hours: 24)) {
      urgent = true;
    }
  }
  if (count <= 0) return null;
  return SidebarBadgeData(count: count, urgent: urgent);
}

/// A campus-card entry the host asked for — a home-screen widget tap, a
/// shortcut, a `techpie://ecard/pay` link — that has not been shown yet.
///
/// The shell owns the push because the shell is what knows where the page
/// belongs: in the Home tab on iOS — where the feature grid opens it, whatever
/// tab the user left the app on — or the selected destination on a wide
/// window, and on the root navigator otherwise. A value set before the shell
/// mounts waits for it, which is what a cold start needs.
final appShellPendingEcardEntry = ValueNotifier<CampusCardEntry?>(null);
final appShellPendingDeadlines = ValueNotifier<bool>(false);
final appShellPendingTab = ValueNotifier<int?>(null);
final appShellPendingHomeEdit = ValueNotifier<bool>(false);

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const bool _desktopShellEnabled = true;

  /// The tab the campus card lives in on iOS: it is entered from Home's feature
  /// grid, so a widget or shortcut opens it there too, the way a system app's
  /// widget opens its content where that content belongs.
  static const int _campusCardTab = 0;

  int _selectedIndex = 0;
  int _previousSelectedIndex = 0;
  bool _sidebarCollapsed = false;
  bool _sidebarPrefLoaded = false;

  /// Per-tab navigation stacks, hero controllers, and primary scroll
  /// controllers. Used on iOS (like UITabBarController) and in DesktopShell so
  /// switching tabs preserves each tab's state, scroll offset, and subpage
  /// stack, while tapping the active tab pops to root and scrolls to top.
  final _tabNavigatorKeys = <int, GlobalKey<NavigatorState>>{};
  final _tabHeroControllers = <int, HeroController>{};
  final _tabScrollControllers = <int, ScrollController>{};
  static const List<AppDestination> _destinations = [
    AppDestination(
      label: '首页',
      icon: TpIcons.home,
      selectedIcon: TpIcons.home,
      sfSymbol: 'house',
      selectedSfSymbol: 'house.fill',
      page: HomePage(key: ValueKey('home')),
    ),
    AppDestination(
      label: '课表',
      icon: TpIcons.schedule,
      selectedIcon: TpIcons.schedule,
      sfSymbol: 'calendar',
      selectedSfSymbol: 'calendar.circle.fill',
      page: SchedulePage(key: ValueKey('schedule')),
    ),
    AppDestination(
      label: 'Deadlines',
      shortLabel: 'DDL',
      icon: TpIcons.deadlines,
      selectedIcon: TpIcons.deadlines,
      sfSymbol: 'checkmark.circle',
      selectedSfSymbol: 'checkmark.circle.fill',
      page: AssignmentsPage(key: ValueKey('assignments')),
    ),
    AppDestination(
      label: '我的',
      icon: TpIcons.profile,
      selectedIcon: TpIcons.profile,
      sfSymbol: 'person',
      selectedSfSymbol: 'person.fill',
      page: SettingsPage(key: ValueKey('settings')),
    ),
  ];

  @override
  void initState() {
    super.initState();
    appShellPendingEcardEntry.addListener(_showPendingEcardEntry);
    appShellPendingDeadlines.addListener(_showDeadlines);
    appShellPendingTab.addListener(_showPendingTab);
    if (appShellPendingDeadlines.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showDeadlines());
    }
    if (appShellPendingTab.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingTab());
    }
    if (appShellPendingEcardEntry.value != null) {
      // Deferred: a push during the first build is a build-time side effect.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showPendingEcardEntry(),
      );
    }
  }

  @override
  void dispose() {
    appShellPendingEcardEntry.removeListener(_showPendingEcardEntry);
    appShellPendingDeadlines.removeListener(_showDeadlines);
    appShellPendingTab.removeListener(_showPendingTab);
    for (final controller in _tabHeroControllers.values) {
      controller.dispose();
    }
    for (final controller in _tabScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showPendingTab() {
    final target = appShellPendingTab.value;
    if (!mounted || target == null) return;
    appShellPendingTab.value = null;
    if (target < 0 || target >= _destinations.length) return;
    _onDestinationSelected(target);
  }

  void _showDeadlines() {
    if (!mounted || !appShellPendingDeadlines.value) return;
    appShellPendingDeadlines.value = false;
    _tabNavigatorKeys[2]?.currentState?.popUntil((route) => route.isFirst);
    _onDestinationSelected(2);
  }

  /// Pushes the entry onto the visible navigation stack.
  void _showPendingEcardEntry() {
    final entry = appShellPendingEcardEntry.value;
    if (entry == null || !mounted) return;
    appShellPendingEcardEntry.value = null;
    context.getInheritedWidgetOfExactType<ServiceProvider>()?.telemetry?.featureOpened('campus_card');
    // Login and playback pages can cover the entire tab shell: the code then
    // opens above that page, and back returns to it.
    final shellCovered = !ModalRoute.of(context)!.isCurrent;
    final BuildContext? nested;
    if (isIos() && !shellCovered) {
      // Straight above Home, as the feature grid would have opened it, so one
      // back lands on Home rather than on whatever that tab was showing.
      if (_selectedIndex != _campusCardTab) {
        _onDestinationSelected(_campusCardTab);
      }
      final navigator = _tabNavigatorKeys[_campusCardTab]?.currentState;
      navigator?.popUntil((route) => route.isFirst);
      nested = navigator?.context;
    } else {
      nested = _tabNavigatorKeys[_selectedIndex]?.currentContext;
    }
    unawaited(
      pushAdaptivePage<void>(
        nested ?? context,
        rootNavigator: shellCovered,
        builder: (_) => CampusCardPage(entry: entry),
      ),
    );
  }

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) {
      _returnToTabRoot(index);
      return;
    }
    const features = ['home', 'schedule', 'deadlines', 'settings'];
    context.getInheritedWidgetOfExactType<ServiceProvider>()?.telemetry?.featureOpened(features[index]);
    _previousSelectedIndex = _selectedIndex;
    setState(() => _selectedIndex = index);
  }

  /// A tap on the selected tab first unwinds that tab's stack, and on its root
  /// scrolls back to the top — the system tab bar's behaviour.
  void _returnToTabRoot(int index) {
    final navigator = _tabNavigatorKeys[index]?.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
      return;
    }
    final controller = _tabScrollControllers[index];
    if (controller == null) return;
    final animate = !MediaQuery.disableAnimationsOf(context);
    for (final position in controller.positions) {
      if (animate) {
        unawaited(position.animateTo(
          position.minScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),);
      } else {
        position.jumpTo(position.minScrollExtent);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sidebarPrefLoaded) {
      _sidebarPrefLoaded = true;
      context.getInheritedWidgetOfExactType<ServiceProvider>()?.telemetry?.featureOpened('home');
      final storage = context
          .dependOnInheritedWidgetOfExactType<ServiceProvider>()
          ?.storageService;
      if (storage != null) {
        _sidebarCollapsed = storage.desktopSidebarCollapsed;
      }
    }
  }

  void _onSidebarToggleCollapsed() {
    final next = !_sidebarCollapsed;
    setState(() => _sidebarCollapsed = next);
    final storage = context
        .dependOnInheritedWidgetOfExactType<ServiceProvider>()
        ?.storageService;
    if (storage != null) {
      unawaited(storage.setDesktopSidebarCollapsed(next));
    }
  }

  BuildContext _activeNavigationContext() =>
      _tabNavigatorKeys[_selectedIndex]?.currentContext ?? context;

  bool _canNavigateBackInActiveTab() =>
      _tabNavigatorKeys[_selectedIndex]?.currentState?.canPop() ?? false;

  void _navigateBackInActiveTab() {
    final navigator = _tabNavigatorKeys[_selectedIndex]?.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
    }
  }

  void _openCampusServices() {
    final services =
        context.getInheritedWidgetOfExactType<ServiceProvider>();
    if (services == null) return;
    unawaited(
      pushAdaptivePage<void>(
        _activeNavigationContext(),
        builder: (_) => CampusServicesPage(storage: services.storageService),
      ),
    );
  }

  void _refreshWorkbenchData() {
    final services =
        context.getInheritedWidgetOfExactType<ServiceProvider>();
    if (services == null) return;
    switch (_selectedIndex) {
      case 1:
        services.scheduleService.requestFetch(force: true);
      case 2:
        unawaited(services.assignmentService.fetchAssignments());
      case 3:
        unawaited(services.campusCardService.refreshAccount());
      default:
        services.scheduleService.requestFetch(force: true);
        unawaited(services.assignmentService.fetchAssignments());
        unawaited(services.campusCardService.refreshAccount());
    }
    showAdaptiveFeedback(
      context: context,
      message: '正在刷新数据…',
      duration: const Duration(seconds: 2),
    );
  }

  void _toggleLightDarkTheme() {
    final services =
        context.getInheritedWidgetOfExactType<ServiceProvider>();
    if (services == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final target = isDark ? AppThemeMode.light : AppThemeMode.dark;
    unawaited(services.themeService.setMode(target));
    showAdaptiveFeedback(
      context: context,
      message: '已切换为${target.label}外观',
      duration: const Duration(seconds: 2),
    );
  }

  void _openHomeEditMode() {
    _onDestinationSelected(0);
    appShellPendingHomeEdit.value = true;
  }

  void _openCommandPalette({required bool allowSidebarToggle}) {
    if (closeDesktopCommandPaletteIfOpen()) return;
    final services =
        context.getInheritedWidgetOfExactType<ServiceProvider>();
    final isMac = isMacOsDesktop();
    final mod = isMac ? '⌘' : 'Ctrl ';

    final items = <DesktopCommandItem>[
      DesktopCommandItem(
        id: 'tab.home',
        title: '首页',
        subtitle: '今日课程、校园卡与快捷入口',
        group: '导航',
        icon: TpIcons.home,
        shortcutLabel: '${mod}1',
        keywords: const ['home', 'shouye'],
        onExecute: () => _onDestinationSelected(0),
      ),
      DesktopCommandItem(
        id: 'tab.schedule',
        title: '课表',
        subtitle: '查看周课表与课程详情',
        group: '导航',
        icon: TpIcons.schedule,
        shortcutLabel: '${mod}2',
        keywords: const ['schedule', 'kebiao', 'timetable'],
        onExecute: () => _onDestinationSelected(1),
      ),
      DesktopCommandItem(
        id: 'tab.deadlines',
        title: 'Deadlines',
        subtitle: '作业、实验与截止提醒',
        group: '导航',
        icon: TpIcons.deadlines,
        shortcutLabel: '${mod}3',
        keywords: const ['deadline', 'ddl', 'assignments', 'zuoye'],
        onExecute: () => _onDestinationSelected(2),
      ),
      DesktopCommandItem(
        id: 'tab.settings',
        title: '我的',
        subtitle: '账号绑定、云同步与外观设置',
        group: '导航',
        icon: TpIcons.profile,
        shortcutLabel: '${mod}4',
        keywords: const ['settings', 'me', 'wode', 'shezhi'],
        onExecute: () => _onDestinationSelected(3),
      ),
      if (services != null)
        DesktopCommandItem(
          id: 'service.hub',
          title: '校园服务中心',
          subtitle: '浏览全部校园服务与首页快捷编辑',
          group: '校园服务',
          icon: TpIcons.activities,
          keywords: const ['services', 'fuwu', 'more', '更多'],
          onExecute: _openCampusServices,
        ),
      if (services != null)
        for (final feature in featureEntries)
          DesktopCommandItem(
            id: 'feature.${feature.id}',
            title: feature.description,
            subtitle: feature.subtitle,
            group: '校园服务',
            icon: feature.icon.icon ?? TpIcons.activities,
            keywords: <String>[...feature.keywords, feature.category.label],
            onExecute: () =>
                openCampusFeature(_activeNavigationContext(), feature),
          ),
      if (services != null)
        DesktopCommandItem(
          id: 'action.refresh',
          title: '刷新当前数据',
          subtitle: '同步最新课表、Deadlines 与校园卡余额',
          group: '快捷操作',
          icon: TpIcons.refresh,
          shortcutLabel: '${mod}R',
          keywords: const ['refresh', 'sync', 'shuaxin'],
          onExecute: _refreshWorkbenchData,
        ),
      if (allowSidebarToggle)
        DesktopCommandItem(
          id: 'action.toggle_sidebar',
          title: _sidebarCollapsed ? '展开侧边栏' : '收起侧边栏',
          subtitle: '切换桌面侧栏折叠状态',
          group: '快捷操作',
          icon: _sidebarCollapsed
              ? TpIcons.sidebarExpand
              : TpIcons.sidebarCollapse,
          shortcutLabel: '$mod\\',
          keywords: const ['sidebar', 'cebianlan', 'collapse'],
          onExecute: _onSidebarToggleCollapsed,
        ),
      DesktopCommandItem(
        id: 'action.edit_home',
        title: '定制主页控件',
        subtitle: '排序、增删或切换校园卡展示样式',
        group: '快捷操作',
        icon: TpIcons.dashboard,
        keywords: const ['home', 'widget', 'layout', '定制', '主页', '组件', '排序'],
        onExecute: _openHomeEditMode,
      ),
      if (services != null)
        DesktopCommandItem(
          id: 'action.toggle_theme',
          title: '切换深浅外观',
          subtitle: '在浅色与深色模式之间快速切换',
          group: '快捷操作',
          icon: TpIcons.palette,
          keywords: const ['theme', 'dark', 'light', '外观'],
          onExecute: _toggleLightDarkTheme,
        ),
    ];

    unawaited(showDesktopCommandPalette(context: context, items: items));
  }

  DesktopSidebarAccountSummary? _buildAccountSummary(ServiceProvider? services) {
    if (services == null) return null;
    final auth = services.authService;
    if (!auth.isLoggedIn || auth.session == null) {
      return const DesktopSidebarAccountSummary(
        displayName: '',
        avatarText: 'GP',
        isLoggedIn: false,
      );
    }
    final displayName = resolveUserDisplayName(
      session: auth.session,
      idsRealName: services.thirdPartyAuthService.idsAccount?.name,
      campusCardOwnerName: services.campusCardService.cachedOwnerName,
    );
    return DesktopSidebarAccountSummary(
      displayName: displayName,
      avatarText: userAvatarLabel(displayName),
      isLoggedIn: true,
      boundPlatformCount:
          services.thirdPartyAuthService.boundPlatforms.length,
    );
  }

  Widget _buildPageView(
    BuildContext context, {
    required bool usePerTabNavigators,
  }) {
    return AppDestinationSwitcher(
      selectedIndex: _selectedIndex,
      previousSelectedIndex: _previousSelectedIndex,
      preserveVisitedPages: usePerTabNavigators,
      animationsEnabled: !MediaQuery.disableAnimationsOf(context),
      pages: [
        for (var index = 0; index < _destinations.length; index++)
          usePerTabNavigators
              ? _buildTabNavigator(index, _destinations[index].page)
              : _destinations[index].page,
      ],
    );
  }

  Widget _buildTabNavigator(int index, Widget page) {
    final navigatorKey = _tabNavigatorKeys.putIfAbsent(
      index,
      GlobalKey<NavigatorState>.new,
    );
    final scrollController = _tabScrollControllers.putIfAbsent(
      index,
      ScrollController.new,
    );

    // Only the selected tab answers a system back: an offstage tab with pages
    // of its own must not pop behind the user's back.
    return NavigatorPopHandler(
      enabled: index == _selectedIndex,
      onPopWithResult: (_) => navigatorKey.currentState?.pop(),
      child: HeroControllerScope(
        controller: _tabHeroControllers.putIfAbsent(
          index,
          MaterialApp.createMaterialHeroController,
        ),
        child: Navigator(
          key: navigatorKey,
          onGenerateRoute: (settings) => adaptivePageRoute<void>(
            settings: settings,
            builder: (context) => PrimaryScrollController(
              controller: scrollController,
              child: page,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktopShell =
        _desktopShellEnabled && usesDesktopSidebarShell(context);
    final autoCollapsedRail =
        desktopShell && usesAutoCollapsedSidebarRail(context);
    final effectiveSidebarCollapsed = autoCollapsedRail || _sidebarCollapsed;
    final showSidebarToggle = !autoCollapsedRail;

    final pageView = _buildPageView(
      context,
      usePerTabNavigators: isIos() || desktopShell || isDesktop(),
    );

    final services =
        context.dependOnInheritedWidgetOfExactType<ServiceProvider>();

    Widget shellWidget;
    if (desktopShell) {
      final listenables = <Listenable>[
        if (services != null) ...[
          services.assignmentService,
          services.authService,
          services.thirdPartyAuthService,
          services.campusCardService,
        ],
      ];
      if (listenables.isEmpty) {
        shellWidget = DesktopShell(
          destinations: _destinations,
          selectedIndex: _selectedIndex,
          sidebarCollapsed: effectiveSidebarCollapsed,
          showToggleButton: showSidebarToggle,
          onDestinationSelected: _onDestinationSelected,
          onToggleSidebarCollapsed: _onSidebarToggleCollapsed,
          onOpenCommandPalette: () =>
              _openCommandPalette(allowSidebarToggle: showSidebarToggle),
          onOpenCampusServices:
              services == null ? null : _openCampusServices,
          accountDestinationIndex: 3,
          onOpenAccount: () => _onDestinationSelected(3),
          child: pageView,
        );
      } else {
        shellWidget = ListenableBuilder(
          listenable: Listenable.merge(listenables),
          builder: (context, child) {
            final deadlineBadge =
                computeDeadlineSidebarBadge(services!.assignmentService);
            return DesktopShell(
              destinations: _destinations,
              selectedIndex: _selectedIndex,
              sidebarCollapsed: effectiveSidebarCollapsed,
              showToggleButton: showSidebarToggle,
              badges: deadlineBadge == null ? const {} : {2: deadlineBadge},
              onDestinationSelected: _onDestinationSelected,
              onToggleSidebarCollapsed: _onSidebarToggleCollapsed,
              onOpenCommandPalette: () =>
                  _openCommandPalette(allowSidebarToggle: showSidebarToggle),
              onOpenCampusServices: _openCampusServices,
              accountSummary: _buildAccountSummary(services),
              accountDestinationIndex: 3,
              onOpenAccount: () => _onDestinationSelected(3),
              child: child!,
            );
          },
          child: pageView,
        );
      }
    } else {
      shellWidget = MobileShell(
        destinations: _destinations,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        child: pageView,
      );
    }

    if (!isDesktop()) return shellWidget;

    return DesktopWorkbenchChrome(
      onSelectTab: _onDestinationSelected,
      onToggleCommandPalette: () =>
          _openCommandPalette(allowSidebarToggle: desktopShell && showSidebarToggle),
      onRefresh: _refreshWorkbenchData,
      onNavigateBack: _navigateBackInActiveTab,
      canNavigateBack: _canNavigateBackInActiveTab,
      onOpenCampusServices: _openCampusServices,
      onToggleTheme: _toggleLightDarkTheme,
      onEditHomeLayout: _openHomeEditMode,
      sidebarCollapsed: effectiveSidebarCollapsed,
      onToggleSidebar:
          desktopShell && showSidebarToggle ? _onSidebarToggleCollapsed : null,
      child: shellWidget,
    );
  }
}

class AppDestinationSwitcher extends StatefulWidget {
  const AppDestinationSwitcher({
    super.key,
    required this.pages,
    required this.selectedIndex,
    required this.previousSelectedIndex,
    required this.preserveVisitedPages,
    required this.animationsEnabled,
  });

  final List<Widget> pages;
  final int selectedIndex;
  final int previousSelectedIndex;
  final bool preserveVisitedPages;
  final bool animationsEnabled;

  @override
  State<AppDestinationSwitcher> createState() => _AppDestinationSwitcherState();
}

class _AppDestinationSwitcherState extends State<AppDestinationSwitcher> {
  late final Set<int> _visitedIndexes = {widget.selectedIndex};

  @override
  void didUpdateWidget(covariant AppDestinationSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visitedIndexes.add(widget.selectedIndex);
    _visitedIndexes.removeWhere((index) => index >= widget.pages.length);
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.pages.isNotEmpty);
    assert(
      widget.selectedIndex >= 0 && widget.selectedIndex < widget.pages.length,
    );

    if (widget.preserveVisitedPages) {
      return Stack(
        fit: StackFit.expand,
        children: [
          for (var index = 0; index < widget.pages.length; index++)
            if (_visitedIndexes.contains(index))
              Offstage(
                offstage: index != widget.selectedIndex,
                child: TickerMode(
                  enabled: index == widget.selectedIndex,
                  child: HeroMode(
                    enabled: index == widget.selectedIndex,
                    child: widget.pages[index],
                  ),
                ),
              ),
        ],
      );
    }

    if (!widget.animationsEnabled) {
      return widget.pages[widget.selectedIndex];
    }

    return PageTransitionSwitcher(
      duration: TgMotion.tabsPageSwitch,
      layoutBuilder: (entries) => Stack(
        fit: StackFit.expand,
        children: entries,
      ),
      transitionBuilder: (child, animation, secondaryAnimation) {
        // Pure horizontal slide synced to TgBottomNavBar's 320ms easeOutQuint
        // timeline so bar capsule and page motion read as one rigid body.
        final direction =
            widget.selectedIndex >= widget.previousSelectedIndex ? 1.0 : -1.0;
        final incoming = Tween<Offset>(
          begin: Offset(direction, 0),
          end: Offset.zero,
        );
        final outgoing = Tween<Offset>(
          begin: Offset.zero,
          end: Offset(-direction, 0),
        );
        return AnimatedBuilder(
          animation: Listenable.merge([animation, secondaryAnimation]),
          builder: (context, built) {
            final incomingOffset = incoming.transform(
              TgMotion.easeOutQuint.transform(animation.value),
            );
            final outgoingOffset = outgoing.transform(
              TgMotion.easeOutQuint.transform(secondaryAnimation.value),
            );
            return FractionalTranslation(
              translation: incomingOffset + outgoingOffset,
              child: built,
            );
          },
          child: child,
        );
      },
      child: widget.pages[widget.selectedIndex],
    );
  }
}
