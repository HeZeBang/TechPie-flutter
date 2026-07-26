import 'dart:async';

import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../services/sync_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';

/// Cloud-sync settings: turn sync on/off, set / restore / change the master
/// password, and trigger a manual pull. All cryptography + Casdoor I/O lives
/// in [SyncService]; this page is pure orchestration + dialogs.
class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  bool _busy = false;
  bool _versionFetchStarted = false;
  bool _loadingCloudVersion = false;
  DateTime? _cloudLastModified;

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final sync = sp.syncService;
    // One-time lazy fetch of the cloud version for the comparison tile.
    // Deliberately NOT in initState — ServiceProvider.of() depends on
    // InheritedWidget lookup, which throws if called before initState
    // completes.
    if (!_versionFetchStarted && sync.enabled) {
      _versionFetchStarted = true;
      unawaited(_loadCloudVersion(sync));
    }
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? const IosNativeNavigationBar(title: 'Cloud sync')
          : const BlurredAppBar(title: Text('Cloud sync')),
      body: ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          return ListView(
            padding: EdgeInsets.only(top: topInset, bottom: 120),
            children: [
              _ExplanationCard(enabled: sync.enabled),
              const SizedBox(height: 8),
              if (sync.enabled) ...[
                _statusTile(sync),
                _versionCompareTile(sync),
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('立即从云端恢复'),
                  subtitle: const Text('用云端备份覆盖本设备绑定'),
                  onTap: _busy ? null : () => unawaited(_pull(sync)),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('立即备份到云端'),
                  subtitle: const Text('用本设备绑定覆盖云端备份'),
                  onTap: _busy ? null : () => unawaited(_push(sync)),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('修改主密码'),
                  onTap: _busy ? null : () => unawaited(_changePassword(sync)),
                ),
                ListTile(
                  leading: Icon(
                    Icons.cloud_off_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('关闭云同步'),
                  subtitle: const Text('清除云端备份与本设备主密码'),
                  onTap: _busy ? null : () => unawaited(_disable(sync)),
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.lock_reset_outlined),
                  title: const Text('从云端恢复（已有备份）'),
                  subtitle: const Text('在其它设备设置过云同步时使用'),
                  onTap: _busy ? null : () => unawaited(_restore(sync)),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('开启并备份（首次设置）'),
                  subtitle: const Text('设置主密码，把当前绑定加密上传'),
                  onTap: _busy ? null : () => unawaited(_setup(sync)),
                ),
              ],
              if (sync.needsRestore)
                _RestoreBanner(onTap: _busy ? null : () => unawaited(_restore(sync))),
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

  Widget _versionCompareTile(SyncService sync) {
    String two(int n) => n.toString().padLeft(2, '0');
    String fmt(DateTime t) =>
        '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';

    final local = sync.localLastModified;
    final cloud = _cloudLastModified;
    final localLabel = local == null ? '无本地数据' : fmt(local);
    String cloudLabel;
    String? compareLabel;
    if (_loadingCloudVersion) {
      cloudLabel = '正在获取…';
    } else if (cloud == null) {
      cloudLabel = '未知（需先解密一次，例如「立即从云端恢复」）';
    } else {
      cloudLabel = fmt(cloud);
      if (local == null) {
        compareLabel = '云端较新';
      } else if (local.isAfter(cloud)) {
        compareLabel = '本地较新';
      } else if (cloud.isAfter(local)) {
        compareLabel = '云端较新';
      } else {
        compareLabel = '已一致';
      }
    }

    return ListTile(
      leading: const Icon(Icons.compare_arrows_outlined),
      title: const Text('版本对比'),
      subtitle: Text(
        '本地: $localLabel\n云端: $cloudLabel'
        '${compareLabel != null ? ' · $compareLabel' : ''}',
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: '刷新云端版本',
        onPressed: _loadingCloudVersion ? null : () => unawaited(_loadCloudVersion(sync)),
      ),
    );
  }

  Future<void> _loadCloudVersion(SyncService sync) async {
    if (!mounted) return;
    setState(() => _loadingCloudVersion = true);
    final at = await sync.cloudLastModified();
    if (!mounted) return;
    setState(() {
      _cloudLastModified = at;
      _loadingCloudVersion = false;
    });
  }

  // -- Actions -----------------------------------------------------------------

  Future<void> _guard(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setup(SyncService sync) async {
    final pwd = await _askMasterPassword(
      title: '设置主密码',
      confirm: true,
      warning: _e2eExplanation,
    );
    if (pwd == null) return;
    await _guard(() async {
      final outcome = await sync.setupWithMasterPassword(pwd);
      _feedback(outcome);
      if (outcome.ok) unawaited(_loadCloudVersion(sync));
    });
  }

  Future<void> _restore(SyncService sync) async {
    final pwd = await _askMasterPassword(
      title: '输入主密码恢复',
      confirm: false,
      warning: _e2eExplanation,
    );
    if (pwd == null) return;
    await _guard(() async {
      final outcome = await sync.restoreWithMasterPassword(pwd);
      _feedback(outcome);
      if (outcome.ok) unawaited(_loadCloudVersion(sync));
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
    await _guard(() async {
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
    await _guard(() async {
      final outcome = await sync.disable();
      _feedback(outcome);
      if (outcome.ok) {
        _versionFetchStarted = false;
        setState(() => _cloudLastModified = null);
      }
    });
  }

  Future<void> _pull(SyncService sync) async {
    await _guard(() async {
      try {
        await sync.pull();
        _toast('已从云端恢复绑定');
        unawaited(_loadCloudVersion(sync));
      } on NeedMasterPassword {
        _toast('需要主密码，请在下方输入');
      } catch (_) {
        _toast('恢复失败，请检查网络或重新登录');
      }
    });
  }

  Future<void> _push(SyncService sync) async {
    await _guard(() async {
      final res = await sync.push();
      if (res.ok) {
        _toast('已备份到云端');
        unawaited(_loadCloudVersion(sync));
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
      style: isError ? AdaptiveFeedbackStyle.error : AdaptiveFeedbackStyle.success,
    );
  }

  Future<String?> _askMasterPassword({
    required String title,
    required bool confirm,
    required String? warning,
  }) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final obscure = true;
            final canSubmit = controller.text.isNotEmpty &&
                (!confirm || controller.text == confirmController.text);
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (warning != null) ...[
                      Text(
                        warning,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: controller,
                      obscureText: obscure,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '主密码',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (confirm) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmController,
                        obscureText: obscure,
                        decoration: const InputDecoration(
                          labelText: '再次输入',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (confirmController.text.isNotEmpty &&
                          controller.text != confirmController.text)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '两次输入不一致',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: canSubmit
                      ? () => Navigator.pop(context, controller.text)
                      : null,
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
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
      child: ListTile(
        leading: Icon(
          Icons.cloud_download_outlined,
          color: theme.colorScheme.onSecondaryContainer,
        ),
        title: Text(
          '云端有备份，点此恢复',
          style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
        ),
        subtitle: Text(
          '检测到其它设备设置了云同步，输入主密码即可恢复绑定',
          style: TextStyle(
            color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
