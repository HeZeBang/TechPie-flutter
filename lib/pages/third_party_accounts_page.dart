import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/renew_status.dart';
import '../models/third_party_account.dart';
import '../services/service_provider.dart';
import '../services/session/session_node.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_confirmation_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/schedule_picker_sheet.dart';
import 'campus_card_account_page.dart';
import 'ids_bind_page.dart';
import 'third_party_bind_page.dart';

/// The three states the linked-accounts status dot can show. `null` (no
/// dot) means "not applicable" — unbound top-level platform, or a derived
/// child whose parent (ids) isn't bound yet.
enum _LinkHealth { normal, recentFailure, error }

Color _healthColor(BuildContext context, _LinkHealth health) {
  final theme = Theme.of(context);
  return switch (health) {
    _LinkHealth.normal => Colors.green.shade600,
    _LinkHealth.recentFailure => Colors.amber.shade700,
    _LinkHealth.error => theme.colorScheme.error,
  };
}

/// Health for a top-level binding (ids/gradescope/hydro): null when
/// unbound (no dot — that's a distinct "not configured" state, not an
/// error).
_LinkHealth? _topLevelHealth(ThirdPartyAccount? account, RenewStatus? status) {
  if (account == null) return null;
  if (account.isExpired && status?.success != true) return _LinkHealth.error;
  if (status?.success == false) return _LinkHealth.recentFailure;
  return _LinkHealth.normal;
}

/// Health for a derived child (eams/elearning): null when the parent
/// (ids) isn't bound — there's nothing to evaluate yet.
_LinkHealth? _childHealth({
  required bool idsBound,
  required bool nodeAvailable,
  required RenewStatus? status,
}) {
  if (!idsBound) return null;
  if (!nodeAvailable && status?.success != true) return _LinkHealth.error;
  if (status?.success == false) return _LinkHealth.recentFailure;
  return _LinkHealth.normal;
}

