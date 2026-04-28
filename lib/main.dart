import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/assignments_page.dart';
import 'pages/home_page.dart';
import 'pages/schedule_page.dart';
import 'pages/settings_page.dart';
import 'services/auth_service.dart';
import 'services/debug_logger.dart';
import 'services/http_client.dart';
import 'services/schedule_service.dart';
import 'services/service_provider.dart';
import 'services/storage_service.dart';
import 'services/theme_service.dart';
import 'widgets/native_glass_tab_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs);
  final debugLogger = DebugLogger()..enabled = storageService.debugMode;
  final httpClient = LoggingHttpClient(debugLogger);
  final authService = AuthService(storageService, httpClient);
  final themeService = ThemeService(storageService);
  final scheduleService = ScheduleService(
    storageService,
    httpClient,
    authService,
  );

  await authService.initialize();

  // Load cached schedule data so widgets (e.g. home page) render immediately
  await scheduleService.loadCachedData();

  // Fetch fresh schedule data in the background if logged in
  if (authService.isLoggedIn) {
    scheduleService.fetchAll(); // fire-and-forget, UI uses cache first
  }

  runApp(
    TechPieApp(
      authService: authService,
      debugLogger: debugLogger,
      storageService: storageService,
      themeService: themeService,
      scheduleService: scheduleService,
    ),
  );
}

class TechPieApp extends StatelessWidget {
  final AuthService authService;
  final DebugLogger debugLogger;
  final StorageService storageService;
  final ThemeService themeService;
  final ScheduleService scheduleService;

  const TechPieApp({
    super.key,
    required this.authService,
    required this.debugLogger,
    required this.storageService,
    required this.themeService,
    required this.scheduleService,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) => ServiceProvider(
        authService: authService,
        debugLogger: debugLogger,
        storageService: storageService,
        themeService: themeService,
        scheduleService: scheduleService,
        child: MaterialApp(
          title: 'TechPie',
          theme: themeService.lightTheme,
          darkTheme: themeService.darkTheme,
          themeMode: themeService.themeMode,
          home: const AppShell(),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const List<NativeGlassTabBarItem> _navigationItems = [
    NativeGlassTabBarItem(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      sfSymbol: 'house',
      selectedSfSymbol: 'house.fill',
    ),
    NativeGlassTabBarItem(
      label: 'Schedule',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      sfSymbol: 'calendar',
      selectedSfSymbol: 'calendar.circle.fill',
    ),
    NativeGlassTabBarItem(
      label: 'Assignments',
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      sfSymbol: 'checkmark.circle',
      selectedSfSymbol: 'checkmark.circle.fill',
    ),
    NativeGlassTabBarItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      sfSymbol: 'gearshape',
      selectedSfSymbol: 'gearshape.fill',
    ),
  ];

  static const List<Widget> _pages = [
    HomePage(key: ValueKey('home')),
    SchedulePage(key: ValueKey('schedule')),
    AssignmentsPage(key: ValueKey('assignments')),
    SettingsPage(key: ValueKey('settings')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation, secondaryAnimation) {
          return FadeThroughTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            fillColor: Colors.transparent,
            child: child,
          );
        },
        child: _pages[_selectedIndex],
      ),
      bottomNavigationBar: NativeGlassTabBar(
        selectedIndex: _selectedIndex,
        items: _navigationItems,
        onSelected: (index) {
          if (index == _selectedIndex) return;

          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
