import 'dart:async';

import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../services/sync_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_text_input_dialog.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_glass_button.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import '../widgets/ios_liquid/ios_platform_view_page_transitions.dart';

/// Cloud-sync settings: turn sync on/off, set / restore / change the master
/// password, and trigger a manual pull. All cryptography + Casdoor I/O lives
/// in [SyncService]; this page is pure orchestration + dialogs.
class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  String? _busyAction;

  bool get _busy => _busyAction != null;

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final sync = sp.syncService;
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: 'Cloud sync',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Settings',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回 Settings',
                  placementGroup: 'leading-main',
                ),
              ],
              onItemPressed: (id) {
                if (id == 'back') {
                  unawaited(maybePopPlatformViewPage<void>(context));
                }
              },
            )
          : const BlurredAppBar(title: Text('Cloud sync')),
      body: ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          return ListView(
            padding: EdgeInsets.only(
              top: topInset,
              bottom: AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              _ExplanationCard(enabled: sync.enabled),
              const SizedBox(height: 8),
              if (sync.enabled) ...[
                _statusTile(sync),
                _actionPanel([
                  _actionButton(
                    id: 'pull',
                    label: '立即从云端恢复',
                    subtitle: '用云端备份覆盖本设备绑定',
                    icon: Icons.download_for_offline_outlined,
                    sfSymbol: 'arrow.down.circle',
                    onPressed: () => unawaited(_pull(sync)),
                  ),
                  _actionButton(
                    id: 'push',
                    label: '立即备份到云端',
                    subtitle: '用本设备绑定覆盖云端备份',
                    icon: Icons.upload_outlined,
                    sfSymbol: 'arrow.up.circle',
                    role: IosNativeButtonRole.prominent,
                    onPressed: () => unawaited(_push(sync)),
                  ),
                  _actionButton(
                    id: 'password',
                    label: '修改主密码',
                    icon: Icons.lock_outline,
                    sfSymbol: 'key',
                    role: IosNativeButtonRole.plain,
                    onPressed: () => unawaited(_changePassword(sync)),
                  ),
                  _actionButton(
                    id: 'disable',
                    label: '关闭云同步',
                    subtitle: '清除云端备份与本设备主密码',
                    icon: Icons.cloud_off_outlined,
                    sfSymbol: 'icloud.slash',
                    role: IosNativeButtonRole.destructive,
                    onPressed: () => unawaited(_disable(sync)),
                  ),
                ]),
              ] else ...[
                _actionPanel([
                  _actionButton(
                    id: 'restore',
                    label: '从云端恢复',
                    subtitle: '已有备份时输入主密码恢复',
                    icon: Icons.lock_reset_outlined,
                    sfSymbol: 'icloud.and.arrow.down',
                    onPressed: () => unawaited(_restore(sync)),
                  ),
                  _actionButton(
                    id: 'setup',
                    label: '开启并备份',
                    subtitle: '首次设置主密码并加密上传',
                    icon: Icons.cloud_upload_outlined,
                    sfSymbol: 'icloud.and.arrow.up',
                    role: IosNativeButtonRole.prominent,
                    onPressed: () => unawaited(_setup(sync)),
                  ),
                ]),
              ],
              if (sync.needsRestore)
                _RestoreBanner(
                  onTap: _busy ? null : () => unawaited(_restore(sync)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusTile(SyncService sync) {
    final at = sync.lastSyncAt;
    String label;
    if (at == null) {
      label = '已开启 · 尚未同步';
    } else {
      String two(int n) => n.toString().padLeft(2, '0');
      label =
          '已开启 · 上次同步 ${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
    }
    return ListTile(
      leading: const Icon(Icons.sync),
      title: const Text('同步状态'),
      subtitle: Text(label),
    );
  }

  Widget _actionPanel(List<Widget> actions) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            actions[index],
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required String id,
    required String label,
    required IconData icon,
    required String sfSymbol,
    required VoidCallback onPressed,
    String? subtitle,
    IosNativeButtonRole role = IosNativeButtonRole.standard,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IosGlassButton(
          label: label,
          icon: icon,
          sfSymbol: sfSymbol,
          role: role,
          height: 44,
          loading: _busyAction == id,
          onPressed: _busy ? null : onPressed,
          accessibilityLabel: label,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // -- Actions -----------------------------------------------------------------

  Future<void> _guard(
    String action,
    Future<void> Function() task,
  ) async {
    setState(() => _busyAction = action);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _setup(SyncService sync) async {
    final pwd = await _askMasterPassword(
      title: '设置主密码',
      confirm: true,
      warning: _e2eExplanation,
    );
    if (pwd == null) return;
    await _guard('setup', () async {
      final outcome = await sync.setupWithMasterPassword(pwd);
      _feedback(outcome);
    });
  }

  Future<void> _restore(SyncService sync) async {
    final pwd = await _askMasterPassword(
      title: '输入主密码恢复',
      confirm: false,
      warning: _e2eExplanation,
    );
    if (pwd == null) return;
    await _guard('restore', () async {
      final outcome = await sync.restoreWithMasterPassword(pwd);
      _feedback(outcome);
    });
  }

  Future<void> _changePassword(SyncService sync) async {
    final oldPwd = await _askMasterPassword(
      title: '当前主密码',
      confirm: false,
      warning: null,
    );
    if (oldPwd == null) return;
    final newPwd = await _askMasterPassword(
      title: '设置新主密码',
      confirm: true,
      warning: _e2eExplanation,
    );
    if (newPwd == null) return;
    await _guard('password', () async {
      final outcome = await sync.changeMasterPassword(oldPwd, newPwd);
      _feedback(outcome);
    });
  }

  Future<void> _disable(SyncService sync) async {
    final ok = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '关闭云同步？',
      message: '将清除云端加密备份与本设备主密码。本设备上的绑定不受影响；其它设备将无法再从云端恢复。',
      actions: const [
        AdaptiveAlertAction<bool>(label: '取消', value: false),
        AdaptiveAlertAction<bool>(
          label: '关闭',
          value: true,
          isDestructive: true,
        ),
      ],
    );
    if (ok != true) return;
    await _guard('disable', () async {
      final outcome = await sync.disable();
      _feedback(outcome);
    });
  }

  Future<void> _pull(SyncService sync) async {
    await _guard('pull', () async {
      try {
        await sync.pull();
        _toast('已从云端恢复绑定');
      } on NeedMasterPassword {
        _toast('需要主密码，请在下方输入');
      } catch (_) {
        _toast('恢复失败，请检查网络或重新登录');
      }
    });
  }

  Future<void> _push(SyncService sync) async {
    await _guard('push', () async {
      final res = await sync.push();
      if (res.ok) {
        _toast('已备份到云端');
      } else {
        // Surface Casdoor's real reason (e.g. "Unauthorized operation") so the
        // user knows whether it's a network/authz/permission issue.
        _toast(res.describe('备份失败'));
      }
    });
  }

  void _feedback(SyncOutcome outcome) {
    _toast(outcome.message);
  }

  void _toast(String message) {
    if (!mounted) return;
    final isError = message.contains('失败') ||
        message.contains('不正确') ||
        message.contains('不能为空') ||
        message.contains('过期') ||
        message.contains('Unauthorized') ||
        message.contains('错误');
    showAdaptiveFeedback(
      context: context,
      message: message,
      style:
          isError ? AdaptiveFeedbackStyle.error : AdaptiveFeedbackStyle.success,
    );
  }

  Future<String?> _askMasterPassword({
    required String title,
    required bool confirm,
    required String? warning,
  }) async {
    return showAdaptiveTextInputDialog(
      context: context,
      title: title,
      message: warning,
      fieldLabel: '主密码',
      confirmationFieldLabel: confirm ? '再次输入' : null,
      mismatchMessage: '两次输入不一致',
      confirmLabel: '确定',
      obscureText: true,
    );
  }
}

const String _e2eExplanation =
    '启用后，你的 eGate 会话(含 CASTGC)、Gradescope/Hydro token 及(若开启自动续期)密码'
    '将以端到端加密形式存于 Casdoor，仅你能用主密码解密，TechPie 与 Casdoor 服务器均无法读取。'
    '请妥善保管主密码——遗忘将无法在其它设备恢复。';

class _ExplanationCard extends StatelessWidget {
  final bool enabled;
  const _ExplanationCard({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  enabled ? Icons.cloud_done_outlined : Icons.lock_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('端到端加密云同步', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '把第三方账号绑定(eGate / Gradescope / Hydro)加密备份到 Casdoor，'
              '跟随你的 GeekPie 账号在设备间同步。用一个你设定的主密码派生密钥加密，'
              '服务器只存密文，无法读取。换设备登录后输入主密码即可恢复全部绑定。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RestoreBanner extends StatelessWidget {
  final VoidCallback? onTap;
  const _RestoreBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      margin: const EdgeInsets.all(16),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_download_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '云端有可恢复的备份',
                    style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '检测到其它设备设置了云同步，输入主密码即可恢复绑定。',
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer.withValues(
                  alpha: 0.8,
                ),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            IosGlassButton(
              label: '恢复备份',
              icon: Icons.cloud_download_outlined,
              sfSymbol: 'icloud.and.arrow.down',
              role: IosNativeButtonRole.prominent,
              onPressed: onTap,
              accessibilityLabel: '恢复云端备份',
            ),
          ],
        ),
      ),
    );
  }
}
