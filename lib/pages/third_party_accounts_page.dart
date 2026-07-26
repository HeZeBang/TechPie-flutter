import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/renew_status.dart';
import '../models/third_party_account.dart';
import '../services/service_provider.dart';
import '../services/session/session_node.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_glass_confirmation_button.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import '../widgets/ios_liquid/ios_platform_view_page_transitions.dart';
import 'third_party_bind_page.dart';

/// The three states the linked-accounts status dot can show. `null` (no
/// dot) means "not applicable" — unbound top-level platform, or a derived
/// child whose parent (cpdaily) isn't bound yet.
enum _LinkHealth { normal, recentFailure, error }

Color _healthColor(BuildContext context, _LinkHealth health) {
  final theme = Theme.of(context);
  return switch (health) {
    _LinkHealth.normal => Colors.green.shade600,
    _LinkHealth.recentFailure => Colors.amber.shade700,
    _LinkHealth.error => theme.colorScheme.error,
  };
}

/// Health for a top-level binding (cpdaily/gradescope/hydro): null when
/// unbound (no dot — that's a distinct "not configured" state, not an
/// error).
_LinkHealth? _topLevelHealth(ThirdPartyAccount? account, RenewStatus? status) {
  if (account == null) return null;
  if (account.isExpired && status?.success != true) return _LinkHealth.error;
  if (status?.success == false) return _LinkHealth.recentFailure;
  return _LinkHealth.normal;
}

