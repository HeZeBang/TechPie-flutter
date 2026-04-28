import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/service_provider.dart';
import '../services/theme_service.dart';
import 'debug_log_page.dart';
import 'login_page.dart';

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
    _loadAppVersion();
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
    final theme = Theme.of(context);
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final logger = sp.debugLogger;
    final storage = sp.storageService;
    final themeService = sp.themeService;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([auth, logger, themeService]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 120),
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
                    auth.session!.schoolName,
                    if (auth.session!.phoneNumber.isNotEmpty)
                      auth.session!.phoneNumber,
                    auth.session!.studentId.isNotEmpty
                        ? auth.session!.studentId
                        : '未知学号',
                  ].join(' | '),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () => auth.logout(),
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Login'),
                subtitle: const Text('Sign in to your campus account'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                ),
              ),
            const Divider(),

            // Appearance section
            _sectionHeader(theme, 'Appearance'),
            ListTile(
              leading: Icon(themeService.mode.icon),
              title: const Text('Theme'),
              subtitle: Text(themeService.mode.label),
              onTap: () => _showThemePicker(context, themeService),
            ),
            const Divider(),

            // General section
            _sectionHeader(theme, 'General'),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications'),
              subtitle: const Text('Manage notification preferences'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              subtitle: Text(
                _appVersion.isEmpty
                    ? 'Version Unknown'
                    : 'Version $_appVersion',
              ),
              onTap: () {},
            ),
            const Divider(),

            // Developer section
            _sectionHeader(theme, 'Developer'),
            SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: const Text('Debug mode'),
              subtitle: const Text('Log all API requests'),
              value: logger.enabled,
              onChanged: (value) {
                logger.enabled = value;
                storage.setDebugMode(value);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.dns_outlined),
              title: const Text('Use localhost'),
              subtitle: const Text('Connect to local development server'),
              value: storage.useLocalhost,
              onChanged: (value) {
                storage.setUseLocalhost(value);
                setState(() {});
              },
            ),
            if (logger.enabled)
              ListTile(
                leading: const Icon(Icons.list_alt),
                title: const Text('View Logs'),
                subtitle: Text('${logger.entries.length} entries'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DebugLogPage()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker(BuildContext context, ThemeService themeService) {
    showModalBottomSheet(
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
                  themeService.setMode(mode);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
          ],
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
}
