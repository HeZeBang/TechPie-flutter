import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../pages/assignments_page.dart';
import '../../pages/home_page.dart';
import '../../pages/schedule_page.dart';
import '../../pages/settings_page.dart';
import 'app_destination.dart';
import 'desktop/desktop_shell.dart';
import 'mobile_shell.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const int _assignmentsIndex = 2;

  int _selectedIndex = 0;
  int _previousSelectedIndex = 0;
  bool _sidebarCollapsed = false;
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

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) return;
    _previousSelectedIndex = _selectedIndex;
    setState(() => _selectedIndex = index);
  }

  void _onSidebarToggleCollapsed() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
  }

  Widget _buildPageView() {
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
        final direction = _selectedIndex >= _previousSelectedIndex ? 1.0 : -1.0;
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
      child: _destinations[_selectedIndex].page,
    );
  }

  Widget _buildDesktopContentNavigator(Widget pageView) {
    return Navigator(
      key: ValueKey('desktop-content-$_selectedIndex'),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (context) => pageView,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pageView = _buildPageView();

    if (width >= 960) {
      return DesktopShell(
        destinations: _destinations,
        selectedIndex: _selectedIndex,
        sidebarCollapsed: _sidebarCollapsed,
        onDestinationSelected: _onDestinationSelected,
        onToggleSidebarCollapsed: _onSidebarToggleCollapsed,
        child: _buildDesktopContentNavigator(pageView),
      );
    }

    if (width >= 600) {
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
      assignmentsIndex: _assignmentsIndex,
      onDestinationSelected: _onDestinationSelected,
      child: pageView,
    );
  }
}
