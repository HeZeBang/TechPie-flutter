import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/utils/platform.dart';

import 'models/third_party_account.dart';
import 'services/assignment_service.dart';
import 'services/auth_service.dart';
import 'services/debug_logger.dart';
import 'services/http_client.dart';
import 'services/oa_gym_service.dart';
import 'services/schedule_service.dart';
import 'services/service_provider.dart';
import 'services/storage_service.dart';
import 'services/theme_service.dart';
import 'services/third_party_auth_service.dart';
import 'services/uni_auth_service.dart';
import 'widgets/adaptive_feedback.dart';
import 'widgets/app_shell/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializePlatformCapabilities();

  // OHOS white-screen probe disabled to speed up startup. Re-enable by
  // restoring the runApp(_BootProbe...) calls and wrapping init in try/catch.
  // runApp(const _BootProbe(message: '启动中…'));
  // final SharedPreferences prefs;
  // try {
  //   prefs = await SharedPreferences.getInstance();
  // } catch (e, st) {
  //   runApp(_BootProbe(message: 'SharedPreferences 失败:\n$e\n\n$st'));
  //   return;
  // }
  // try {
  //   await _realMain(prefs);
  // } catch (e, st) {
  //   runApp(_BootProbe(message: '初始化失败:\n$e\n\n$st'));
  // }

  final prefs = await SharedPreferences.getInstance();
  await _realMain(prefs);
}

Future<void> _realMain(SharedPreferences prefs) async {
  final storageService = StorageService(prefs);
  final debugLogger = DebugLogger()..enabled = storageService.debugMode;
  final httpClient = LoggingHttpClient(debugLogger);
  final authService = AuthService(storageService, httpClient);
  final themeService = ThemeService(storageService);
  final thirdPartyAuthService = ThirdPartyAuthService(
    storageService,
    httpClient,
  );
  final scheduleService = ScheduleService(
    storageService,
    httpClient,
    authService,
    thirdPartyAuthService,
  );
  final oaGymService = OaGymService(authService, storageService);
  final assignmentService = AssignmentService(
    storageService,
    httpClient,
    authService,
    thirdPartyAuthService,
    scheduleService,
  );
  final uniAuthService = UniAuthService();

  // Wire eGate binding checker into AuthService (avoids circular construction).
  authService.setEgateBindingChecker(
    () => thirdPartyAuthService.account(ThirdPartyPlatform.egate) != null,
  );

  authService.onLogout = () async {
    // Third-party bindings persist across logouts — they will be used by the
    // future sync system. Only clear ephemeral state.
    await assignmentService.clearCache();
    await assignmentService.clearAllOverrides();
    oaGymService.clearSession();
  };

  // -- Boot critical path: local I/O only --
  // Hydrate everything from caches so the first frame paints with data.
  await authService.loadSession();
  await thirdPartyAuthService.initialize();
  assignmentService.loadCached();
  await scheduleService.loadCachedData();

  runApp(
    TechPieApp(
      authService: authService,
      debugLogger: debugLogger,
      storageService: storageService,
      themeService: themeService,
      scheduleService: scheduleService,
      assignmentService: assignmentService,
      thirdPartyAuthService: thirdPartyAuthService,
      oaGymService: oaGymService,
      uniAuthService: uniAuthService,
    ),
  );

  // -- Background: renew tokens first (main session + third-party in
  // parallel — they touch independent state), then fan out fetches that
  // depend on those tokens. The whole block is unawaited so the splash
  // never blocks. --
  unawaited(() async {
    final renewMain = authService.isLoggedIn
        ? authService.tryRenewSession()
        : Future.value(true);
    final renewThirdParty = thirdPartyAuthService.autoRenewIfNeeded();

    final results = await Future.wait([renewMain, renewThirdParty]);
    final mainOk = results[0] as bool;
    final failedTp = results[1] as List<ThirdPartyPlatform>;

    if (!mainOk && !isIos()) {
      showAdaptiveFeedback(
        message: '登录已过期，请重新登录',
        style: AdaptiveFeedbackStyle.error,
        duration: const Duration(seconds: 4),
      );
    }
    if (failedTp.isNotEmpty && !isIos()) {
      showAdaptiveFeedback(
        message: '${failedTp.map((p) => p.label).join('、')} 续期失败',
        style: AdaptiveFeedbackStyle.error,
        duration: const Duration(seconds: 4),
      );
    }

    if (thirdPartyAuthService.account(ThirdPartyPlatform.egate) != null) {
      await scheduleService.fetchAll();
    }
    if (authService.isLoggedIn ||
        thirdPartyAuthService.boundPlatforms.isNotEmpty) {
      unawaited(assignmentService.fetchAssignments());
    }
  }());
  // Allow auto-refetch on subsequent auth / binding changes
  // (login, bind, unbind, logout).
  assignmentService.enableAutoRefetch();
}

// Disabled along with the boot probe above. Restore if the white-screen
// diagnostic is needed again.
// class _BootProbe extends StatelessWidget {
//   final String message;
//   const _BootProbe({required this.message});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       home: Scaffold(
//         body: SafeArea(
//           child: Padding(
//             padding: const EdgeInsets.all(16),
//             child: SingleChildScrollView(
//               child: SelectableText(
//                 message,
//                 style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

class TechPieApp extends StatefulWidget {
  final AuthService authService;
  final DebugLogger debugLogger;
  final StorageService storageService;
  final ThemeService themeService;
  final ScheduleService scheduleService;
  final AssignmentService assignmentService;
  final ThirdPartyAuthService thirdPartyAuthService;
  final OaGymService oaGymService;
  final UniAuthService uniAuthService;

  const TechPieApp({
    super.key,
    required this.authService,
    required this.debugLogger,
    required this.storageService,
    required this.themeService,
    required this.scheduleService,
    required this.assignmentService,
    required this.thirdPartyAuthService,
    required this.oaGymService,
    required this.uniAuthService,
  });

  @override
  State<TechPieApp> createState() => _TechPieAppState();
}

class _TechPieAppState extends State<TechPieApp> {
  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.themeService.updateSystemSchemes(lightDynamic, darkDynamic);
        });
        return _buildApp();
      },
    );
  }

  Widget _buildApp() {
    return ListenableBuilder(
      listenable: widget.themeService,
      builder: (context, _) => ServiceProvider(
        authService: widget.authService,
        debugLogger: widget.debugLogger,
        storageService: widget.storageService,
        themeService: widget.themeService,
        scheduleService: widget.scheduleService,
        assignmentService: widget.assignmentService,
        thirdPartyAuthService: widget.thirdPartyAuthService,
        oaGymService: widget.oaGymService,
        uniAuthService: widget.uniAuthService,
        child: MaterialApp(
          scaffoldMessengerKey: rootMessengerKey,
          title: 'TechPie',
          theme: widget.themeService.lightTheme,
          darkTheme: widget.themeService.darkTheme,
          themeMode: widget.themeService.themeMode,
          home: const AppShell(),
        ),
      ),
    );
  }
}