String _formatDateTime(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm').format(dt);

class ThirdPartyAccountsPage extends StatelessWidget {
  const ThirdPartyAccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final tpAuth = sp.thirdPartyAuthService;
    final auth = sp.authService;
    final campusCard = sp.campusCardService;
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
                    title: 'Settings',
                    sfSymbol: 'chevron.left',
                    accessibilityLabel: '返回 Settings',
                  ),
              ],
              onItemPressed: (id) {
                if (id == 'back') {
                  unawaited(maybePopAdaptivePage<void>(context));
                }
              },
            )
          : const BlurredAppBar(title: Text('Linked Accounts')),
      body: ListenableBuilder(
        listenable: Listenable.merge([tpAuth, auth, campusCard]),
        builder: (context, _) {
          final idsBound = tpAuth.hasIdsBinding;
          return ListView(
            padding: EdgeInsets.only(
              top: topInset,
              bottom: AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              // IDS is the parent session — Blackboard (elearning),
              // 教务系统 (eams), and eGate 签到 (egateApp) below are all
              // derived from its tgc, not independent bindings, hence the
              // nested/indented rendering.
              _TopLevelTile(
                platform: ThirdPartyPlatform.ids,
                account: tpAuth.account(ThirdPartyPlatform.ids),
                node: tpAuth.idsNode,
                renewStatus: tpAuth.renewStatus('ids'),
              ),
              _ChildSessionTile(
                nodeId: 'elearning',
                label: 'Blackboard',
                icon: Icons.school_outlined,
                idsBound: idsBound,
                node: tpAuth.elearningNode,
                renewStatus: tpAuth.renewStatus('elearning'),
              ),
              _ChildSessionTile(
                nodeId: 'eams',
                label: '教务系统',
                icon: Icons.account_balance_outlined,
                idsBound: idsBound,
                node: tpAuth.eamsNode,
                renewStatus: tpAuth.renewStatus('eams'),
              ),
              _ChildSessionTile(
                nodeId: 'egateApp',
                label: 'eGate',
                icon: Icons.apps_outlined,
                idsBound: idsBound,
                node: tpAuth.egateAppNode,
                renewStatus: tpAuth.renewStatus('egateApp'),
              ),
              const Divider(),

              _TopLevelTile(
                platform: ThirdPartyPlatform.gradescope,
                account: tpAuth.account(ThirdPartyPlatform.gradescope),
                node: tpAuth.gradescopeNode,
                renewStatus: tpAuth.renewStatus('gradescope'),
              ),
              const Divider(height: 1),
              _TopLevelTile(
                platform: ThirdPartyPlatform.hydro,
                account: tpAuth.account(ThirdPartyPlatform.hydro),
                node: tpAuth.hydroNode,
                renewStatus: tpAuth.renewStatus('hydro'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('eCard'),
                subtitle: Text(
                  campusCard.configured
                      ? '${campusCard.openIdChannel.label} · ${campusCard.maskedOpenId}'
                      : '未连接',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(
                  pushAdaptivePage<void>(
                    context,
                    builder: (_) => const CampusCardAccountPage(),
                  ),
                ),
              ),
              const Divider(height: 1),

              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '绑定信息保存在本机安全存储中。开启 Cloud sync 后，绑定信息与 eCard OPENID 会经过端到端加密后备份。',
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

/// Small colored dot overlaid at the bottom-right of a leading icon via
/// [Stack]. `null` health renders nothing (unbound / not-yet-applicable).
class _StatusDot extends StatelessWidget {
  final _LinkHealth? health;
  const _StatusDot({required this.health});

  @override
  Widget build(BuildContext context) {
    final health = this.health;
    if (health == null) return const SizedBox.shrink();
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: _healthColor(context, health),
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).scaffoldBackgroundColor,
          width: 1.5,
        ),
      ),
    );
  }
}

Widget _dottedIcon(
  BuildContext context,
  IconData icon,
  Color? color,
  _LinkHealth? health, {
  double size = 24,
}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      Icon(icon, color: color, size: size),
      Positioned(
        right: -2,
        bottom: -2,
        child: _StatusDot(health: health),
      ),
    ],
  );
}

class _TopLevelTile extends StatefulWidget {
  final ThirdPartyPlatform platform;
  final ThirdPartyAccount? account;
  final SessionNode node;
  final RenewStatus? renewStatus;

  const _TopLevelTile({
    required this.platform,
    required this.account,
    required this.node,
    required this.renewStatus,
  });

  @override
  State<_TopLevelTile> createState() => _TopLevelTileState();
}

class _TopLevelTileState extends State<_TopLevelTile> {
  bool _refreshing = false;

