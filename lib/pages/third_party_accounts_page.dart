import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/renew_status.dart';
import '../models/third_party_account.dart';
import '../services/service_provider.dart';
import '../services/session/session_node.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_confirmation_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import 'campus_card_account_page.dart';
import 'ids_bind_page.dart';
import 'third_party_bind_page.dart';

/// The three states the linked-accounts status badge can show. `null` means
/// "not applicable" — unbound top-level platform, or a derived child whose
/// parent (ids) isn't bound yet.
enum _LinkHealth { normal, recentFailure, error }

Color _healthColor(TpColors colors, _LinkHealth health) {
  return switch (health) {
    _LinkHealth.normal => colors.successGreen,
    _LinkHealth.recentFailure => colors.warningAmber,
    _LinkHealth.error => colors.dangerRed,
  };
}

TpBadgeTone _healthTone(_LinkHealth health) {
  return switch (health) {
    _LinkHealth.normal => TpBadgeTone.success,
    _LinkHealth.recentFailure => TpBadgeTone.warning,
    _LinkHealth.error => TpBadgeTone.danger,
  };
}

String _healthLabel(_LinkHealth health, {bool needsUpgrade = false}) {
  if (needsUpgrade) return '需升级';
  return switch (health) {
    _LinkHealth.normal => '已绑定',
    _LinkHealth.recentFailure => '刷新异常',
    _LinkHealth.error => '需重绑',
  };
}

_LinkHealth? _topLevelHealth(ThirdPartyAccount? account, RenewStatus? status) {
  if (account == null) return null;
  if (account.isExpired && status?.success != true) return _LinkHealth.error;
  if (status?.success == false) return _LinkHealth.recentFailure;
  return _LinkHealth.normal;
}

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

String _formatDateTime(DateTime dt) =>
    DateFormat('yyyy-MM-dd HH:mm').format(dt);

