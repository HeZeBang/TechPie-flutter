import 'dart:async';
import 'package:desktop_webview_window/desktop_webview_window.dart' show runWebViewTitleBarWidget;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/utils/platform.dart';

import 'models/third_party_account.dart';
import 'services/ai_service.dart';
import 'services/assignment_service.dart';
import 'services/auth_service.dart';
import 'services/debug_logger.dart';
import 'services/http_client.dart';
import 'services/oa_gym_service.dart';
import 'services/schedule_service.dart';
import 'services/service_provider.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'services/theme_service.dart';
import 'services/third_party_auth_service.dart';
import 'services/uni_auth_service.dart';
import 'widgets/adaptive_feedback.dart';
import 'widgets/app_shell/app_shell.dart';

void main(List<String> args) async {
  // If this Flutter engine is a desktop_webview_window title bar (secondary
  // engine inside the webview popup), render the navigation controls and
  // return early — do not start the full TechPie app.
  if (runWebViewTitleBarWidget(args)) return;

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
  final uniAuthService = UniAuthService();
  final authService = AuthService(storageService, httpClient, uniAuthService);
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
  final oaGymService = OaGymService(
    authService,
    storageService,
    thirdPartyAuthService,
  );
  final assignmentService = AssignmentService(
    storageService,
    httpClient,
    authService,
    thirdPartyAuthService,
    scheduleService,
  );
  final syncService = SyncService(authService, thirdPartyAuthService, storageService);
  final aiService = AiService(storageService);

  authService.onLogout = () async {
    // Third-party bindings persist across logouts — they will be used by the
    // sync system. Only clear ephemeral state.
    await assignmentService.clearCache();
    await assignmentService.clearAllOverrides();
    oaGymService.clearSession();
  };

  // Cloud-sync push hook: after any binding mutation, best-effort push the new
  // state (throttled). Wired via post-construction setter to avoid a circular
  // dependency between ThirdPartyAuthService and SyncService.
  thirdPartyAuthService.onBindingsChanged = () {
    return syncService.pushIfDue();
  };

  // Cloud-sync pull hook: after a fresh SSO login, pull cloud bindings onto
  // this device (or surface the master-password restore prompt).
  authService.onLogin = () async {
    if (!syncService.enabled) return;
    try {
      await syncService.pull();
    } on NeedMasterPassword {
      // Settings UI surfaces the restore banner.
    } catch (_) {}
  };

  // -- Boot critical path: local I/O only --
  // Hydrate everything from caches so the first frame paints with data.
  await authService.loadSession();
  await thirdPartyAuthService.initialize();
  await syncService.loadCachedKey();
  assignmentService.loadCached();
  await scheduleService.loadCachedData();
  await aiService.initialize();

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
      syncService: syncService,
      aiService: aiService,
    ),
  );

  // -- Background: renew tokens first (main SSO session + third-party in
  // parallel — they touch independent state), then fan out fetches that
  // depend on those tokens. The whole block is unawaited so the splash
  // never blocks. --
  unawaited(() async {
    // Primary SSO renewal uses Casdoor's refresh-token grant. With no
    // refresh token (legacy session) this is a no-op and returns false —
    // that is NOT a "login expired" condition, only an actual renewal
    // failure is.
    final renewMain = authService.isLoggedIn ? authService.tryRenewSession() : Future.value(true);
    final renewThirdParty = thirdPartyAuthService.autoRenewIfNeeded();

    final results = await Future.wait([renewMain, renewThirdParty]);
    final mainOk = results[0] as bool;
    final failedTp = results[1] as List<ThirdPartyPlatform>;

    // Only surface a renewal failure when we actually had a refresh token
    // to try (a no-op returning false is not an expiry).
    if (!mainOk && authService.session?.geekpieRefreshToken != null && !isIos()) {
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

    if (thirdPartyAuthService.hasEgateBinding) {
      await scheduleService.fetchAll();
    }
    if (authService.isLoggedIn || thirdPartyAuthService.boundPlatforms.isNotEmpty) {
      await assignmentService.fetchAssignments();
    }

    // Cloud-sync pull: if sync is enabled and this device has a cached master
    // key, silently pull the latest cloud bindings before any feature fetch
    // fires. If the device is enabled but has no key (new device with a cloud
    // backup), set the needsRestore flag so the UI can prompt for the master
    // password. All best-effort — sync failures never block boot.
    if (syncService.enabled && authService.isLoggedIn) {
      try {
        await syncService.pull();
      } on NeedMasterPassword {
        // Surface via the settings/banner UI; not a toast.
      } catch (_) {
        // Network/Casdoor hiccup — next manual sync retries.
      }
    }

    // All initial fetches done — now allow listener-triggered auto-refetch
    // so subsequent auth/binding changes don't double-fire.
    assignmentService.enableAutoRefetch();
  }());
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
  final SyncService syncService;
  final AiService aiService;

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
    required this.syncService,
    required this.aiService,
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
        syncService: widget.syncService,
        aiService: widget.aiService,
        child: MaterialApp(
          scaffoldMessengerKey: rootMessengerKey,
          title: 'TechPie',
          theme: _withAiExtension(widget.themeService.lightTheme),
          darkTheme: _withAiExtension(widget.themeService.darkTheme),
          themeMode: widget.themeService.themeMode,
          home: const AppShell(),
        ),
      ),
    );
  }
}

/// Registers an [AiThemeExtension] on the TechPie theme so the flutter_ai
/// widgets (AiResponse markdown, AiCodeBlock, etc.) pick up the active color
/// scheme instead of their built-in defaults. Without this they fall back to
/// `AiThemeExtension.fallback()`, whose dark code-block background clashes
/// with TechPie's surfaces.
ThemeData _withAiExtension(ThemeData base) {
  final cs = base.colorScheme;
  final isDark = base.brightness == Brightness.dark;
  final ai = (isDark ? AiThemeExtension.dark() : AiThemeExtension.fallback())
      .copyWith(
        // Prose follows the surface text color; code block sits on a surface
        // container tint with a contrasting foreground.
        assistantTextColor: cs.onSurface,
        userTextColor: cs.onSurface,
        codeBackgroundColor:
            isDark ? cs.surfaceContainerHighest : const Color(0xFF1E1E1E),
        codeForegroundColor:
            isDark ? cs.onSurface : const Color(0xFFE6E6E6),
        linkColor: cs.primary,
        accentColor: cs.primary,
        onAccentColor: cs.onPrimary,
      );
  return base.copyWith(extensions: [...base.extensions.values, ai]);
}
