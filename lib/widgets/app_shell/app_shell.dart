import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../features/campus_card/app/app_providers.dart';
import '../../pages/assignments_page.dart';
import '../../pages/campus_card_page.dart';
import '../../pages/home_page.dart';
import '../../pages/schedule_page.dart';
import '../../pages/settings_page.dart';
import '../../utils/adaptive_layout.dart';
import '../../utils/platform.dart';
import '../../widgets/adaptive_page_navigation.dart';
import 'app_destination.dart';
import 'desktop/desktop_shell.dart';
import 'mobile_shell.dart';

/// A campus-card entry the host asked for — a home-screen widget tap, a
/// shortcut, a `techpie://ecard/pay` link — that has not been shown yet.
///
/// The shell owns the push because the shell is what knows where the page
/// belongs: in the Home tab on iOS — where the feature grid opens it, whatever
/// tab the user left the app on — or the selected destination on a wide
/// window, and on the root navigator otherwise. A value set before the shell
/// mounts waits for it, which is what a cold start needs.
final appShellPendingEcardEntry = ValueNotifier<CampusCardEntry?>(null);

/// Asks the shell to bring the campus card's own tab forward, for an entry that
/// an already-open campus card handles itself: the code must not open in a tab
/// the user cannot see.
final appShellCampusCardRevealRequests = AppShellRevealRequests();

class AppShellRevealRequests extends ChangeNotifier {
  void request() => notifyListeners();
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Temporarily disabled: the wide-window sidebar (DesktopShell) is turned
  // off so every window width uses MobileShell's bottom nav bar instead.
  // Flip this back to true to restore the sidebar at width >= 600. The
  // nav-bar-clearance check in adaptive_feedback.dart was changed to match —
  // re-enabling this alone is not enough, see that call site as well.
  static const bool _desktopShellEnabled = false;

  /// The tab the campus card lives in on iOS: it is entered from Home's feature
  /// grid, so a widget or shortcut opens it there too, the way a system app's
  /// widget opens its content where that content belongs.
  static const int _campusCardTab = 0;

  int _selectedIndex = 0;
  int _previousSelectedIndex = 0;
  bool _sidebarCollapsed = false;

  /// One stack per destination, and a key for each: the content navigator is
  /// rebuilt when the destination changes, and two live navigators must not
  /// share one GlobalKey.
  final _contentNavigatorKeys = <int, GlobalKey<NavigatorState>>{};