  IconData get _icon => switch (widget.platform) {
        ThirdPartyPlatform.gradescope => Icons.grading_outlined,
        ThirdPartyPlatform.hydro => Icons.terminal_outlined,
        ThirdPartyPlatform.ids => Icons.vpn_key_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acc = widget.account;

    if (acc == null) {
      return ListTile(
        leading: Icon(_icon),
        title: Text(widget.platform.label),
        subtitle: const Text('未绑定'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(
          pushAdaptivePage<void>(
            context,
            builder: (_) => ThirdPartyBindPage(platform: widget.platform),
          ),
        ),
      );
    }

    final needsUpgrade =
        widget.platform == ThirdPartyPlatform.ids && acc.raw['authMethod'] != 'passkey';
    final health = needsUpgrade ? _LinkHealth.error : _topLevelHealth(acc, widget.renewStatus);
    final subtitleParts = <String>[
      acc.displayName,
      if (needsUpgrade) '需要升级为 Passkey',
      if (acc.expireAt != null) _expireLabel(acc.expireAt!),
      if (acc.autoRenew && !needsUpgrade) '自动更新 Token 已开启',
    ];
    if (widget.platform == ThirdPartyPlatform.hydro) {
      final origin = acc.hydroOrigin ?? '';
      final domains = (acc.hydroDomains ?? const []).join(', ');
      subtitleParts.add('$origin · $domains');
    }

    return ListTile(
      leading: _dottedIcon(context, _icon, theme.colorScheme.primary, health),
      title: Text(widget.platform.label),
      subtitle: Text(subtitleParts.join('\n')),
      isThreeLine: subtitleParts.length > 1,
      onTap: () => unawaited(_openDetails(context)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _refreshing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '立即刷新',
                  onPressed: needsUpgrade ? null : () => unawaited(_refresh(context)),
                ),
          isIos()
              ? AdaptiveConfirmationButton(
                  label: 'Unbind',
                  confirmTitle: widget.platform == ThirdPartyPlatform.ids &&
                          acc.raw['authMethod'] == 'passkey'
                      ? '解绑本地及 IDS Passkey?'
                      : '解绑 ${widget.platform.label}?',
                  confirmLabel: '解绑',
                  destructive: true,
                  onConfirmed: () => unawaited(_unbind(context, widget.platform)),
                )
              : TextButton.icon(
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Unbind'),
                  onPressed: () => unawaited(_confirmUnbind(context, widget.platform)),
                ),
        ],
      ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    setState(() => _refreshing = true);
    final ok = await ServiceProvider.of(context).thirdPartyAuthService.refreshNode(widget.node);
    if (!context.mounted) return;
    setState(() => _refreshing = false);
    showAdaptiveFeedback(
      context: context,
      message: ok
          ? '${widget.platform.label} 刷新成功'
          : (widget.node.lastRenewError ?? '${widget.platform.label} 刷新失败'),
      style: ok ? AdaptiveFeedbackStyle.success : AdaptiveFeedbackStyle.error,
    );
  }

  Future<void> _probe(BuildContext context) async {
    setState(() => _refreshing = true);
    final result = await widget.node.probe();
    if (!context.mounted) return;
    setState(() => _refreshing = false);
    showAdaptiveFeedback(
      context: context,
      message: result.success
          ? '${widget.platform.label} 检测成功: ${result.display}'
          : '${widget.platform.label} 检测失败: ${result.display}',
      style: result.success ? AdaptiveFeedbackStyle.success : AdaptiveFeedbackStyle.error,
    );
  }

  Future<void> _openDetails(BuildContext context) async {
    final acc = widget.account;
    if (acc == null) return;
    final rows = <MapEntry<String, String>>[
      MapEntry('账号', acc.displayName),
      if (widget.platform == ThirdPartyPlatform.ids && acc.idsStudentId.isNotEmpty)
        MapEntry('学号', acc.idsStudentId)
      else if (acc.sid != null && acc.sid!.isNotEmpty)
        MapEntry('学号', acc.sid!),
      if (widget.platform == ThirdPartyPlatform.ids)
        MapEntry('登录方式', acc.raw['authMethod'] == 'passkey' ? 'Passkey' : '待升级为 Passkey'),
      MapEntry('绑定时间', _formatDateTime(acc.boundAt)),
      MapEntry('更新时间', _formatDateTime(acc.updatedAt)),
      MapEntry('最近刷新', _renewStatusLabel(widget.renewStatus)),
      MapEntry('下次刷新', _nextRenewLabel(widget.node.nextRenewTimestamp)),
      MapEntry(
        'Token 有效期',
        acc.expireAt != null ? _formatDateTime(acc.expireAt!) : '无',
      ),
      MapEntry(
        '自动续期',
        widget.platform == ThirdPartyPlatform.ids
            ? (acc.raw['authMethod'] == 'passkey' ? '已开启' : '未开启')
            : (acc.autoRenew ? '已开启' : '未开启'),
      ),
      if (widget.platform == ThirdPartyPlatform.hydro) ...[
        MapEntry('Hydro 站点', acc.hydroOrigin ?? ''),
        MapEntry('Hydro 域名', (acc.hydroDomains ?? const []).join(', ')),
      ],
    ];
    final upgrade = await _showAccountDetailSheet(
      context,
      title: widget.platform.label,
      rows: rows,
      needsUpgrade: widget.platform == ThirdPartyPlatform.ids && acc.raw['authMethod'] != 'passkey',
      idsNotice: widget.platform == ThirdPartyPlatform.ids && acc.raw['authMethod'] == 'passkey',
      onRefresh: () => unawaited(_refresh(context)),
      onUnbind: () => unawaited(_confirmUnbind(context, widget.platform)),
      onProbe: widget.node.keepaliveConfig != null ? () => unawaited(_probe(context)) : null,
      cookieText: ServiceProvider.of(context).storageService.debugMode
          ? widget.node.cookieProvider?.cookies
          : null,
    );
    if (upgrade == true && context.mounted) {
      await pushAdaptivePage<void>(
        context,
        builder: (_) => const ThirdPartyBindPage(platform: ThirdPartyPlatform.ids),
      );
    }
  }
}

class _ChildSessionTile extends StatefulWidget {
  final String nodeId; // 'eams' | 'elearning'
  final String label;
  final IconData icon;
  final bool idsBound;
  final SessionNode node;
  final RenewStatus? renewStatus;

