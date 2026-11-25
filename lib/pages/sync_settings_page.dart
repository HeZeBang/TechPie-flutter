import 'dart:async';

import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../services/sync_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_text_input_dialog.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

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
  bool _versionFetchStarted = false;
  bool _loadingCloudVersion = false;
  DateTime? _cloudLastModified;

  bool get _busy => _busyAction != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final sp = ServiceProvider.of(context);
    final sync = sp.syncService;
    if (!_versionFetchStarted && sync.enabled) {
      _versionFetchStarted = true;
      unawaited(_loadCloudVersion(sync));
    }
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space3,
    );

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: '云同步',
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '我的',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回我的',
              placementGroup: 'leading-main',
            ),
          ],
          onItemPressed: (id) {
            if (id == 'back') {
              unawaited(maybePopAdaptivePage<void>(context));
            }
          },
        ),
        material: () => const BlurredAppBar(title: Text('云同步')),
      ),
      body: ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          return ListView(
            padding: EdgeInsets.fromLTRB(
              TpTokens.pageHorizontalPadding,
              topInset,
              TpTokens.pageHorizontalPadding,
              AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              TpPageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ExplanationCard(enabled: sync.enabled),
                    const SizedBox(height: TpTokens.sectionGap),
                    if (sync.enabled) ...[
                      TpCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _statusTile(colors, sync),
                            _versionCompareTile(colors, sync),
                          ],
                        ),
                      ),
                      const SizedBox(height: TpTokens.sectionGap),
                      _actionPanel([
                        _actionButton(
                          id: 'pull',
                          label: '立即从云端恢复',
                          subtitle: '用云端备份覆盖本设备绑定',
                          icon: TpIcons.download,
                          sfSymbol: 'arrow.down.circle',
                          onPressed: () => unawaited(_pull(sync)),
                        ),
                        _actionButton(
                          id: 'push',
                          label: '立即备份到云端',
                          subtitle: '用本设备绑定覆盖云端备份',
                          icon: TpIcons.sync,
                          sfSymbol: 'arrow.up.circle',
                          role: AdaptiveButtonRole.prominent,
                          onPressed: () => unawaited(_push(sync)),
                        ),
                        _actionButton(
                          id: 'password',
                          label: '修改主密码',
                          icon: TpIcons.lock,
                          sfSymbol: 'key',
                          role: AdaptiveButtonRole.plain,
                          onPressed: () => unawaited(_changePassword(sync)),
                        ),
                        _actionButton(
                          id: 'disable',
                          label: '关闭云同步',
                          subtitle: '清除云端备份与本设备主密码',
                          icon: Icons.cloud_off_outlined,
                          sfSymbol: 'icloud.slash',
                          role: AdaptiveButtonRole.destructive,
                          onPressed: () => unawaited(_disable(sync)),
                        ),
                      ]),
                    ] else ...[
                      _actionPanel([
                        _actionButton(
                          id: 'restore',
                          label: '从云端恢复',
                          subtitle: '已有备份时输入主密码恢复',
                          icon: TpIcons.download,
                          sfSymbol: 'icloud.and.arrow.down',
                          onPressed: () => unawaited(_restore(sync)),
                        ),
                        _actionButton(
                          id: 'setup',
                          label: '开启并备份',
                          subtitle: '首次设置主密码并加密上传',
                          icon: TpIcons.sync,
                          sfSymbol: 'icloud.and.arrow.up',
                          role: AdaptiveButtonRole.prominent,
                          onPressed: () => unawaited(_setup(sync)),
                        ),
                      ]),
                    ],
                    if (sync.needsRestore) ...[
                      const SizedBox(height: TpTokens.sectionGap),
                      _RestoreBanner(
                        onTap: _busy ? null : () => unawaited(_restore(sync)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusTile(TpColors colors, SyncService sync) {
    final at = sync.lastSyncAt;
    String label;
    if (at == null) {
      label = '已开启 · 尚未同步';
    } else {
      String two(int n) => n.toString().padLeft(2, '0');
      label =
          '已开启 · 上次同步 ${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
    }
    return TpListRow(
      icon: TpIcons.sync,
      iconColor: colors.infoBlue,
      title: '同步状态',
      subtitle: label,
      showDivider: true,
      trailing: const TpBadge(label: '已开启', tone: TpBadgeTone.success),
    );
  }

  Widget _versionCompareTile(TpColors colors, SyncService sync) {
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

    return TpListRow(
      icon: TpIcons.refresh,
      iconColor: colors.textSecondary,
      title: '版本对比',
      subtitle: '本地: $localLabel\n云端: $cloudLabel'
          '${compareLabel != null ? ' · $compareLabel' : ''}',
      subtitleMaxLines: 4,
      trailing: IconButton(
        icon: const Icon(TpIcons.refresh, size: TpTokens.iconS),
        tooltip: '刷新云端版本',
        onPressed: _loadingCloudVersion
            ? null
            : () => unawaited(_loadCloudVersion(sync)),
      ),
    );
  }

  Widget _actionPanel(List<Widget> actions) {
    return TpCard(
      padding: const EdgeInsets.all(TpTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(height: TpTokens.space3),
            actions[index],
          ],
        ],
      ),
    );
  }

  Future<void> _loadCloudVersion(SyncService sync) async {
    if (!mounted) return;
    setState(() => _loadingCloudVersion = true);
    try {
      final at = await sync.cloudLastModified();
      if (mounted) setState(() => _cloudLastModified = at);
    } finally {
      if (mounted) setState(() => _loadingCloudVersion = false);
    }
  }

  Widget _actionButton({
    required String id,
    required String label,
    required IconData icon,
    required String sfSymbol,
    required VoidCallback onPressed,
    String? subtitle,
    AdaptiveButtonRole role = AdaptiveButtonRole.standard,
  }) {
    final colors = context.tpColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveButton(
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
            padding: const EdgeInsets.symmetric(horizontal: TpTokens.space3),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TpTypography.itemMeta(colors),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _guard(
    String action,
    Future<void> Function() task,
  ) async {
    setState(() => _busyAction = action);
    try {
      await task();
    } catch (error) {
      _toast('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _setup(SyncService sync) async {
    final bool hasRemoteBackup;
    try {
      hasRemoteBackup = await sync.cloudHasBlob();
    } catch (error) {
      _toast('无法确认云端备份状态：$error');
      return;
    }
    if (hasRemoteBackup && await _confirmRemoteBackupOverwrite() != true) {
      return;
    }
    final pwd = await _askMasterPassword(
      title: '设置主密码',
      confirm: true,
      warning: _e2eExplanation,
    );
    if (pwd == null) return;
    await _guard('setup', () async {
      final outcome = await sync.setupWithMasterPassword(
        pwd,
        overwriteRemote: hasRemoteBackup,
      );
      _feedback(outcome);
      if (outcome.ok) unawaited(_loadCloudVersion(sync));
    });
  }

  Future<bool> _confirmRemoteBackupOverwrite() async {
    final ok = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '云端已有备份',
      message: '本设备尚未开启云同步，但云端已存在一份备份。'
          '如果它来自你的其它设备，建议先「从云端恢复」；'
          '继续设置将用本设备的绑定覆盖云端备份。',
      actions: const [
        AdaptiveAlertAction<bool>(label: '取消', value: false),
        AdaptiveAlertAction<bool>(
          label: '继续设置（覆盖）',
          value: true,
          isDestructive: true,
        ),
      ],
    );
    return ok == true;
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
      if (outcome.ok) {
        _versionFetchStarted = false;
        setState(() => _cloudLastModified = null);
      }
    });
  }

  Future<void> _pull(SyncService sync) async {
    await _guard('pull', () async {
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
    await _guard('push', () async {
      final res = await sync.push();
      if (res.ok) {
        _toast('已备份到云端');
        unawaited(_loadCloudVersion(sync));
      } else {
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
    '启用后，你的 IDS Passkey、Gradescope/Hydro token 及(若开启自动续期)密码'
    '将以端到端加密形式存于 Casdoor，仅你能用主密码解密，TechPie 与 Casdoor 服务器均无法读取。'
    '请妥善保管主密码——遗忘将无法在其它设备恢复。';

class _ExplanationCard extends StatelessWidget {
  final bool enabled;
  const _ExplanationCard({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return TpCard(
      leadingIcon: enabled ? TpIcons.checkCircle : TpIcons.lock,
      title: '端到端加密云同步',
      trailing: TpBadge(
        label: enabled ? '已开启' : '未开启',
        tone: enabled ? TpBadgeTone.success : TpBadgeTone.muted,
      ),
      padding: const EdgeInsets.fromLTRB(
        TpTokens.cardPaddingHorizontal,
        TpTokens.space1,
        TpTokens.cardPaddingHorizontal,
        TpTokens.space4,
      ),
      child: Text(
        '把第三方账号绑定(eGate / Gradescope / Hydro)加密备份到 Casdoor，'
        '跟随你的 GeekPie 账号在设备间同步。用一个你设定的主密码派生密钥加密，'
        '服务器只存密文，无法读取。换设备登录后输入主密码即可恢复全部绑定。',
        style: TpTypography.itemMeta(colors).copyWith(height: 1.45),
      ),
    );
  }
}

class _RestoreBanner extends StatelessWidget {
  final VoidCallback? onTap;
  const _RestoreBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return TpCard(
      color: colors.opaqueBrandContainer,
      borderColor: colors.brand.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(TpTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                TpIcons.download,
                size: TpTokens.iconM,
                color: colors.brandInk,
              ),
              const SizedBox(width: TpTokens.space2),
              Expanded(
                child: Text(
                  '云端有可恢复的备份',
                  style: TpTypography.itemTitle(colors).copyWith(
                    color: colors.brandInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '检测到其它设备设置了云同步，输入主密码即可恢复绑定。',
            style: TpTypography.itemMeta(colors),
          ),
          const SizedBox(height: TpTokens.space3),
          AdaptiveButton(
            label: '恢复备份',
            icon: TpIcons.download,
            sfSymbol: 'icloud.and.arrow.down',
            role: AdaptiveButtonRole.prominent,
            height: 44,
            onPressed: onTap,
            accessibilityLabel: '恢复云端备份',
          ),
        ],
      ),
    );
  }
}