/// Health for a derived child (eams/elearning): null when the parent
/// (cpdaily) isn't bound — there's nothing to evaluate yet.
_LinkHealth? _childHealth({
  required bool cpdailyBound,
  required bool nodeAvailable,
  required RenewStatus? status,
}) {
  if (!cpdailyBound) return null;
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
                  unawaited(maybePopPlatformViewPage<void>(context));
                }
              },
            )
          : const BlurredAppBar(title: Text('Linked Accounts')),
      body: ListenableBuilder(
        listenable: Listenable.merge([tpAuth, auth]),
        builder: (context, _) {
          final cpdailyBound = tpAuth.hasCpdailyBinding;
          return ListView(
            padding: EdgeInsets.only(top: topInset, bottom: 120),
            children: [
              // CpDaily/IDS is the parent session — Blackboard (elearning)
              // and 教务系统 (eams) below are derived from its tgc, not
              // independent bindings, hence the nested/indented rendering.
              _TopLevelTile(
                platform: ThirdPartyPlatform.cpdaily,
                account: tpAuth.account(ThirdPartyPlatform.cpdaily),
                node: tpAuth.cpdailyNode,
                renewStatus: tpAuth.renewStatus('cpdaily'),
              ),
              _ChildSessionTile(
                nodeId: 'elearning',
                label: 'Blackboard',
                icon: Icons.school_outlined,
                cpdailyBound: cpdailyBound,
                node: tpAuth.elearningNode,
                renewStatus: tpAuth.renewStatus('elearning'),
              ),
              _ChildSessionTile(
                nodeId: 'eams',
                label: '教务系统',
                icon: Icons.account_balance_outlined,
                cpdailyBound: cpdailyBound,
                node: tpAuth.eamsNode,
                renewStatus: tpAuth.renewStatus('eams'),
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

Widget _dottedIcon(BuildContext context, IconData icon, Color? color, _LinkHealth? health, {double size = 24}) {
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
        ThirdPartyPlatform.cpdaily => Icons.vpn_key_outlined,
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
          pushPlatformViewPage<void>(
            context,
            builder: (_) => ThirdPartyBindPage(platform: widget.platform),
          ),
        ),
      );
    }

    final health = _topLevelHealth(acc, widget.renewStatus);
    final subtitleParts = <String>[
      acc.displayName,
      if (acc.expireAt != null) _expireLabel(acc.expireAt!),
      if (acc.autoRenew) '自动更新 Token 已开启',
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
                  onPressed: () => unawaited(_refresh(context)),
                ),
          isIos()
              ? IosGlassConfirmationButton(
                  label: 'Unbind',
                  confirmTitle: '解绑 ${widget.platform.label}?',
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
    final ok = await widget.node.renew();
    if (!context.mounted) return;
    setState(() => _refreshing = false);
    showAdaptiveFeedback(
      context: context,
      message: ok ? '${widget.platform.label} 刷新成功' : '${widget.platform.label} 刷新失败',
      style: ok ? AdaptiveFeedbackStyle.success : AdaptiveFeedbackStyle.error,
    );
  }

  Future<void> _openDetails(BuildContext context) async {
    final acc = widget.account;
    if (acc == null) return;
    final rows = <MapEntry<String, String>>[
      MapEntry('账号', acc.displayName),
      if (acc.sid != null && acc.sid!.isNotEmpty) MapEntry('学号', acc.sid!),
      MapEntry('绑定时间', _formatDateTime(acc.boundAt)),
      MapEntry('更新时间', _formatDateTime(acc.updatedAt)),
      MapEntry('最近刷新', _renewStatusLabel(widget.renewStatus)),
      MapEntry('Token 有效期', acc.expireAt != null ? _formatDateTime(acc.expireAt!) : '无'),
      MapEntry('自动续期', acc.autoRenew ? '已开启' : '未开启'),
      if (widget.platform == ThirdPartyPlatform.hydro) ...[
        MapEntry('Hydro 站点', acc.hydroOrigin ?? ''),
        MapEntry('Hydro 域名', (acc.hydroDomains ?? const []).join(', ')),
      ],
    ];
    await _showAccountDetailSheet(
      context,
      title: widget.platform.label,
      rows: rows,
      onRefresh: () => unawaited(_refresh(context)),
      onUnbind: () => unawaited(_confirmUnbind(context, widget.platform)),
    );
  }
}

class _ChildSessionTile extends StatefulWidget {
  final String nodeId; // 'eams' | 'elearning'
  final String label;
  final IconData icon;
  final bool cpdailyBound;
  final SessionNode node;
  final RenewStatus? renewStatus;

  const _ChildSessionTile({
    required this.nodeId,
    required this.label,
    required this.icon,
    required this.cpdailyBound,
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

    if (!widget.cpdailyBound) {
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 40, right: 16),
        leading: Icon(widget.icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        title: Text(
          widget.label,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        subtitle: Text(
          '需要先绑定 CpDaily/IDS',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        onTap: () => unawaited(
          pushPlatformViewPage<void>(
            context,
            builder: (_) => const ThirdPartyBindPage(platform: ThirdPartyPlatform.cpdaily),
          ),
        ),
      );
    }

    final health = _childHealth(
      cpdailyBound: widget.cpdailyBound,
      nodeAvailable: widget.node.isAvailable,
      status: widget.renewStatus,
    );

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 40, right: 16),
      leading: _dottedIcon(context, widget.icon, theme.colorScheme.primary, health, size: 20),
      title: Text(widget.label),
      subtitle: Text('随 CpDaily/IDS 自动获取 · ${_renewStatusLabel(widget.renewStatus)}'),
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
    final ok = await widget.node.renew();
    if (!context.mounted) return;
    setState(() => _refreshing = false);
    showAdaptiveFeedback(
      context: context,
      message: ok ? '${widget.label} 刷新成功' : '${widget.label} 刷新失败',
      style: ok ? AdaptiveFeedbackStyle.success : AdaptiveFeedbackStyle.error,
    );
  }

  Future<void> _openDetails(BuildContext context) async {
    final rows = <MapEntry<String, String>>[
      MapEntry('状态', widget.node.isAvailable ? '可用' : '不可用'),
      MapEntry('最近刷新', _renewStatusLabel(widget.renewStatus)),
      const MapEntry('说明', '由 CpDaily/IDS 会话派生，不单独绑定账号'),
    ];
    await _showAccountDetailSheet(
      context,
      title: widget.label,
      rows: rows,
      onRefresh: () => unawaited(_refresh(context)),
      onUnbind: null,
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

Future<void> _showAccountDetailSheet(
  BuildContext context, {
  required String title,
  required List<MapEntry<String, String>> rows,
  required VoidCallback onRefresh,
  VoidCallback? onUnbind,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
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
                          child: Text(row.value, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('立即刷新'),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        onRefresh();
                      },
                    ),
                  ),
                  if (onUnbind != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.link_off, color: theme.colorScheme.error),
                        label: Text('解绑', style: TextStyle(color: theme.colorScheme.error)),
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