  const _ChildSessionTile({
    required this.nodeId,
    required this.label,
    required this.icon,
    required this.idsBound,
    required this.node,
    required this.renewStatus,
  });

  @override
  State<_ChildSessionTile> createState() => _ChildSessionTileState();
}

class _ChildSessionTileState extends State<_ChildSessionTile> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.idsBound) {
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 40, right: 16),
        leading: Icon(
          widget.icon,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          widget.label,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        subtitle: Text(
          '需要先绑定校园账号',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        onTap: () => unawaited(
          pushAdaptivePage<void>(
            context,
            builder: (_) => const ThirdPartyBindPage(platform: ThirdPartyPlatform.ids),
          ),
        ),
      );
    }

    final health = _childHealth(
      idsBound: widget.idsBound,
      nodeAvailable: widget.node.isAvailable,
      status: widget.renewStatus,
    );

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 40, right: 16),
      leading: _dottedIcon(
        context,
        widget.icon,
        theme.colorScheme.primary,
        health,
        size: 20,
      ),
      title: Text(widget.label),
      subtitle: Text(widget.node.displayName),
      onTap: () => unawaited(_openDetails(context)),
      trailing: _refreshing
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '立即刷新',
              onPressed: () => unawaited(_refresh(context)),
            ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    setState(() => _refreshing = true);
    final ok = await ServiceProvider.of(context).thirdPartyAuthService.refreshNode(widget.node);
    if (!context.mounted) return;
    setState(() => _refreshing = false);
    showAdaptiveFeedback(
      context: context,
      message: ok ? '${widget.label} 刷新成功' : '${widget.label} 刷新失败',
      style: ok ? AdaptiveFeedbackStyle.success : AdaptiveFeedbackStyle.error,
    );
  }

  Future<void> _probe(BuildContext context) async {
    setState(() => _refreshing = true);
    final result = await widget.node.probe();
    if (!context.mounted) return;
    setState(() => _refreshing = false);
    showAdaptiveFeedback(
      context: context,
      message: result.success
          ? '${widget.label} 检测成功: ${result.display}'
          : '${widget.label} 检测失败: ${result.display}',
      style: result.success ? AdaptiveFeedbackStyle.success : AdaptiveFeedbackStyle.error,
    );
  }

  Future<void> _openDetails(BuildContext context) async {
    final rows = <MapEntry<String, String>>[
      MapEntry('状态', widget.node.isAvailable ? '可用' : '不可用'),
      MapEntry('保活探测', widget.node.probeDisplay),
      MapEntry('最近刷新', _renewStatusLabel(widget.renewStatus)),
      MapEntry('下次刷新', _nextRenewLabel(widget.node.nextRenewTimestamp)),
    ];
    await _showAccountDetailSheet(
      context,
      title: widget.label,
      rows: rows,
      onRefresh: () => unawaited(_refresh(context)),
      onUnbind: null,
      onProbe: () => unawaited(_probe(context)),
      cookieText: ServiceProvider.of(context).storageService.debugMode
          ? widget.node.cookieProvider?.cookies
          : null,
    );
  }
}