class ThirdPartyAccountsPage extends StatelessWidget {
  const ThirdPartyAccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final tpAuth = sp.thirdPartyAuthService;
    final auth = sp.authService;
    final campusCard = sp.campusCardService;
    final colors = context.tpColors;
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
          title: '第三方账号',
          leadingItems: [
            if (Navigator.canPop(context))
              const IosNativeNavigationBarItem(
                id: 'back',
                title: '我的',
                sfSymbol: 'chevron.left',
                accessibilityLabel: '返回我的',
              ),
          ],
          onItemPressed: (id) {
            if (id == 'back') {
              unawaited(maybePopAdaptivePage<void>(context));
            }
          },
        ),
        material: () => const BlurredAppBar(title: Text('第三方账号')),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([tpAuth, auth, campusCard]),
        builder: (context, _) {
          final idsBound = tpAuth.hasIdsBinding;
          final connectedCount =
              tpAuth.boundPlatforms.length + (campusCard.configured ? 1 : 0);
          const totalPlatforms = 4;

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
                    // Connection Summary Card
                    TpCard(
                      key: const ValueKey('accounts.summary-card'),
                      padding: const EdgeInsets.all(TpTokens.space4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: colors.brandSoft,
                                  borderRadius:
                                      BorderRadius.circular(TpTokens.radiusS),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  TpIcons.linkedAccounts,
                                  size: TpTokens.iconM,
                                  color: colors.brand,
                                ),
                              ),
                              const SizedBox(width: TpTokens.space3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '校园与课程平台',
                                      style: TpTypography.cardTitle(colors),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '已连接 $connectedCount / $totalPlatforms 个平台',
                                      style: TpTypography.itemMeta(colors),
                                    ),
                                  ],
                                ),
                              ),
                              TpBadge(
                                label: connectedCount == totalPlatforms
                                    ? '全部就绪'
                                    : connectedCount > 0
                                        ? '部分连接'
                                        : '未绑定',
                                tone: connectedCount == totalPlatforms
                                    ? TpBadgeTone.success
                                    : connectedCount > 0
                                        ? TpBadgeTone.info
                                        : TpBadgeTone.muted,
                              ),
                            ],
                          ),
                          const SizedBox(height: TpTokens.space3),
                          TpProgressBar(
                            progress: connectedCount / totalPlatforms,
                            color: connectedCount == totalPlatforms
                                ? colors.successGreen
                                : colors.brand,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: TpTokens.sectionGap),

                    // Group 1: Campus Unified Identity (IDS + derived sessions)
                    const _AccountGroupLabel(title: '校园统一身份'),
                    TpCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TopLevelTile(
                            platform: ThirdPartyPlatform.ids,
                            account: tpAuth.account(ThirdPartyPlatform.ids),
                            node: tpAuth.idsNode,
                            renewStatus: tpAuth.renewStatus('ids'),
                            showDivider: true,
                          ),
                          Material(
                            color: colors.surfaceSubtle.withValues(
                              alpha: colors.isDark ? 0.55 : 0.65,
                            ),
                            child: Column(
                              children: [
                                _ChildSessionTile(
                                  nodeId: 'elearning',
                                  label: 'Blackboard',
                                  icon: TpIcons.course,
                                  idsBound: idsBound,
                                  node: tpAuth.elearningNode,
                                  renewStatus: tpAuth.renewStatus('elearning'),
                                  showDivider: true,
                                ),
                                _ChildSessionTile(
                                  nodeId: 'eams',
                                  label: '教务系统',
                                  icon: TpIcons.building,
                                  idsBound: idsBound,
                                  node: tpAuth.eamsNode,
                                  renewStatus: tpAuth.renewStatus('eams'),
                                  showDivider: true,
                                ),
                                _ChildSessionTile(
                                  nodeId: 'egateApp',
                                  label: 'eGate',
                                  icon: TpIcons.activities,
                                  idsBound: idsBound,
                                  node: tpAuth.egateAppNode,
                                  renewStatus: tpAuth.renewStatus('egateApp'),
                                  showDivider: false,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: TpTokens.sectionGap),

                    // Group 2: Campus Card & Learning Platforms
                    const _AccountGroupLabel(title: '校园卡与课程平台'),
                    TpCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TpListRow(
                            icon: TpIcons.wallet,
                            iconColor: campusCard.configured
                                ? colors.brand
                                : colors.textMuted,
                            title: 'eCard',
                            subtitle: campusCard.configured
                                ? '${campusCard.openIdChannel.label} · ${campusCard.maskedOpenId}'
                                : '未连接',
                            showDivider: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TpBadge(
                                  label: campusCard.configured ? '已连接' : '未连接',
                                  tone: campusCard.configured
                                      ? TpBadgeTone.success
                                      : TpBadgeTone.muted,
                                ),
                                const SizedBox(width: TpTokens.space1),
                                Icon(
                                  TpIcons.chevronRight,
                                  size: TpTokens.iconS,
                                  color: colors.textMuted,
                                ),
                              ],
                            ),
                            onTap: () => unawaited(
                              pushAdaptivePage<void>(
                                context,
                                builder: (_) => const CampusCardAccountPage(),
                              ),
                            ),
                          ),
                          _TopLevelTile(
                            platform: ThirdPartyPlatform.gradescope,
                            account:
                                tpAuth.account(ThirdPartyPlatform.gradescope),
                            node: tpAuth.gradescopeNode,
                            renewStatus: tpAuth.renewStatus('gradescope'),
                            showDivider: true,
                          ),
                          _TopLevelTile(
                            platform: ThirdPartyPlatform.hydro,
                            account: tpAuth.account(ThirdPartyPlatform.hydro),
                            node: tpAuth.hydroNode,
                            renewStatus: tpAuth.renewStatus('hydro'),
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: TpTokens.space3),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TpTokens.space2,
                      ),
                      child: Text(
                        '绑定信息保存在本机安全存储中。开启云同步 (Cloud sync) 后，绑定信息与 eCard OPENID 会经过端到端加密后备份。',
                        style: TpTypography.itemMeta(colors),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AccountGroupLabel extends StatelessWidget {
  const _AccountGroupLabel({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TpTokens.space2,
        0,
        TpTokens.space2,
        TpTokens.space2,
      ),
      child: Text(
        title,
        style: TpTypography.cardMeta(colors).copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final _LinkHealth? health;
  const _StatusDot({required this.health});

  @override
  Widget build(BuildContext context) {
    final health = this.health;
    if (health == null) return const SizedBox.shrink();
    final colors = context.tpColors;
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: _healthColor(colors, health),
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.surface,
          width: 1.5,
        ),
      ),
    );
  }
}

