import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/service_provider.dart';
import '../services/sync_service.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import '../utils/adaptive_layout.dart';
import '../utils/platform.dart';
import '../utils/product_version.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_confirmation_button.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/adaptive_switch.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/desktop_popup.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/update_dialogs.dart';
import 'debug_log_page.dart';
import 'debug_webview_page.dart';
import 'developer_lab_page.dart';
import 'login_page.dart';
import 'sync_settings_page.dart';
import 'third_party_accounts_page.dart';
import 'watch_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '';
  bool _checkingUpdate = false;

  /// The stack a settings subpage is pushed onto in a wide window. A field, not
  /// a local: a GlobalKey rebuilt every frame would drop the stack with it.
  final _nestedNavigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppVersion());
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

    return Scaffold(
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
        ]),
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(
            top: topInset,
            bottom: AppShellMetrics.bottomContentPaddingOf(context),
          ),
          children: [
            // Account section
            _sectionHeader(theme, 'Account'),
            if (auth.isLoggedIn) ...[
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(
                  auth.session!.userName.isNotEmpty
                      ? auth.session!.userName
                      : auth.session!.userId,
                ),
                subtitle: Text(
                  [
                    'GeekPie Uni-Auth',
                    if (auth.session!.userId.isNotEmpty) auth.session!.userId,
                  ].join(' · '),
                ),
              ),
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
                title: const Text('申请注销账号'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => unawaited(
                  launchUrl(
                    Uri.parse('https://techpie.geekpie.club/privacy#account-deletion'),
                    mode: LaunchMode.externalApplication,
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
                  onPressed: () => unawaited(presentLoginPage(context)),
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Login'),
                subtitle: const Text('通过 GeekPie Uni-Auth 登录'),
                onTap: () => unawaited(presentLoginPage(context)),
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
                  pushAdaptivePage<void>(context, builder: (_) => const WatchSettingsPage()),
                ),
              ),

            // Appearance section
            _sectionHeader(theme, 'Appearance'),
            if (useIosChrome)
              ListTile(
                leading: Icon(themeService.mode.icon),
                title: const Text('Theme'),
                subtitle: Text(themeService.mode.label),
                trailing: AdaptiveSelect(
                  value: themeService.mode.name,
                  placeholder: 'Choose theme',
                  width: 156,
                  options: [
                    for (final mode in AppThemeMode.values)
                      AdaptiveSelectOption(value: mode.name, label: mode.label),
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
            if (!kReleaseMode) _AdaptiveSwitchTile(
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
            if (!kReleaseMode) _AdaptiveSwitchTile(
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
        ),
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

  void _showThemePicker(BuildContext context, ThemeService themeService) {
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
                    'Choose theme',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const Divider(height: 1),
                for (final mode in AppThemeMode.values)
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
                    onTap: () {
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
      showModalBottomSheet<void>(
        context: context,
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
              for (final mode in AppThemeMode.values)
                ListTile(
                  leading: Icon(mode.icon),
                  title: Text(mode.label),
                  trailing: themeService.mode == mode
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
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
    if (themeService.colorScheme == AppColorScheme.system &&
        !themeService.systemDynamicColorAvailable) {
      return '${themeService.colorScheme.label} (unavailable, using TechRed)';
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
      showModalBottomSheet<void>(
        context: context,
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

class _AdaptiveSwitchTile extends StatelessWidget {
  const _AdaptiveSwitchTile({
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
