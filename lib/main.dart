import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart'
    show runWebViewTitleBarWidget;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/utils/platform.dart';

import 'features/campus_card/app/app_providers.dart';
import 'models/third_party_account.dart';
import 'services/assignment_service.dart';
import 'services/auth_service.dart';
import 'services/campus/campus_clients.dart';
import 'services/campus/campus_file_share.dart';
import 'services/campus_card_service.dart';
import 'services/deadline_reminder_service.dart';
import 'services/deadline_widget_service.dart';
import 'services/debug_logger.dart';
import 'services/ecard_bind_service.dart';
import 'services/ecard_widget_service.dart';
import 'services/egate_app_service.dart';
import 'services/http_client.dart';
import 'services/ids/ids_client.dart';
import 'services/island_service.dart';
import 'services/oa_gym_service.dart';
import 'services/schedule_service.dart';
import 'services/service_provider.dart';
import 'services/spending_alert_service.dart';
import 'services/storage_service.dart';
import 'services/student_allowance_service.dart';
import 'services/study_plan_service.dart';
import 'services/sync_service.dart';
import 'services/theme_service.dart';
import 'services/third_party_auth_service.dart';
import 'services/uni_auth_service.dart';
import 'services/update_service.dart';
import 'services/usage_telemetry.dart';
import 'services/wear/android_wear_transport.dart';
import 'services/wear/techpie_wear_data_source.dart';
import 'services/wear/wear_engine_service.dart';
import 'services/wear/wear_protocol.dart';
import 'spending_background_refresh.dart';
import 'widgets/adaptive_feedback.dart';
import 'widgets/app_shell/app_shell.dart';
import 'widgets/privacy_consent.dart';
import 'widgets/update_dialogs.dart';

@pragma('vm:entry-point')
Future<void> spendingBackgroundRefresh() => runSpendingBackgroundRefresh();

