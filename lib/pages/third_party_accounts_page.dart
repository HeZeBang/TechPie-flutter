import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/third_party_account.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_glass_confirmation_button.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import 'login_page.dart';
import 'third_party_bind_page.dart';

class ThirdPartyAccountsPage extends StatelessWidget {
  const ThirdPartyAccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final tpAuth = sp.thirdPartyAuthService;
    final auth = sp.authService;
    final theme = Theme.of(context);
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: 'Linked Accounts',
              leadingItems: [
                if (Navigator.canPop(context))
                  const IosNativeNavigationBarItem(
                    id: 'back',
                    title: '返回',
                    sfSymbol: 'chevron.left',
                    accessibilityLabel: '返回',
                  ),
              ],
              onItemPressed: (id) {
                if (id == 'back') {
                  unawaited(Navigator.maybePop(context));
                }
              },
            )
          : const BlurredAppBar(title: Text('Linked Accounts')),
      body: ListenableBuilder(
        listenable: Listenable.merge([tpAuth, auth]),
        builder: (context, _) {
          return ListView(
            padding: EdgeInsets.only(top: topInset, bottom: 120),
            children: [
              // Blackboard read-only entry
              _BlackboardTile(),
              const Divider(),

              for (final platform in ThirdPartyPlatform.values) ...[
                _ThirdPartyTile(
                  platform: platform,
                  account: tpAuth.account(platform),
                ),
                const Divider(height: 1),
              ],

              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '绑定信息加密存储于设备本地 Keychain / EncryptedSharedPreferences,'
                  '不会上传到服务器。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BlackboardTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = ServiceProvider.of(context).authService;
    final theme = Theme.of(context);
    final loggedIn = auth.isLoggedIn;

    return ListTile(
      leading: const Icon(Icons.school_outlined),
      title: const Text('Blackboard'),
      subtitle: Text(
        loggedIn
            ? '通过主账号自动启用 (CASTGC) · ${auth.session!.studentId.isNotEmpty ? auth.session!.studentId : auth.session!.userId}'
            : '登录主账号后自动启用',
        style: theme.textTheme.bodySmall,
      ),
      trailing: loggedIn
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20)
          : const Icon(Icons.chevron_right),
      onTap: loggedIn ? null : () => unawaited(presentLoginPage(context)),
    );
  }
}

class _ThirdPartyTile extends StatelessWidget {
  final ThirdPartyPlatform platform;
  final ThirdPartyAccount? account;

  const _ThirdPartyTile({required this.platform, required this.account});

  IconData get _icon => switch (platform) {
        ThirdPartyPlatform.gradescope => Icons.grading_outlined,
        ThirdPartyPlatform.hydro => Icons.terminal_outlined,
        ThirdPartyPlatform.egate => Icons.vpn_key_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acc = account;

    if (acc == null) {
      return ListTile(
        leading: Icon(_icon),
        title: Text(platform.label),
        subtitle: const Text('未绑定'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ThirdPartyBindPage(platform: platform),
            ),
          ),
        ),
      );
    }

    final subtitleParts = <String>[
      acc.displayName,
      if (acc.expireAt != null) _expireLabel(acc.expireAt!),
      if (acc.autoRenew) '自动更新 Token 已开启',
    ];
    if (platform == ThirdPartyPlatform.hydro) {
      final origin = acc.hydroOrigin ?? '';
      final domains = (acc.hydroDomains ?? const []).join(', ');
      subtitleParts.add('$origin · $domains');
    }

    return ListTile(
      leading: Icon(_icon, color: theme.colorScheme.primary),
      title: Text(platform.label),
      subtitle: Text(subtitleParts.join('\n')),
      isThreeLine: subtitleParts.length > 1,
      trailing: isIos()
          ? IosGlassConfirmationButton(
              label: 'Unbind',
              confirmTitle: '解绑 ${platform.label}?',
              confirmLabel: '解绑',
              destructive: true,
              onConfirmed: () => unawaited(_unbind(context, platform)),
            )
          : TextButton.icon(
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Unbind'),
              onPressed: () => unawaited(_confirmUnbind(context, platform)),
            ),
    );
  }

  String _expireLabel(DateTime at) {
    final now = DateTime.now();
    if (at.isBefore(now)) return '已过期';
    final diff = at.difference(now);
    if (diff.inDays >= 1) return "过期于 ${DateFormat("yyyy-MM-dd").format(at)}";
    if (diff.inHours >= 1) return '${diff.inHours}h 后过期';
    return '${diff.inMinutes}m 后过期';
  }

  Future<void> _confirmUnbind(
    BuildContext context,
    ThirdPartyPlatform platform,
  ) async {
    final tpAuth = ServiceProvider.of(context).thirdPartyAuthService;
    final ok = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '解绑 ${platform.label}?',
      message: '将清除本地保存的 token 与账号信息,不会注销远端账号。',
      actions: const [
        AdaptiveAlertAction<bool>(label: '取消', value: false),
        AdaptiveAlertAction<bool>(
          label: '解绑',
          value: true,
          isDestructive: true,
        ),
      ],
    );
    if (ok == true) {
      await tpAuth.unbind(platform);
    }
  }

  Future<void> _unbind(
    BuildContext context,
    ThirdPartyPlatform platform,
  ) async {
    final tpAuth = ServiceProvider.of(context).thirdPartyAuthService;
    await tpAuth.unbind(platform);
  }
}