Widget _dottedIcon(
  TpColors colors,
  IconData icon,
  Color color,
  _LinkHealth? health, {
  double size = TpTokens.iconM,
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
  final bool showDivider;

  const _TopLevelTile({
    required this.platform,
    required this.account,
    required this.node,
    required this.renewStatus,
    required this.showDivider,
  });

  @override
  State<_TopLevelTile> createState() => _TopLevelTileState();
}

class _TopLevelTileState extends State<_TopLevelTile> {
  bool _refreshing = false;

  IconData get _icon => switch (widget.platform) {
        ThirdPartyPlatform.gradescope => TpIcons.graduation,
        ThirdPartyPlatform.hydro => TpIcons.code,
        ThirdPartyPlatform.ids => TpIcons.lock,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final acc = widget.account;

    if (acc == null) {
      return TpListRow(
        icon: _icon,
        iconColor: colors.textMuted,
        title: widget.platform.label,
        subtitle: '未绑定',
        showDivider: widget.showDivider,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TpBadge(label: '未绑定', tone: TpBadgeTone.muted),
            const SizedBox(width: TpTokens.space1),
            Icon(
              TpIcons.chevronRight,
              size: TpTokens.iconS,
              color: colors.textMuted,
            ),
          ],
        ),
        onTap: () => unawaited(
          pushAdaptivePage<void>(
            context,
            builder: (_) => ThirdPartyBindPage(platform: widget.platform),
          ),
        ),
      );
    }

    final needsUpgrade = widget.platform == ThirdPartyPlatform.ids &&
        acc.raw['authMethod'] != 'passkey';
    final health = needsUpgrade
        ? _LinkHealth.error
        : (_topLevelHealth(acc, widget.renewStatus) ?? _LinkHealth.normal);
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => unawaited(_openDetails(context)),
          splashColor: colors.brandSoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TpTokens.cardPaddingHorizontal,
              vertical: TpTokens.space3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _dottedIcon(colors, _icon, colors.brand, health),
                const SizedBox(width: TpTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.platform.label,
                              style: TpTypography.itemTitle(colors),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: TpTokens.space2),
                          TpBadge(
                            label: _healthLabel(
                              health,
                              needsUpgrade: needsUpgrade,
                            ),
                            tone: _healthTone(health),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitleParts.join(' · '),
                        style: TpTypography.itemMeta(colors),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: TpTokens.space1),
                if (_refreshing)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(TpIcons.refresh, size: TpTokens.iconS),
                    tooltip: '立即刷新',
                    onPressed: needsUpgrade
                        ? null
                        : () => unawaited(_refresh(context)),
                    visualDensity: VisualDensity.compact,
                  ),
                AdaptiveNavigationScaffold.adaptiveChrome(
                  ios: () => AdaptiveConfirmationButton(
                    label: '解绑',
                    confirmTitle: widget.platform == ThirdPartyPlatform.ids &&
                            acc.raw['authMethod'] == 'passkey'
                        ? '解绑本地及 IDS Passkey?'
                        : '解绑 ${widget.platform.label}?',
                    confirmLabel: '解绑',
                    destructive: true,
                    onConfirmed: () =>
                        unawaited(_unbind(context, widget.platform)),
                  ),
                  material: () => TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.dangerRed,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: () =>
                        unawaited(_confirmUnbind(context, widget.platform)),
                    child: const Text('解绑'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TpTokens.cardPaddingHorizontal,
            ),
            child: Divider(height: 1, thickness: 0.5, color: colors.divider),
          ),
      ],
    );
  }

  Future<void> _refresh(BuildContext context) async {
    setState(() => _refreshing = true);
    final ok = await ServiceProvider.of(context)
        .thirdPartyAuthService
        .refreshNode(widget.node);
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
      style: result.success
          ? AdaptiveFeedbackStyle.success
          : AdaptiveFeedbackStyle.error,
    );
  }

  Future<void> _openDetails(BuildContext context) async {
    final acc = widget.account;
    if (acc == null) return;
    final rows = <MapEntry<String, String>>[
      MapEntry('账号', acc.displayName),
      if (widget.platform == ThirdPartyPlatform.ids &&
          acc.idsStudentId.isNotEmpty)
        MapEntry('学号', acc.idsStudentId)
      else if (acc.sid != null && acc.sid!.isNotEmpty)
        MapEntry('学号', acc.sid!),
      if (widget.platform == ThirdPartyPlatform.ids)
        MapEntry(
          '登录方式',
          acc.raw['authMethod'] == 'passkey' ? 'Passkey' : '待升级为 Passkey',
        ),
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
      needsUpgrade: widget.platform == ThirdPartyPlatform.ids &&
          acc.raw['authMethod'] != 'passkey',
      idsNotice: widget.platform == ThirdPartyPlatform.ids &&
          acc.raw['authMethod'] == 'passkey',
      onRefresh: () => unawaited(_refresh(context)),
      onUnbind: () => unawaited(_confirmUnbind(context, widget.platform)),
      onProbe: widget.node.keepaliveConfig != null
          ? () => unawaited(_probe(context))
          : null,
      cookieText: ServiceProvider.of(context).storageService.debugMode
          ? widget.node.cookieProvider?.cookies
          : null,
    );
    if (upgrade == true && context.mounted) {
      await pushAdaptivePage<void>(
        context,
        builder: (_) =>
            const ThirdPartyBindPage(platform: ThirdPartyPlatform.ids),
      );
    }
  }
}