void main(List<String> args) async {
  // If this Flutter engine is a desktop_webview_window title bar (secondary
  // engine inside the webview popup), render the navigation controls and
  // return early — do not start the full TechPie app.
  if (runWebViewTitleBarWidget(args)) return;

  WidgetsFlutterBinding.ensureInitialized();
  await initializePlatformCapabilities();
  await initializeCampusUserAgent();
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
  await storageService.migrateLegacyDefaultColorScheme();
  final package = await PackageInfo.fromPlatform();
  const collector = String.fromEnvironment(
    'TECHPIE_TELEMETRY_URL',
    defaultValue: 'https://techpie.geekpie.club/api/telemetry',
  );
  final telemetry = UsageTelemetry(
    prefs,
    endpoint: Uri.parse(collector),
    version: package.buildNumber.isEmpty
        ? package.version
        : '${package.version}+${package.buildNumber}',
    platform: kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
    existingInstall: storageService.privacyAccepted,
  );
  final configuredProxy =
      supportsInAppProxy() && storageService.appProxyEnabled
          ? normalizeAppProxy(storageService.appProxyUrl)
          : '';
  final activeProxy = isValidAppProxy(configuredProxy) ? configuredProxy : '';
  configureAppProxy(activeProxy);
  final debugLogger = DebugLogger()..enabled = storageService.debugMode;
  final httpClient = LoggingHttpClient(debugLogger);
  final uniAuthService = UniAuthService(
    logger: debugLogger,
    proxyUrl: activeProxy,
  );
  final authService = AuthService(
    storageService,
    httpClient,
    uniAuthService,
    logger: debugLogger,
  );
  final themeService = ThemeService(storageService);
  final campusCardService =
      CampusCardService(debugLogger: debugLogger, storage: storageService);
  final spendingAlertService = SpendingAlertService(storageService);
  final ecardBindService = EcardBindService();
  final ecardWidgetService = EcardWidgetService();
  final thirdPartyAuthService = ThirdPartyAuthService(
    storageService,
    httpClient,
    idsClient: IdsClient(logger: debugLogger),
  );
  final campusClients = CampusClients(
    authService,
    thirdPartyAuthService,
    onAccountChanged: () => unawaited(CampusFileShare.clearScopedFiles()),
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
  final isApple = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
  final assignmentService = AssignmentService(
    storageService,
    httpClient,
    authService,
    thirdPartyAuthService,
    scheduleService,
    syncReminders: isApple,
  );
  final wearSource = isAndroid()
      ? TechPieWearDataSource(
          auth: authService, accounts: thirdPartyAuthService,
          assignments: assignmentService, campusCard: campusCardService,
          timetable: scheduleService,
        )
      : null;
  final wearEngineService = wearSource == null ? null : WearEngineService(
    transport: AndroidWearTransport(), metadata: PreferencesWearMetadata(prefs),
    source: wearSource, offlineCredential: wearSource.offlineCredential,
    adoptCurrentSchedule: wearSource.adoptCurrentSchedule,
  );
  final islandService = IslandService(storageService, scheduleService, assignmentService);
  final deadlineWidgetService = DeadlineWidgetService(
    assignmentService,
    enabled: kIsWeb ||
        defaultTargetPlatform != TargetPlatform.linux ||
        storageService.deadlineWidgetsEnabled,
  );
  final deadlineReminderService =
      isApple ? DeadlineReminderService(assignmentService) : null;
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
    if (wearEngineService != null) {
      unawaited(
        wearEngineService.clear(reason: 'logout').catchError((Object error) {
          if (error is! WearFailure) throw error;
        }),
      );
    }
    // Third-party bindings persist across logouts — they will be used by the
    // sync system. Only clear ephemeral state.
    await assignmentService.clearCache();
    await assignmentService.clearAllOverrides();
    await storageService.clearCampusCaches();
    await CampusFileShare.clearScopedFiles();
    oaGymService.clearSession();
    await thirdPartyAuthService.campusWebSession.prepare();
  };

  // Cloud-sync push hook: after any binding mutation, best-effort push the new
  // state (throttled). Wired via post-construction setter to avoid a circular
  // dependency between ThirdPartyAuthService and SyncService.
  thirdPartyAuthService.onBindingsChanged = ({force = false}) {
    scheduleService.requestFetch();
    return force ? syncService.forcePush() : syncService.pushIfDue();
  };
  // Cloud-sync tombstone hook: record a deletion so the next LWW merge does
  // not resurrect an older remote copy of the unbound platform.
  thirdPartyAuthService.onUnbind = syncService.recordTombstone;

  // Cloud-sync pull hook: after a fresh SSO login, pull cloud bindings onto
  // this device (or surface the master-password restore prompt).
  authService.onLogin = () async {
    telemetry.firstLogin();
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
      telemetry: telemetry,
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
      campusClients: campusClients,
      campusCardService: campusCardService,
      ecardBindService: ecardBindService,
      ecardWidgetService: ecardWidgetService,
      wearEngineService: wearEngineService,
      deadlineWidgetService: deadlineWidgetService,
      deadlineReminderService: deadlineReminderService,
      spendingAlertService: spendingAlertService,
      islandService: islandService,
    ),
  );

  spendingAlertService.start(authService, campusCardService);
  bootMark('cached data ready');
  if (isApple || (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux)) {
    deadlineWidgetService.initialize();
  }

  islandService.start();
  oaGymService.startProfileSync();
  unawaited(campusCardService.refreshAccount());

  // The home-screen widget / shortcut only needs its handler once something
  // could press it — a widget tap on iOS/Android, a long-press shortcut on OHOS.
  if (isIos() || isAndroid() || isOhos()) ecardWidgetService.initialize();

  // Build the campus-card runtime now that the first frame is up, so tapping the
  // pass does not pay for it. Nothing session-related happens here: a request
  // that needs a session issues one itself.
  campusCardService.prepare();
  if (wearEngineService != null) {
    void accountChanged() => unawaited(wearEngineService.reconcileAccount());
    void deadlinesChanged() {
      if (wearEngineService.ready &&
          !assignmentService.loading &&
          (wearEngineService.getStatus()['capabilities'] as List)
              .contains('ddl.display')) {
        unawaited(
          wearEngineService.refresh(resources: ['ddl']).catchError(
            (Object error) {
              if (error is! WearFailure) throw error;
            },
          ),
        );
      }
    }

    void scheduleChanged() {
      if (wearEngineService.ready &&
          !scheduleService.loading &&
          wearEngineService.supports('schedule.display')) {
        unawaited(
          wearEngineService
              .refresh(resources: ['schedule']).catchError((Object error) {
            if (error is! WearFailure) throw error;
          }),
        );
      }
    }

    scheduleService.addListener(scheduleChanged);
    assignmentService.addListener(scheduleChanged);
    authService.addListener(accountChanged);
    thirdPartyAuthService.addListener(accountChanged);
    campusCardService.addListener(accountChanged);
    assignmentService.addListener(deadlinesChanged);
    unawaited(wearEngineService.reconcileAccount());
  }

  // -- Background: renew tokens first (main SSO session + third-party in
  // parallel — they touch independent state), then fan out fetches that
  // depend on those tokens. The whole block is unawaited so the splash
  // never blocks. --
  unawaited(() async {
    // Primary SSO renewal uses Casdoor's refresh-token grant. Only an explicit
    // grant rejection (`invalid_grant` / `invalid_token`) means the user's
    // login expired; legacy sessions without a refresh token and transient
    // offline/timeout/5xx errors must not trigger a re-login prompt.
    final renewMain = authService.isLoggedIn
        ? authService.tryRenewSession()
        : Future.value(SessionRenewalResult.skipped);
    final renewThirdParty = thirdPartyAuthService.autoRenewIfNeeded();

    final results = await Future.wait([renewMain, renewThirdParty]);
    final mainResult = results[0] as SessionRenewalResult;
    final failedTp = results[1] as List<ThirdPartyPlatform>;

    if (mainResult.isExpired && !isIos()) {
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

    if (thirdPartyAuthService.hasIdsBinding) {
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
  final UsageTelemetry? telemetry;
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
  final CampusClients? campusClients;
  final CampusCardService campusCardService;
  final EcardBindService ecardBindService;
  final EcardWidgetService? ecardWidgetService;
  final WearEngineService? wearEngineService;
  final DeadlineWidgetService? deadlineWidgetService;
  final DeadlineReminderService? deadlineReminderService;
  final SpendingAlertService? spendingAlertService;
  final IslandService? islandService;

  const TechPieApp({
    super.key,
    this.telemetry,
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
    this.campusClients,
    required this.campusCardService,
    required this.ecardBindService,
    this.ecardWidgetService,
    this.wearEngineService,
    this.deadlineWidgetService,
    this.deadlineReminderService,
    this.spendingAlertService,
    this.islandService,
  });

  @override
  State<TechPieApp> createState() => _TechPieAppState();
}

class _TechPieAppState extends State<TechPieApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _nativeChromeObserver = CNTabBarRouteObserver();
  late CampusClients _campusClients;
  bool _ownsCampusClients = false;
  late StudentAllowanceService _studentAllowanceService;

  void _initCampusClients() {
    final external = widget.campusClients;
    if (external != null) {
      _campusClients = external;
      _ownsCampusClients = false;
    } else {
      _campusClients = CampusClients(widget.authService, widget.thirdPartyAuthService);
      _ownsCampusClients = true;
    }
  }

  StudentAllowanceService _createStudentAllowanceService() => StudentAllowanceService(
        widget.authService,
        widget.thirdPartyAuthService,
        logger: widget.debugLogger,
      );

  late StudyPlanService _studyPlanService;
  StudyPlanService _createStudyPlanService() => StudyPlanService(
        _campusClients.eams,
        widget.storageService,
        _campusClients.eams.session.identity,
        Listenable.merge([widget.authService, widget.thirdPartyAuthService]),
      );

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
    _initCampusClients();
    widget.wearEngineService?.resumeSync();
    _studentAllowanceService = _createStudentAllowanceService();
    unawaited(_checkForUpdatesQuietly());
    widget.ecardWidgetService?.setOpenPayHandler(_openEcardPayCode);
    widget.deadlineWidgetService?.setOpenHandler(_openDeadlines);
    _studyPlanService = _createStudyPlanService();
    widget.deadlineReminderService?.initialize();
  }

  @override
  void didUpdateWidget(covariant TechPieApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clientsChanged = oldWidget.campusClients != widget.campusClients;
    if (clientsChanged) {
      if (_ownsCampusClients) _campusClients.dispose();
      _initCampusClients();
    } else if (_ownsCampusClients &&
        (oldWidget.authService != widget.authService ||
            oldWidget.thirdPartyAuthService != widget.thirdPartyAuthService)) {
      _campusClients.dispose();
      _initCampusClients();
    }
    if (oldWidget.authService != widget.authService ||
        oldWidget.thirdPartyAuthService != widget.thirdPartyAuthService ||
        oldWidget.debugLogger != widget.debugLogger) {
      _studentAllowanceService.dispose();
      _studentAllowanceService = _createStudentAllowanceService();
    }
    if (clientsChanged ||
        oldWidget.authService != widget.authService ||
        oldWidget.thirdPartyAuthService != widget.thirdPartyAuthService ||
        oldWidget.storageService != widget.storageService) {
      _studyPlanService.dispose();
      _studyPlanService = _createStudyPlanService();
    }
    if (oldWidget.deadlineWidgetService != widget.deadlineWidgetService) {
      oldWidget.deadlineWidgetService?.clearOpenHandler();
      widget.deadlineWidgetService?.setOpenHandler(_openDeadlines);
    }
    if (oldWidget.deadlineReminderService != widget.deadlineReminderService) {
      oldWidget.deadlineReminderService?.dispose();
      widget.deadlineReminderService?.initialize();
    }
    if (oldWidget.ecardWidgetService == widget.ecardWidgetService) return;
    oldWidget.ecardWidgetService?.clearOpenPayHandler();
    widget.ecardWidgetService?.setOpenPayHandler(_openEcardPayCode);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.ecardWidgetService?.clearOpenPayHandler();
    widget.deadlineWidgetService?.dispose();
    widget.deadlineReminderService?.dispose();
    widget.spendingAlertService?.dispose();
    _studyPlanService.dispose();
    widget.islandService?.dispose();
    _studentAllowanceService.dispose();
    if (_ownsCampusClients) _campusClients.dispose();
    widget.telemetry?.dispose();
    widget.campusCardService.dispose();
    widget.wearEngineService?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.telemetry?.opened();
      // Coming back is a cheap moment to top the SSO token up, and it is
      // guarded: a token with time left is left alone.
      widget.wearEngineService?.resumeSync();
      unawaited(widget.authService.tryRenewSession());
      unawaited(widget.spendingAlertService?.synchronize());
      unawaited(widget.islandService?.refreshNow(force: true));
      unawaited(_checkForUpdatesQuietly());
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      widget.wearEngineService?.suspendSync();
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

    // This State sits above the MaterialApp, so its own context has no
    // MaterialLocalizations and no navigator to put a dialog on; ask the app's
    // navigator instead.
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;
    _promptedThisLaunch = true;
    await showUpdateAvailableDialog(dialogContext, release);
  }

  Future<void> _openDeadlines() async {
    // Only dialogs and sheets are dismissed: a login or player covering the
    // shell stays, and back from it lands on the Deadlines tab.
    _navigatorKey.currentState?.popUntil((route) => route is! PopupRoute);
    appShellPendingDeadlines.value = true;
  }

  Future<void> _openEcardPayCode() async {
    // The shell performs the push: it knows which stack the entry belongs in —
    // the Home tab's on iOS — and it is still there after a cold start.
    _navigatorKey.currentState?.popUntil((route) => route is! PopupRoute);
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
        telemetry: widget.telemetry,
        studyPlanService: _studyPlanService,
        themeService: widget.themeService,
        scheduleService: widget.scheduleService,
        assignmentService: widget.assignmentService,
        thirdPartyAuthService: widget.thirdPartyAuthService,
        oaGymService: widget.oaGymService,
        egateAppService: widget.egateAppService,
        campusClients: _campusClients,
        studentAllowanceService: _studentAllowanceService,
        uniAuthService: widget.uniAuthService,
        syncService: widget.syncService,
        updateService: widget.updateService,
        campusCardService: widget.campusCardService,
        ecardBindService: widget.ecardBindService,
        ecardWidgetService: widget.ecardWidgetService,
        wearEngineService: widget.wearEngineService,
        deadlineWidgetService: widget.deadlineWidgetService,
        deadlineReminderService: widget.deadlineReminderService,
        spendingAlertService: widget.spendingAlertService,
        islandService: widget.islandService,
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: rootMessengerKey,
          navigatorObservers: [FeedbackRouteObserver(), _nativeChromeObserver],
          builder: (context, child) => AdaptiveFeedbackHost(
            key: adaptiveFeedbackHostKey,
            child: child ?? const SizedBox.shrink(),
          ),
          title: 'TechPie',
          theme: widget.themeService.lightTheme,
          darkTheme: widget.themeService.darkTheme,
          themeMode: widget.themeService.themeMode,
          home: const PrivacyGate(child: AppShell()),
        ),
      ),
    );
  }
}