String _renewStatusLabel(RenewStatus? status) {
  if (status == null) return '尚无记录';
  final time = _formatDateTime(status.at);
  return status.success ? '$time · 成功' : '$time · 失败';
}

String _expireLabel(DateTime at) {
  final now = DateTime.now();
  if (at.isBefore(now)) return '已过期';
  final diff = at.difference(now);
  if (diff.inDays >= 1) return "过期于 ${DateFormat("yyyy-MM-dd").format(at)}";
  if (diff.inHours >= 1) return '${diff.inHours}h 后过期';
  return '${diff.inMinutes}m 后过期';
}

String _nextRenewLabel(DateTime? timestamp) {
  if (timestamp == null) return '未安排';
  final state = timestamp.isBefore(DateTime.now()) ? '已到期 · ' : '';
  return '$state${_formatDateTime(timestamp)}';
}

Future<void> _confirmUnbind(
  BuildContext context,
  ThirdPartyPlatform platform,
) async {
  final tpAuth = ServiceProvider.of(context).thirdPartyAuthService;
  final ok = await showAdaptiveAlertDialog<bool>(
    context: context,
    title: '解绑 ${platform.label}?',
    message: platform == ThirdPartyPlatform.ids && tpAuth.usesIdsPasskey
        ? '将删除本地绑定，并尝试在 IDS 解绑此 Passkey。学校验证取消或删除失败时，本地绑定仍会删除。'
        : '将清除本地保存的 token 与账号信息,不会注销远端账号。',
    actions: const [
      AdaptiveAlertAction<bool>(label: '取消', value: false),
      AdaptiveAlertAction<bool>(
        label: '解绑',
        value: true,
        isDestructive: true,
      ),
    ],
  );
  if (ok == true && context.mounted) await _unbind(context, platform);
}

Future<void> _unbind(
  BuildContext context,
  ThirdPartyPlatform platform,
) async {
  final tpAuth = ServiceProvider.of(context).thirdPartyAuthService;
  if (platform != ThirdPartyPlatform.ids || !tpAuth.usesIdsPasskey) {
    await tpAuth.unbind(platform);
    return;
  }
  final prompts = IdsDialogSession(context, withPassword: true);
  final bool removed;
  try {
    removed = await tpAuth.unbindIdsWithRemote(promptVerification: prompts.verification);
  } finally {
    await prompts.close();
    prompts.dispose();
  }
  if (!context.mounted) return;
  showAdaptiveFeedback(
    context: context,
    message: removed ? '本地与 IDS Passkey 均已解绑' : '本地绑定已删除，IDS 解绑未完成，可在账号安全页面手动删除',
    style: removed ? AdaptiveFeedbackStyle.success : AdaptiveFeedbackStyle.info,
  );
}