  /// On iOS each tab owns its page stack, so the tab bar stays on screen as
  /// the user drills in and switching tabs returns to where that tab was —
  /// what UITabBarController does. Each stack needs its own hero controller,
  /// and its root its own primary scroll controller, so a second tap on the
  /// tab can scroll that tab, and only that tab, back to the top.
  final _tabNavigatorKeys = <int, GlobalKey<NavigatorState>>{};
  final _tabHeroControllers = <int, HeroController>{};
  final _tabScrollControllers = <int, ScrollController>{};
  static const List<AppDestination> _destinations = [
    AppDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      sfSymbol: 'house',
      selectedSfSymbol: 'house.fill',
      page: HomePage(key: ValueKey('home')),
    ),
    AppDestination(
      label: 'Schedule',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      sfSymbol: 'calendar',
      selectedSfSymbol: 'calendar.circle.fill',
      page: SchedulePage(key: ValueKey('schedule')),
    ),
    AppDestination(
      label: 'Deadlines',
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      sfSymbol: 'checkmark.circle',
      selectedSfSymbol: 'checkmark.circle.fill',
      page: AssignmentsPage(key: ValueKey('assignments')),
    ),
    AppDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      sfSymbol: 'gearshape',
      selectedSfSymbol: 'gearshape.fill',
      page: SettingsPage(key: ValueKey('settings')),
    ),
  ];

  @override
  void initState() {
    super.initState();
    appShellPendingEcardEntry.addListener(_showPendingEcardEntry);
    appShellCampusCardRevealRequests.addListener(_revealCampusCardTab);
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
    appShellCampusCardRevealRequests.removeListener(_revealCampusCardTab);
    for (final controller in _tabHeroControllers.values) {
      controller.dispose();
    }
    for (final controller in _tabScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Pushes the entry the host asked for into the destination the user is on.
  void _showPendingEcardEntry() {
    final entry = appShellPendingEcardEntry.value;
    if (entry == null || !mounted) return;
    appShellPendingEcardEntry.value = null;
    final BuildContext? nested;
    if (isIos()) {
      // Straight above Home, as the feature grid would have opened it, so one
      // back lands on Home rather than on whatever that tab was showing.
      _revealCampusCardTab();
      final navigator = _tabNavigatorKeys[_campusCardTab]?.currentState;
      navigator?.popUntil((route) => route.isFirst);
      nested = navigator?.context;
    } else {
      nested = _contentNavigatorKeys[_selectedIndex]?.currentContext;
    }
    unawaited(
      pushAdaptivePage<void>(
        nested ?? context,
        builder: (_) => CampusCardPage(entry: entry),
      ),
    );
  }

  void _revealCampusCardTab() {
    if (!mounted || !isIos() || _selectedIndex == _campusCardTab) return;
    _onDestinationSelected(_campusCardTab);
  }

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) {
      _returnToTabRoot(index);
      return;
    }
    _previousSelectedIndex = _selectedIndex;
    setState(() => _selectedIndex = index);
  }

  /// A tap on the selected tab first unwinds that tab's stack, and on its root
  /// scrolls back to the top — the system tab bar's behaviour.
  void _returnToTabRoot(int index) {
    final navigator = _tabNavigatorKeys[index]?.currentState;
    if (navigator == null) return;
    if (navigator.canPop()) {
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

  void _onSidebarToggleCollapsed() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
  }

  Widget _buildPageView(BuildContext context) {
    return AppDestinationSwitcher(
      selectedIndex: _selectedIndex,
      previousSelectedIndex: _previousSelectedIndex,
      preserveVisitedPages: isIos(),
      animationsEnabled: !MediaQuery.disableAnimationsOf(context),
      pages: [
        for (var index = 0; index < _destinations.length; index++)
          isIos()
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

  Widget _buildDesktopContentNavigator(Widget pageView) {
    final navigatorKey = _contentNavigatorKeys.putIfAbsent(
      _selectedIndex,
      GlobalKey<NavigatorState>.new,
    );

    // The same reason the settings page needs it: this stack holds the pages a
    // destination pushed, so the system back has to reach it rather than the
    // root navigator, which only has the shell on it.
    return NavigatorPopHandler(
      onPopWithResult: (_) => navigatorKey.currentState?.pop(),
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (settings) => adaptivePageRoute<void>(
          settings: settings,
          builder: (context) => pageView,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final windowSizeClass = appWindowSizeClassOf(context);
    final pageView = _buildPageView(context);

    if (_desktopShellEnabled &&
        windowSizeClass == AppWindowSizeClass.expanded) {
      return DesktopShell(
        destinations: _destinations,
        selectedIndex: _selectedIndex,
        sidebarCollapsed: _sidebarCollapsed,
        onDestinationSelected: _onDestinationSelected,
        onToggleSidebarCollapsed: _onSidebarToggleCollapsed,
        child: _buildDesktopContentNavigator(pageView),
      );
    }

    if (_desktopShellEnabled &&
        windowSizeClass == AppWindowSizeClass.medium) {
      return DesktopShell(
        destinations: _destinations,
        selectedIndex: _selectedIndex,
        sidebarCollapsed: true,
        showToggleButton: false,
        onDestinationSelected: _onDestinationSelected,
        onToggleSidebarCollapsed: () {},
        child: _buildDesktopContentNavigator(pageView),
      );
    }

    return MobileShell(
      destinations: _destinations,
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onDestinationSelected,
      child: pageView,
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
                  child: widget.pages[index],
                ),
              ),
        ],
      );
    }

    if (!widget.animationsEnabled) {
      return widget.pages[widget.selectedIndex];
    }

    return PageTransitionSwitcher(
      duration: const Duration(milliseconds: 300),
      layoutBuilder: (entries) => Stack(
        fit: StackFit.expand,
        children: entries,
      ),
      transitionBuilder: (child, animation, secondaryAnimation) {
        // Pure horizontal slide — no fade, no scale, no color fill.
        // Controllers always run forward: the new entry's primary (0→1)
        // drives its incoming slide; the old entry's secondary (0→1)
        // drives its outgoing slide. Direction is encoded only in the
        // tween sign, so backward navigation mirrors forward correctly
        // and the easing curve stays consistent in both directions.
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
              Curves.easeInOutCubicEmphasized.transform(animation.value),
            );
            final outgoingOffset = outgoing.transform(
              Curves.easeInOutCubicEmphasized
                  .transform(secondaryAnimation.value),
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
