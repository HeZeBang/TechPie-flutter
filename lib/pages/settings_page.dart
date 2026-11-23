import 'dart:async';
import 'dart:ui';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/third_party_account.dart';
import '../services/api_base_url.dart';
import '../services/deadline_widget_service.dart';
import '../services/feedback_service.dart';
import '../services/http_client.dart';
import '../services/island_service.dart';
import '../services/service_provider.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/theme_service.dart';
import '../services/uni_auth_service.dart';
import '../services/update_service.dart';
import '../utils/adaptive_layout.dart';
import '../utils/platform.dart';
import '../utils/product_version.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_confirmation_button.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/adaptive_switch.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/desktop_popup.dart';
import '../widgets/ids_rebind_banner.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/uni_auth_login.dart';
import '../widgets/update_dialogs.dart';
import 'account_deletion_page.dart';
import 'debug_log_page.dart';
import 'debug_webview_page.dart';
import 'developer_lab_page.dart';
import 'feedback_page.dart';
import 'sync_settings_page.dart';
import 'third_party_accounts_page.dart';
import 'third_party_bind_page.dart';
import 'watch_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '';
  bool _checkingUpdate = false;
  bool? _isPersonalInfoBlurred;
  bool _wasVisible = false;
  IslandCapability? _islandCapability;

  /// The stack a settings subpage is pushed onto in a wide window. A field, not
  /// a local: a GlobalKey rebuilt every frame would drop the stack with it.
  final _nestedNavigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppVersion());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ignore: deprecated_member_use
    final isVisible = TickerMode.of(context);
    if (isVisible && !_wasVisible) {
      _isPersonalInfoBlurred =
          ServiceProvider.of(context).storageService.maskPersonalInfo;
    }
    if (isVisible && !_wasVisible) unawaited(_loadIslandCapability());
    _wasVisible = isVisible;
  }

  Future<void> _loadIslandCapability() async {
    final island = ServiceProvider.of(context).islandService;
    if (island == null || !island.supported) return;
    final capability = await island.capability();
    if (mounted) setState(() => _islandCapability = capability);
  }

  Future<void> _setIslandEnabled(IslandService island, bool value) async {
    await island.setEnabled(value);
    if (!mounted) return;
    setState(() {});
    await _loadIslandCapability();
  }

  Future<void> _setDeadlineWidgetsEnabled(
    StorageService storage,
    DeadlineWidgetService widgetService,
    bool value,
  ) async {
    await storage.setDeadlineWidgetsEnabled(value);
    await widgetService.setEnabled(value);
    if (mounted) setState(() {});
  }

  String get _islandSubtitle {
    final capability = _islandCapability;
    if (capability == null) return '显示当前课程、下一节课和即将到期的截止日期';
    if (!capability.notificationsEnabled) return '请允许 TechPie 发送通知';
    return switch (capability.backend) {
      'hyper_island' => '通过 HyperOS 超级岛显示',
      'live_update' => '通过 Android 实时通知显示',
      _ => '通过普通常驻通知显示',
    };
  }

  void _togglePersonalInfoBlur() {
    setState(() {
      _isPersonalInfoBlurred = !(_isPersonalInfoBlurred ?? true);
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      if (info.version.isEmpty) {
        // The tile would read "Version Unknown" with no clue why: the plugin
        // resolves but its source (an OHOS bundle, Linux's version.json) came
        // back empty.
        debugPrint(
          'PackageInfo returned an empty version '
          '(appName="${info.appName}", packageName="${info.packageName}", '
          'buildNumber="${info.buildNumber}")',
        );
      }
      setState(() {
        _appVersion = info.buildNumber.isNotEmpty
            ? '${info.version}+${info.buildNumber}'
            : info.version;
      });
    } catch (error) {
      // Never let the tile's failure take the page down, but do say why.
      debugPrint('PackageInfo.fromPlatform failed: $error');
    }
  }

  /// Checks GitHub for a release newer than the one running, and offers it.
  ///
  /// The answer comes from the releases page rather than our backend, so it
  /// keeps working when the backend does not and needs no account. Cancelling
  /// the offer changes nothing; accepting it opens the release page, where the
  /// build for this platform lives.
  Future<void> _checkForUpdate() async {
    final updateService = ServiceProvider.of(context).updateService;
    final current = ProductVersion.tryParse(_appVersion);
    if (current == null) {
      await showAdaptiveAlertDialog<void>(
        context: context,
        title: '无法检查更新',
        message: '当前版本号（$_appVersion）无法识别，没法与 GitHub 上的版本比较。',
        actions: const [AdaptiveAlertAction<void>(label: '好')],
      );
      return;
    }

    setState(() => _checkingUpdate = true);
    try {
      final release = await updateService.checkForUpdate(current);
      if (!mounted) return;

      if (release == null) {
        await showUpToDateDialog(context, _appVersion);
        return;
      }
      await showUpdateAvailableDialog(context, release);
    } on UpdateCheckException catch (error) {
      if (!mounted) return;
      // The manual check is the one that reports everything, including the way
      // out that does not depend on this app reaching GitHub at all.
      await showUpdateFailureDialog(context, message: error.message);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (usesSidebarLayout(context)) {
      // A wide window gives the settings subpages their own stack, which is what
      // makes them feel like pages rather than a full-screen push. The system back
      // has to be told about that stack: without NavigatorPopHandler the gesture
      // goes to the root navigator, which shows the shell and has nothing to pop,
      // so it closes the app instead of leaving the subpage.
      return NavigatorPopHandler(
        onPopWithResult: (_) => _nestedNavigatorKey.currentState?.pop(),
        child: Navigator(
          key: _nestedNavigatorKey,
          onGenerateRoute: (settings) => adaptivePageRoute<void>(
            settings: settings,
            builder: (context) => _buildSettingsScaffold(context),
          ),
        ),
      );
    }

    return _buildSettingsScaffold(context);
  }

  Widget _buildSettingsScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final logger = sp.debugLogger;
    final storage = sp.storageService;
    final themeService = sp.themeService;
    final tpAuth = sp.thirdPartyAuthService;
    final campusCard = sp.campusCardService;
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return AdaptiveNavigationScaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? const IosNativeNavigationBar(
              title: 'Settings',
              largeTitleMode: true,
            )
          : const BlurredAppBar(title: Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          auth,
          logger,
          themeService,
          tpAuth,
          campusCard,
          sp.syncService,
          if (sp.spendingAlertService != null) sp.spendingAlertService!,
        ]),
        builder: (context, _) {
          final session = auth.session;
          return ListView(
            padding: EdgeInsets.only(
              top: topInset,
              bottom: AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              if (tpAuth.needsIdsRebind || storage.debugForceIdsRebindBanner)
                IdsRebindBanner(onRebind: () => unawaited(pushAdaptivePage<void>(
                  context, builder: (_) => const ThirdPartyBindPage(platform: ThirdPartyPlatform.ids),
                ),),),
              // Account section
              _sectionHeader(theme, 'Account'),
              if (session != null) ...[
                Semantics(
                  button: true,
                  label: (_isPersonalInfoBlurred ?? true)
                      ? 'Personal info hidden, tap to show'
                      : 'Personal info shown, tap to hide',
                  child: ListTile(
                    leading: const Icon(Icons.person),
                    title: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      enabled: _isPersonalInfoBlurred ?? true,
                      child: Text(
                        session.userName.isNotEmpty
                            ? session.userName
                            : session.userId,
                      ),
                    ),
                    subtitle: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      enabled: _isPersonalInfoBlurred ?? true,
                      child: Text(
                        [
                          'GeekPie Uni-Auth',
                          if (session.userId.isNotEmpty) session.userId,
                        ].join(' · '),
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        (_isPersonalInfoBlurred ?? true)
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      tooltip: (_isPersonalInfoBlurred ?? true)
                          ? 'Show personal info'
                          : 'Hide personal info',
                      onPressed: _togglePersonalInfoBlur,
                    ),
                    onTap: _togglePersonalInfoBlur,
                  ),
                ),
              ],
            if (auth.isLoggedIn) ...[
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('Cloud sync'),
                subtitle: Text(_cloudSyncSubtitle(sp.syncService)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(
                  pushAdaptivePage<void>(
                    context,
                    builder: (_) => const SyncSettingsPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_remove_outlined),
                title: const Text('注销账号'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(
                  pushAdaptivePage<void>(
                    context,
                    builder: (_) => AccountDeletionPage(auth: auth),
                  ),
                ),
              ),
              if (useIosChrome)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: AdaptiveConfirmationButton(
                    label: 'Logout',
                    icon: Icons.logout,
                    sfSymbol: 'rectangle.portrait.and.arrow.right',
                    confirmTitle: '退出登录？',
                    confirmLabel: '退出登录',
                    destructive: true,
                    width: double.infinity,
                    height: 44,
                    onConfirmed: () => unawaited(auth.logout()),
                  ),
                )
              else
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Logout'),
                  onTap: () => unawaited(_confirmLogout(auth)),
                ),
            ] else if (useIosChrome)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: AdaptiveButton(
                  icon: Icons.login,
                  sfSymbol: 'person.crop.circle.badge.plus',
                  label: '通过 GeekPie Uni-Auth 登录',
                  role: AdaptiveButtonRole.prominent,
                  accessibilityLabel: '登录 TechPie',
                  onPressed: () => unawaited(startUniAuthLogin(context)),
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Login'),
                subtitle: const Text('通过 GeekPie Uni-Auth 登录'),
                onTap: () => unawaited(startUniAuthLogin(context)),
              ),
            // Bindings are configured independently of the primary account, so
            // this row sits outside the signed-in block (it replaces the old
            // OPENID row, which was reachable the same way).
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('Linked accounts'),
              subtitle: Text(
                '${tpAuth.boundPlatforms.length + (campusCard.configured ? 1 : 0)} bound · eCard / eGate / Gradescope / Hydro',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => unawaited(
                pushAdaptivePage<void>(
                  context,
                  builder: (_) => const ThirdPartyAccountsPage(),
                ),
              ),
            ),
            const Divider(),

            ListTile(
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('问题反馈 / 功能建议'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (!auth.isLoggedIn) await startUniAuthLogin(context);
                if (!context.mounted || !auth.isLoggedIn) return;
                await pushAdaptivePage<void>(
                  context,
                  builder: (_) => FeedbackPage(
                    service: FeedbackService(auth, apiBaseUrl(sp.storageService)),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('隐私政策与使用支持'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => unawaited(
                launchUrl(
                  Uri.parse('https://techpie.geekpie.club/privacy'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
            const Divider(),
            if (isIos())
              ListTile(
                leading: const Icon(Icons.watch_outlined),
                title: const Text('Apple Watch'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(
                  pushAdaptivePage<void>(context,
                      builder: (_) => const WatchSettingsPage(),),
                ),
              ),

            // Appearance section
            _sectionHeader(theme, 'Appearance'),
            if (useIosChrome)
              ListTile(
                leading: Icon(themeService.mode.icon),
                title: const Text('Theme'),
                // The menu button shows the value; a subtitle would repeat it.
                trailing: AdaptiveSelect(
                  value: themeService.mode.name,
                  placeholder: 'Choose theme',
                  accessibilityLabel: 'Theme',
                  shrinkWrap: true,
                  options: [
                    for (final mode in AppThemeMode.values)
                      AdaptiveSelectOption(
                        value: mode.name,
                        label: mode.label,
                        sfSymbol: switch (mode) {
                          AppThemeMode.system => 'circle.lefthalf.filled',
                          AppThemeMode.light => 'sun.max',
                          AppThemeMode.dark => 'moon',
                          AppThemeMode.amoled => 'moon.fill',
                        },
                      ),
                  ],
                  onChanged: (value) {
                    final mode = AppThemeMode.values.firstWhere(
                      (item) => item.name == value,
                      orElse: () => AppThemeMode.system,
                    );
                    unawaited(themeService.setMode(mode));
                  },
                ),
              )
            else
              Builder(
                builder: (tileContext) => ListTile(
                  leading: Icon(themeService.mode.icon),
                  title: const Text('Theme'),
                  subtitle: Text(themeService.mode.label),
                  onTap: () => _showThemePicker(tileContext, themeService),
                ),
              ),
            if (themeService.supportsColorSchemeSelection)
              Builder(
                builder: (tileContext) => ListTile(
                  leading: Icon(themeService.colorScheme.icon),
                  title: const Text('Color'),
                  subtitle: Text(_colorSubtitle(themeService)),
                  onTap: () => _showColorPicker(tileContext, themeService),
                ),
              ),
            const Divider(),

            // General section
            _sectionHeader(theme, 'General'),
            if (!kIsWeb &&
                defaultTargetPlatform == TargetPlatform.linux &&
                sp.deadlineWidgetService != null)
              _AdaptiveSwitchTile(
                key: const ValueKey('settings.deadline-widgets'),
                usesIosLiquidGlass: useIosChrome,
                secondary: const Icon(Icons.widgets_outlined),
                title: 'Deadline widgets',
                subtitle: 'Share task titles and dates with your desktop. '
                    'Widgets use cached data while TechPie is closed.',
                value: storage.deadlineWidgetsEnabled,
                onChanged: (value) => unawaited(
                  _setDeadlineWidgetsEnabled(
                    storage,
                    sp.deadlineWidgetService!,
                    value,
                  ),
                ),
              ),
            if (sp.islandService case final island? when island.supported)
              _AdaptiveSwitchTile(
                key: const ValueKey('settings.island'),
                usesIosLiquidGlass: useIosChrome,
                secondary: const Icon(Icons.notifications_active_outlined),
                title: '课程与截止日期通知',
                subtitle: _islandSubtitle,
                value: storage.islandEnabled,
                onChanged: (value) => unawaited(_setIslandEnabled(island, value)),
              ),
            if (sp.spendingAlertService case final spending? when spending.supported)
              _AdaptiveSwitchTile(
                key: const ValueKey('settings.spending-alerts'),
                usesIosLiquidGlass: useIosChrome,
                secondary: const Icon(Icons.notifications_active_outlined),
                title: '校园卡消费提醒',
                subtitle: '刷新发现新消费时通知；后台检查受系统调度限制',
                value: spending.enabled,
                onChanged: (value) => unawaited(spending.setEnabled(value)),
              ),
            _AdaptiveSwitchTile(
              key: const ValueKey('settings.mask-personal-info'),
              usesIosLiquidGlass: useIosChrome,
              secondary: const Icon(Icons.visibility_off_outlined),
              title: 'Mask personal info',
              subtitle: 'Blur sensitive profile details by default',
              value: storage.maskPersonalInfo,
              onChanged: (value) {
                unawaited(storage.setMaskPersonalInfo(value));
                setState(() {
                  _isPersonalInfoBlurred = value;
                });
              },
            ),
            if (!kIsWeb) ...[
              ListTile(
                key: const ValueKey('settings.app-proxy-address'),
                leading: const Icon(Icons.lan_outlined),
                title: const Text('Application proxy'),
                subtitle: Text(
                  storage.appProxyEnabled && storage.appProxyUrl.isNotEmpty
                      ? storage.appProxyUrl
                      : (storage.appProxyUrl.isNotEmpty
                          ? '${storage.appProxyUrl} (Disabled)'
                          : 'System default'),
                ),
                onTap: () =>
                    unawaited(_showProxySettings(storage, sp.uniAuthService)),
              ),
              _AdaptiveSwitchTile(
                key: const ValueKey('settings.app-proxy-enabled'),
                usesIosLiquidGlass: useIosChrome,
                secondary: const Icon(Icons.power_settings_new),
                title: 'Enable application proxy',
                subtitle: 'Route requests through the configured HTTP proxy',
                value: storage.appProxyEnabled && storage.appProxyUrl.isNotEmpty,
                onChanged: (value) => unawaited(
                  _setProxyEnabled(storage, sp.uniAuthService, value),
                ),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              subtitle: Text(
                _appVersion.isEmpty
                    ? 'Version Unknown'
                    : 'Version $_appVersion',
              ),
              // Tapping the version is the whole affordance: it is where a user
              // looks when they wonder whether they are up to date.
              trailing: _checkingUpdate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onTap: _appVersion.isEmpty || _checkingUpdate
                  ? null
                  : () => unawaited(_checkForUpdate()),
            ),
            if (!kReleaseMode) const Divider(),

            // Developer section
            if (!kReleaseMode) _sectionHeader(theme, 'Developer'),
            if (!kReleaseMode)
              _AdaptiveSwitchTile(
                key: const ValueKey('settings.ids-rebind-preview'),
                usesIosLiquidGlass: useIosChrome,
                secondary: const Icon(Icons.key_outlined),
                title: '强制显示 IDS 重绑横幅',
                subtitle: '仅用于调试迁移提示',
                value: storage.debugForceIdsRebindBanner,
                onChanged: (value) {
                  unawaited(storage.setDebugForceIdsRebindBanner(value));
                  setState(() {});
                },
              ),
            if (!kReleaseMode)
              _AdaptiveSwitchTile(
                key: const ValueKey('settings.debug-mode'),
                usesIosLiquidGlass: useIosChrome,
                secondary: const Icon(Icons.bug_report_outlined),
                title: 'Debug mode',
                subtitle: 'Log all API requests',
                value: logger.enabled,
                onChanged: (value) {
                  logger.enabled = value;
                  unawaited(storage.setDebugMode(value));
                },
              ),
            if (!kReleaseMode)
              _AdaptiveSwitchTile(
                key: const ValueKey('settings.use-localhost'),
                usesIosLiquidGlass: useIosChrome,
                secondary: const Icon(Icons.dns_outlined),
                title: 'Use localhost',
                subtitle: isAndroid()
                    ? 'Connect to local server via 10.0.2.2:3000'
                    : 'Connect to local development server',
                value: storage.useLocalhost,
                onChanged: (value) {
                  unawaited(storage.setUseLocalhost(value));
                  setState(() {});
                },
              ),
            if (!kReleaseMode)
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('WebView Test'),
                subtitle: const Text('Bridge injection and custom URL testing'),
                onTap: () => unawaited(
                  pushAdaptivePage<void>(
                    context,
                    builder: (_) => const DebugWebViewPage(
                      initialUrl: 'http://127.0.0.1:8000/bridge_test.html',
                    ),
                  ),
                ),
              ),
            if (!kReleaseMode)
              ListTile(
                leading: const Icon(Icons.vibration),
                title: const Text('Developer Lab'),
                subtitle: const Text('Play every waveform and sound'),
                onTap: () => unawaited(
                  pushAdaptivePage<void>(
                    context,
                    builder: (_) => const DeveloperLabPage(),
                  ),
                ),
              ),
            if (!kReleaseMode && logger.enabled)
              ListTile(
                leading: const Icon(Icons.list_alt),
                title: const Text('View Logs'),
                subtitle: Text('${logger.entries.length} entries'),
                onTap: () => unawaited(
                  pushAdaptivePage<void>(
                    context,
                    builder: (_) => const DebugLogPage(),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
  }

  Future<void> _confirmLogout(AuthService auth) async {
    final ok = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '退出登录',
      message: '将清除当前设备上的登录状态和相关缓存数据。',
      actions: const [
        AdaptiveAlertAction<bool>(label: '取消', value: false),
        AdaptiveAlertAction<bool>(
          label: '退出登录',
          value: true,
          isDestructive: true,
        ),
      ],
    );

    if (ok == true) {
      await auth.logout();
    }
  }

  Future<void> _setProxyEnabled(
    StorageService storage,
    UniAuthService uniAuth,
    bool value,
  ) async {
    if (value) {
      final normalized = normalizeAppProxy(storage.appProxyUrl);
      if (!isValidAppProxy(normalized)) {
        await _showProxySettings(storage, uniAuth);
        return;
      }
      await storage.setAppProxyUrl(normalized);
      await storage.setAppProxyEnabled(true);
      configureAppProxy(normalized);
      uniAuth.setProxyUrl(normalized);
    } else {
      await storage.setAppProxyEnabled(false);
      configureAppProxy('');
      uniAuth.setProxyUrl('');
    }
    if (mounted) setState(() {});
  }

  Future<void> _showProxySettings(
    StorageService storage,
    UniAuthService uniAuth,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _ProxySettingsDialog(initialValue: storage.appProxyUrl),
    );
    if (value == null || !mounted) return;
    final proxy = normalizeAppProxy(value);
    if (proxy.isNotEmpty && !isValidAppProxy(proxy)) {
      await showAdaptiveAlertDialog<void>(
        context: context,
        title: 'Invalid proxy',
        message: 'Use host:port, for example 127.0.0.1:7890.',
        actions: const [AdaptiveAlertAction<void>(label: 'OK')],
      );
      return;
    }
    await storage.setAppProxyUrl(proxy);
    await storage.setAppProxyEnabled(proxy.isNotEmpty);
    configureAppProxy(proxy);
    uniAuth.setProxyUrl(proxy);
    if (mounted) setState(() {});
  }

  void _showThemePicker(BuildContext context, ThemeService themeService) {
    if (usesSidebarLayout(context)) {
      showDesktopPopover(
        anchorContext: context,
        width: 260,
        placement: DesktopPopoverPlacement.belowEnd,
        offset: const Offset(0, 8),
        scrollable: true,
        builder: (context, close) {
          final theme = Theme.of(context);
          return DesktopPopoverSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text(
                    'Choose theme',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const Divider(height: 1),
                _ThemeModeOptions(
                  themeService: themeService,
                  desktop: true,
                  onSelected: (mode) {
                    unawaited(themeService.setMode(mode));
                    close();
                  },
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    unawaited(
      CNBottomSheet.show<void>(
        context: context,
        useRootNavigator: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Choose theme',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _ThemeModeOptions(
                themeService: themeService,
                onSelected: (mode) {
                  unawaited(themeService.setMode(mode));
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _colorSubtitle(ThemeService themeService) {
    if (themeService.colorScheme == AppColorScheme.system) {
      if (themeService.usesIosSystemAccent) {
        return 'System Blue';
      }
      if (!themeService.systemDynamicColorAvailable) {
        return '${themeService.colorScheme.label} (unavailable, using TechRed)';
      }
    }
    return themeService.colorScheme.label;
  }

  void _showColorPicker(BuildContext context, ThemeService themeService) {
    if (usesSidebarLayout(context)) {
      showDesktopPopover(
        anchorContext: context,
        width: 260,
        placement: DesktopPopoverPlacement.belowEnd,
        offset: const Offset(0, 8),
        builder: (context, close) {
          final theme = Theme.of(context);
          return DesktopPopoverSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text(
                    'Choose color',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const Divider(height: 1),
                for (final scheme in AppColorScheme.values)
                  DesktopMenuRow(
                    leading: Icon(scheme.icon, size: 20),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            scheme.label,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        if (themeService.colorScheme == scheme)
                          Icon(
                            Icons.check,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                    onTap: () {
                      unawaited(themeService.setColorScheme(scheme));
                      close();
                    },
                  ),
              ],
            ),
          );
        },
      );
      return;
    }

    unawaited(
      CNBottomSheet.show<void>(
        context: context,
        useRootNavigator: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Choose color',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final scheme in AppColorScheme.values)
                ListTile(
                  leading: Icon(scheme.icon),
                  title: Text(scheme.label),
                  trailing: themeService.colorScheme == scheme
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    unawaited(themeService.setColorScheme(scheme));
                    Navigator.pop(context);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  String _cloudSyncSubtitle(SyncService sync) {
    if (!sync.enabled) return '未开启';
    final at = sync.lastSyncAt;
    if (at == null) return '已开启 · 尚未同步';
    return '已开启 · 上次同步 ${_shortTime(at)}';
  }

  String _shortTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _ThemeModeOptions extends StatelessWidget {
  const _ThemeModeOptions({
    required this.themeService,
    required this.onSelected,
    this.desktop = false,
  });

  final ThemeService themeService;
  final ValueChanged<AppThemeMode> onSelected;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in AppThemeMode.values)
          if (desktop)
            DesktopMenuRow(
              leading: Icon(mode.icon, size: 20),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      mode.label,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (themeService.mode == mode)
                    Icon(
                      Icons.check,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
              onTap: () => onSelected(mode),
            )
          else
            ListTile(
              leading: Icon(mode.icon),
              title: Text(mode.label),
              trailing: themeService.mode == mode
                  ? Icon(
                      Icons.check,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () => onSelected(mode),
            ),
      ],
    );
  }
}

class _AdaptiveSwitchTile extends StatelessWidget {
  const _AdaptiveSwitchTile({
    super.key,
    required this.usesIosLiquidGlass,
    required this.secondary,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final bool usesIosLiquidGlass;
  final Widget secondary;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!usesIosLiquidGlass) {
      return SwitchListTile(
        secondary: secondary,
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      );
    }

    return ListTile(
      leading: secondary,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: AdaptiveSwitch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}

class _ProxySettingsDialog extends StatefulWidget {
  const _ProxySettingsDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_ProxySettingsDialog> createState() => _ProxySettingsDialogState();
}

class _ProxySettingsDialogState extends State<_ProxySettingsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Application proxy'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '127.0.0.1:7890'),
        keyboardType: TextInputType.url,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