/// Returns true when the user chooses to upgrade the stored IDS account.
Future<bool?> _showAccountDetailSheet(
  BuildContext context, {
  required String title,
  required List<MapEntry<String, String>> rows,
  required VoidCallback onRefresh,
  VoidCallback? onUnbind,
  VoidCallback? onProbe,
  String? cookieText,
  bool idsNotice = false,
  bool needsUpgrade = false,
}) {
  if (isIos()) {
    return _showIosAccountDetailSheet(
      context,
      title: title,
      rows: rows,
      onRefresh: onRefresh,
      onUnbind: onUnbind,
      onProbe: onProbe,
      cookieText: cookieText,
      idsNotice: idsNotice,
      needsUpgrade: needsUpgrade,
    );
  }
  final theme = Theme.of(context);
  return CNBottomSheet.show<bool>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final row in rows)
                if (row.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 88,
                          child: Text(
                            row.key,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row.value,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              if (idsNotice) ...[
                const SizedBox(height: 12),
                const IdsPasskeyHelp(),
              ],
              if (cookieText != null && cookieText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        'Cookie',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        cookieText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        unawaited(Clipboard.setData(ClipboardData(text: cookieText)));
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('Cookie 已复制'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.copy,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: needsUpgrade
                        ? FilledButton.icon(
                            icon: const Icon(Icons.key_outlined),
                            label: const Text('升级为 Passkey'),
                            onPressed: () => Navigator.pop(sheetContext, true),
                          )
                        : OutlinedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('立即刷新'),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              onRefresh();
                            },
                          ),
                  ),
                  if (onProbe != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.favorite_border),
                        label: const Text('检测'),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          onProbe();
                        },
                      ),
                    ),
                  ],
                  if (onUnbind != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(
                          Icons.link_off,
                          color: theme.colorScheme.error,
                        ),
                        label: Text(
                          '解绑',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          onUnbind();
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// iOS: the account's details as an inset-grouped list of label/value rows,
/// and its actions as a second group of tappable rows — unbinding last, in the
/// destructive red — under a sheet toolbar with a ✕ to close. No grabber: the
/// sheet has one height.
Future<bool?> _showIosAccountDetailSheet(
  BuildContext context, {
  required String title,
  required List<MapEntry<String, String>> rows,
  required VoidCallback onRefresh,
  VoidCallback? onUnbind,
  VoidCallback? onProbe,
  String? cookieText,
  bool idsNotice = false,
  bool needsUpgrade = false,
}) {
  return CNBottomSheet.show<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
    builder: (sheetContext) {
      final secondary = CupertinoColors.secondaryLabel.resolveFrom(sheetContext);
      final red = CupertinoColors.systemRed.resolveFrom(sheetContext);
      final tint = Theme.of(sheetContext).colorScheme.primary;
      void run(VoidCallback action) {
        Navigator.pop(sheetContext);
        action();
      }

      Widget actionRow(IconData icon, String label, Color color, VoidCallback action) =>
          CupertinoListTile(
            leading: Icon(icon, color: color),
            title: Text(label, style: TextStyle(color: color)),
            onTap: () => run(action),
          );

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              IosSheetHeader(title: title, onCancel: () => Navigator.pop(sheetContext)),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      CupertinoListSection.insetGrouped(
                        children: [
                          for (final row in rows)
                            if (row.value.isNotEmpty)
                              CupertinoListTile(
                                title: Text(row.key),
                                additionalInfo: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.sizeOf(sheetContext).width * 0.5,
                                  ),
                                  child: Text(
                                    row.value,
                                    textAlign: TextAlign.end,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          if (cookieText != null && cookieText.isNotEmpty)
                            CupertinoListTile(
                              title: const Text('Cookie'),
                              subtitle: Text(
                                cookieText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: 'monospace', color: secondary),
                              ),
                              trailing: Icon(CupertinoIcons.doc_on_doc, color: tint, size: 20),
                              onTap: () {
                                unawaited(Clipboard.setData(ClipboardData(text: cookieText)));
                                showAdaptiveFeedback(
                                  context: sheetContext,
                                  message: 'Cookie 已复制',
                                  style: AdaptiveFeedbackStyle.success,
                                );
                              },
                            ),
                        ],
                      ),
                      if (idsNotice)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              IdsPasskeyHelp(),
                            ],
                          ),
                        ),
                      CupertinoListSection.insetGrouped(
                        children: [
                          if (needsUpgrade)
                            CupertinoListTile(
                              leading: Icon(CupertinoIcons.lock, color: tint),
                              title: Text('升级为 Passkey', style: TextStyle(color: tint)),
                              onTap: () => Navigator.pop(sheetContext, true),
                            )
                          else
                            actionRow(CupertinoIcons.arrow_clockwise, '立即刷新', tint, onRefresh),
                          if (onProbe != null) actionRow(CupertinoIcons.heart, '检测', tint, onProbe),
                          if (onUnbind != null) actionRow(CupertinoIcons.link, '解绑', red, onUnbind),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
