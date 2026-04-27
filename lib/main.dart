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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs);
  final debugLogger = DebugLogger()..enabled = storageService.debugMode;
  final httpClient = LoggingHttpClient(debugLogger);
  final authService = AuthService(storageService, httpClient);
  final themeService = ThemeService(storageService);
  final scheduleService =
      ScheduleService(storageService, httpClient, authService);

  await authService.initialize();

  // Load cached schedule data so widgets (e.g. home page) render immediately
  await scheduleService.loadCachedData();

  // Fetch fresh schedule data in the background if logged in
  if (authService.isLoggedIn) {
    scheduleService.fetchAll(); // fire-and-forget, UI uses cache first
  }

  runApp(TechPieApp(
    authService: authService,
    debugLogger: debugLogger,
    storageService: storageService,
    themeService: themeService,
    scheduleService: scheduleService,
  ));
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

  static const List<Widget> _pages = [
    HomePage(key: ValueKey('home')),
    SchedulePage(key: ValueKey('schedule')),
    AssignmentsPage(key: ValueKey('assignments')),
    SettingsPage(key: ValueKey('settings')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation, secondaryAnimation) {
          return FadeThroughTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            fillColor: Theme.of(context).colorScheme.surface,
            child: child,
          );
        },
        child: _pages[_selectedIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Assignments',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
