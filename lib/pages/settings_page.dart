import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:techpie/services/auth_service.dart';

import '../models/third_party_account.dart';
import '../services/service_provider.dart';
import '../services/sync_service.dart';
import '../services/theme_service.dart';
import '../services/third_party_auth_service.dart';
import '../utils/adaptive_layout.dart';
import '../utils/platform.dart';
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
import 'debug_log_page.dart';
import 'login_page.dart';
import 'sync_settings_page.dart';
import 'third_party_accounts_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppVersion());
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = info.buildNumber.isNotEmpty
          ? '${info.version}+${info.buildNumber}'
          : info.version;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (usesSidebarLayout(context)) {
      return Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => _buildSettingsScaffold(context),
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
        listenable: Listenable.merge([auth, logger, themeService, tpAuth]),
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
              _CpdailyBindingTile(tpAuth: tpAuth),
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('Linked accounts'),
                subtitle: Text(
                  '${tpAuth.boundPlatforms.length} bound · Gradescope / Hydro / eGate',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(
                  pushAdaptivePage<void>(
                    context,
                    builder: (_) => const ThirdPartyAccountsPage(),
                  ),
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
            const Divider(),

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
            ),
            const Divider(),

            // Developer section
            _sectionHeader(theme, 'Developer'),
            _AdaptiveSwitchTile(
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
            _AdaptiveSwitchTile(
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
            if (logger.enabled)
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

class _CpdailyBindingTile extends StatelessWidget {
  final ThirdPartyAuthService tpAuth;

  const _CpdailyBindingTile({required this.tpAuth});

  @override
  Widget build(BuildContext context) {
    final cpdaily = tpAuth.account(ThirdPartyPlatform.cpdaily);
    final bound = cpdaily != null;
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        bound ? Icons.vpn_key : Icons.vpn_key_outlined,
        color: bound ? theme.colorScheme.primary : null,
      ),
      title: const Text('CpDaily / IDS'),
      subtitle: Text(
        bound
            ? '已绑定 · ${cpdaily.name ?? cpdaily.sid ?? cpdaily.account}'
            : '未绑定 · 需要绑定以启用课表和考试功能',
      ),
      trailing: bound
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20)
          : const Icon(Icons.chevron_right),
      onTap: bound
          ? null
          : () => unawaited(
                pushAdaptivePage<void>(
                  context,
                  builder: (_) => const ThirdPartyAccountsPage(),
                ),
              ),
    );
  }
}