class _ChildSessionTile extends StatefulWidget {
  final String nodeId;
  final String label;
  final IconData icon;
  final bool idsBound;
  final SessionNode node;
  final RenewStatus? renewStatus;
  final bool showDivider;

  const _ChildSessionTile({
    required this.nodeId,
    required this.label,
    required this.icon,
    required this.idsBound,
    required this.node,
    required this.renewStatus,
    required this.showDivider,
  });

  @override
  State<_ChildSessionTile> createState() => _ChildSessionTileState();
}

class _ChildSessionTileState extends State<_ChildSessionTile> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;

    if (!widget.idsBound) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => unawaited(
              pushAdaptivePage<void>(
                context,
                builder: (_) =>
                    const ThirdPartyBindPage(platform: ThirdPartyPlatform.ids),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                TpTokens.space6,
                10,
                TpTokens.cardPaddingHorizontal,
                10,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: TpTokens.iconS,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: TpTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: TpTypography.itemTitle(colors).copyWith(
                            fontSize: 14,
                            color: colors.textMuted,
                          ),
                        ),
                        Text(
                          '需要先绑定校园账号',
                          style: TpTypography.itemMeta(colors),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.showDivider)
            Padding(
              padding: const EdgeInsets.only(
                left: TpTokens.space6,
                right: TpTokens.cardPaddingHorizontal,
              ),
              child: Divider(height: 1, thickness: 0.5, color: colors.divider),
            ),
        ],
      );
    }

    final health = _childHealth(
      idsBound: widget.idsBound,
      nodeAvailable: widget.node.isAvailable,
      status: widget.renewStatus,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => unawaited(_openDetails(context)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              TpTokens.space6,
              10,
              TpTokens.cardPaddingHorizontal,
              10,
            ),
            child: Row(
              children: [
                _dottedIcon(
                  colors,
                  widget.icon,
                  colors.brand,
                  health,
                  size: TpTokens.iconS,
                ),
                const SizedBox(width: TpTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TpTypography.itemTitle(colors).copyWith(
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        widget.node.displayName,
                        style: TpTypography.itemMeta(colors),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_refreshing)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(TpIcons.refresh, size: TpTokens.iconS),
                    tooltip: '立即刷新',
                    onPressed: () => unawaited(_refresh(context)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
        if (widget.showDivider)
          Padding(
            padding: const EdgeInsets.only(
              left: TpTokens.space6,
              right: TpTokens.cardPaddingHorizontal,
            ),
            child: Divider(height: 1, thickness: 0.5, color: colors.divider),
          ),
      ],
    );
  }

  Future<void> _refresh(BuildContext context) async {
    setState(() => _refreshing = true);
    final ok = await ServiceProvider.of(context)
        .thirdPartyAuthService
        .refreshNode(widget.node);
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
      style: result.success
          ? AdaptiveFeedbackStyle.success
          : AdaptiveFeedbackStyle.error,
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
  if (diff.inDays >= 1) return '过期于 ${DateFormat('yyyy-MM-dd').format(at)}';
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
    removed = await tpAuth.unbindIdsWithRemote(
      promptVerification: prompts.verification,
    );
  } finally {
    await prompts.close();
    prompts.dispose();
  }
  if (!context.mounted) return;
  showAdaptiveFeedback(
    context: context,
    message: removed
        ? '本地与 IDS Passkey 均已解绑'
        : '本地绑定已删除，IDS 解绑未完成，可在账号安全页面手动删除',
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
  return AdaptiveNavigationScaffold.showSheet<bool>(
    context: context,
    builder: (sheetContext, padding) {
      final colors = sheetContext.tpColors;
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TpTypography.cardTitle(colors)
                            .copyWith(fontSize: 18),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(TpIcons.close, size: TpTokens.iconM),
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const SizedBox(height: TpTokens.space2),
                TpCard(
                  color: colors.surfaceSubtle,
                  padding: const EdgeInsets.symmetric(
                    horizontal: TpTokens.space4,
                    vertical: TpTokens.space2,
                  ),
                  child: Column(
                    children: [
                      for (final row in rows)
                        if (row.value.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 92,
                                  child: Text(
                                    row.key,
                                    style: TpTypography.itemMeta(colors),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    row.value,
                                    textAlign: TextAlign.end,
                                    style: TpTypography.itemMeta(colors)
                                        .copyWith(color: colors.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      if (cookieText != null && cookieText.isNotEmpty) ...[
                        Divider(
                          height: 12,
                          thickness: 0.5,
                          color: colors.divider,
                        ),
                        Row(
                          children: [
                            SizedBox(
                              width: 92,
                              child: Text(
                                'Cookie',
                                style: TpTypography.itemMeta(colors),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                cookieText,
                                style: TpTypography.itemMeta(colors).copyWith(
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.copy,
                                size: TpTokens.iconS,
                              ),
                              tooltip: '复制 Cookie',
                              onPressed: () {
                                unawaited(
                                  Clipboard.setData(
                                    ClipboardData(text: cookieText),
                                  ),
                                );
                                showAdaptiveFeedback(
                                  context: sheetContext,
                                  message: 'Cookie 已复制',
                                  style: AdaptiveFeedbackStyle.success,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (idsNotice) ...[
                  const SizedBox(height: TpTokens.space3),
                  const IdsPasskeyHelp(),
                ],
                const SizedBox(height: TpTokens.space4),
                Wrap(
                  spacing: TpTokens.space2,
                  runSpacing: TpTokens.space2,
                  children: [
                    if (needsUpgrade)
                      FilledButton.icon(
                        icon: const Icon(TpIcons.lock, size: TpTokens.iconS),
                        label: const Text('升级为 Passkey'),
                        onPressed: () => Navigator.pop(sheetContext, true),
                      )
                    else
                      OutlinedButton.icon(
                        icon: const Icon(TpIcons.refresh, size: TpTokens.iconS),
                        label: const Text('立即刷新'),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          onRefresh();
                        },
                      ),
                    if (onProbe != null)
                      OutlinedButton.icon(
                        icon: const Icon(
                          TpIcons.activity,
                          size: TpTokens.iconS,
                        ),
                        label: const Text('检测'),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          onProbe();
                        },
                      ),
                    if (onUnbind != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.dangerRed,
                        ),
                        icon: Icon(
                          TpIcons.delete,
                          size: TpTokens.iconS,
                          color: colors.dangerRed,
                        ),
                        label: const Text('解绑'),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          onUnbind();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
