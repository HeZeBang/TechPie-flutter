import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart'
    show runWebViewTitleBarWidget;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/utils/platform.dart';

import 'features/campus_card/app/app_providers.dart';
import 'models/third_party_account.dart';
import 'services/assignment_service.dart';
import 'services/auth_service.dart';
import 'services/campus_card_service.dart';
import 'services/debug_logger.dart';
import 'services/ecard_bind_service.dart';
import 'services/ecard_widget_service.dart';
import 'services/egate_app_service.dart';
import 'services/http_client.dart';
import 'services/oa_gym_service.dart';
import 'services/schedule_service.dart';
import 'services/service_provider.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'services/theme_service.dart';
import 'services/third_party_auth_service.dart';
import 'services/uni_auth_service.dart';
import 'services/update_service.dart';
import 'widgets/adaptive_feedback.dart';
import 'widgets/app_shell/app_shell.dart';
import 'widgets/update_dialogs.dart';
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
  final campusCardService = CampusCardService(debugLogger: debugLogger, storage: storageService);
  final ecardBindService = EcardBindService();
  final ecardWidgetService = EcardWidgetService();
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
  final egateAppService = EgateAppService(
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
  final syncService = SyncService(
    authService,
    thirdPartyAuthService,
    storageService,
    ecard: campusCardService,
    logger: debugLogger,
  );
  campusCardService.onBindingChanged = syncService.forcePush;
  // It talks to GitHub rather than our backend, so it keeps its own client
  // instead of the logging one the API services share.
  final updateService = UpdateService();

  authService.onLogout = () async {
    // Third-party bindings persist across logouts — they will be used by the
    // sync system. Only clear ephemeral state.
    await assignmentService.clearCache();
    await assignmentService.clearAllOverrides();
    oaGymService.clearSession();
    await thirdPartyAuthService.campusWebSession.prepare();
  };

  // Cloud-sync push hook: after any binding mutation, best-effort push the new
  // state (throttled). Wired via post-construction setter to avoid a circular
  // dependency between ThirdPartyAuthService and SyncService.
  thirdPartyAuthService.onBindingsChanged = ({force = false}) {
    // The timetable is drawn from the eGate binding, and `fetchAll` does nothing
    // at all while there is none — silently, which is how a freshly bound account
    // used to sit on an empty table with nothing to suggest it should reload. This
    // runs for every binding, though, and a timetable does not care about
    // Gradescope: requestFetch is what decides whether the campus account this
    // data belongs to actually changed, and collapses the burst around a login
    // into one round.
    scheduleService.requestFetch();
    return force ? syncService.forcePush() : syncService.pushIfDue();
  };
  // Cloud-sync tombstone hook: record a deletion so the next LWW merge does
  // not resurrect an older remote copy of the unbound platform.
  thirdPartyAuthService.onUnbind = syncService.recordTombstone;

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

  // Boot timings, debug only: this is exactly what the splash waits for. Work
  // that the first frame does not need belongs after `runApp` below.
  final bootWatch = Stopwatch()..start();
  void bootMark(String phase) {
    if (!kDebugMode) return;
    debugPrint('[BOOT] $phase ${bootWatch.elapsedMilliseconds}ms');
  }

  bootMark('services built');

  // -- Boot critical path: local I/O only --
  // Hydrate everything from caches so the first frame paints with data.
  await authService.loadSession();
  await thirdPartyAuthService.initialize();
  thirdPartyAuthService.campusWebSession.attachAuth(authService);
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
      egateAppService: egateAppService,
      uniAuthService: uniAuthService,
      syncService: syncService,
      updateService: updateService,
      campusCardService: campusCardService,
      ecardBindService: ecardBindService,
      ecardWidgetService: ecardWidgetService,
    ),
  );

  bootMark('cached data ready');

  unawaited(campusCardService.refreshAccount());

  // The home-screen widget only needs its handler once something could press it.
  if (isIos() || isAndroid()) ecardWidgetService.initialize();

  // Build the campus-card runtime now that the first frame is up, so tapping the
  // pass does not pay for it. Nothing session-related happens here: a request
  // that needs a session issues one itself.
  campusCardService.prepare();

  // -- Background: renew tokens first (main SSO session + third-party in
  // parallel — they touch independent state), then fan out fetches that
  // depend on those tokens. The whole block is unawaited so the splash
  // never blocks. --
  unawaited(() async {
    // Primary SSO renewal uses Casdoor's refresh-token grant. With no
    // refresh token (legacy session) this is a no-op and returns false —
    // that is NOT a "login expired" condition, only an actual renewal
    // failure is.
    final renewMain = authService.isLoggedIn
        ? authService.tryRenewSession()
        : Future.value(true);
    final renewThirdParty = thirdPartyAuthService.autoRenewIfNeeded();

    final results = await Future.wait([renewMain, renewThirdParty]);
    final mainOk = results[0] as bool;
    final failedTp = results[1] as List<ThirdPartyPlatform>;

    // Only surface a renewal failure when we actually had a refresh token
    // to try (a no-op returning false is not an expiry).
    if (!mainOk &&
        authService.session?.geekpieRefreshToken != null &&
        !isIos()) {
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

    if (thirdPartyAuthService.hasCpdailyBinding) {
      // Through the funnel: the token renewals just above fire the same trigger,
      // and this used to be a second round on top of theirs.
      scheduleService.requestFetch(force: true);
    }
    if (authService.isLoggedIn ||
        thirdPartyAuthService.boundPlatforms.isNotEmpty) {
      await assignmentService.fetchAssignments();
    }

    // Cloud-sync pull: if sync is enabled and this device has a cached master
    // key, silently pull the latest cloud bindings before any feature fetch
    // fires. If the device is enabled but has no key (new device with a cloud
    // backup), set the needsRestore flag so the UI can prompt for the master
    // password. All best-effort — sync failures never block boot.
    await syncService.loadCachedKey();

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
  final EgateAppService egateAppService;
  final UniAuthService uniAuthService;
  final SyncService syncService;
  final UpdateService updateService;
  final CampusCardService campusCardService;
  final EcardBindService ecardBindService;
  final EcardWidgetService? ecardWidgetService;

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
    required this.egateAppService,
    required this.uniAuthService,
    required this.syncService,
    required this.updateService,
    required this.campusCardService,
    required this.ecardBindService,
    this.ecardWidgetService,
  });

  @override
  State<TechPieApp> createState() => _TechPieAppState();
}

class _TechPieAppState extends State<TechPieApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  /// The silent check runs at launch and whenever the app comes back to the
  /// foreground, but not more often than this: a resume is not a reason to hit
  /// the network, and the answer does not change that fast.
  static const _autoCheckInterval = Duration(minutes: 30);

  DateTime? _lastAutoCheck;
  bool _promptedThisLaunch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkForUpdatesQuietly());
    widget.ecardWidgetService?.setOpenPayHandler(_openEcardPayCode);
  }

  @override
  void didUpdateWidget(covariant TechPieApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ecardWidgetService == widget.ecardWidgetService) return;
    oldWidget.ecardWidgetService?.clearOpenPayHandler();
    widget.ecardWidgetService?.setOpenPayHandler(_openEcardPayCode);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.ecardWidgetService?.clearOpenPayHandler();
    widget.campusCardService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkForUpdatesQuietly());
    }
  }

  /// The check nobody asked for.
  ///
  /// It may raise the update dialog, and says nothing else: a network the user
  /// cannot do anything about is not worth interrupting them over, and the manual
  /// check — the one they did ask for — reports all of it, with a way out.
  Future<void> _checkForUpdatesQuietly() async {
    final now = DateTime.now();
    final last = _lastAutoCheck;
    if (last != null && now.difference(last) < _autoCheckInterval) return;
    _lastAutoCheck = now;
    // One prompt per launch: a dialog that reappears on every resume is worse
    // than not mentioning the update at all.
    if (_promptedThisLaunch) return;

    final current = await UpdateService.currentProductVersion();
    if (current == null || !mounted) return;

    final ReleaseInfo? release;
    try {
      release = await widget.updateService.checkForUpdate(current);
    } on UpdateCheckException {
      return;
    }
    if (release == null || !mounted) return;

    _promptedThisLaunch = true;
    await showUpdateAvailableDialog(context, release);
  }

  Future<void> _openEcardPayCode() async {
    // The shell performs the push: it knows whether the entry belongs inside the
    // selected destination's stack or on the root navigator, and it is still
    // there after a cold start.
    appShellPendingEcardEntry.value = CampusCardEntry.paymentCode;
  }

  @override
  Widget build(BuildContext context) {
    // The plugin has no implementation on iOS, web or OHOS, where asking for
    // the palette throws a MissingPluginException the builder does not catch.
    if (!supportsSystemDynamicColor()) return _buildApp();
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
        egateAppService: widget.egateAppService,
        uniAuthService: widget.uniAuthService,
        syncService: widget.syncService,
        updateService: widget.updateService,
        campusCardService: widget.campusCardService,
        ecardBindService: widget.ecardBindService,
        ecardWidgetService: widget.ecardWidgetService,
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: rootMessengerKey,
          navigatorObservers: [FeedbackRouteObserver()],
          builder: (context, child) => AdaptiveFeedbackHost(
            key: adaptiveFeedbackHostKey,
            child: child ?? const SizedBox.shrink(),
          ),
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
