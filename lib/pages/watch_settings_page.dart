import 'dart:async';

import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../services/watch_sync_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_switch.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class WatchSettingsPage extends StatefulWidget {
  const WatchSettingsPage({super.key});
  @override
  State<WatchSettingsPage> createState() => _WatchSettingsPageState();
}

class _WatchSettingsPageState extends State<WatchSettingsPage> {
  bool _loaded = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    unawaited(
      ServiceProvider.of(context).campusCardService.watchSync.refreshStatus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: 'Apple Watch',
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
            if (id == 'back') unawaited(maybePopAdaptivePage<void>(context));
          },
        ),
        material: () => const BlurredAppBar(title: Text('Apple Watch')),
      ),
      body: WatchSettingsContent(
        sync: ServiceProvider.of(context).campusCardService.watchSync,
      ),
    );
  }
}

/// One actionable summary; transport details and session history stay collapsed.
class WatchSettingsContent extends StatelessWidget {
  const WatchSettingsContent({super.key, required this.sync});
  final WatchSyncService sync;

  static String _date(Object? seconds) {
    if (seconds is! num) return '暂无';
    final date = DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).round(),
      isUtc: true,
    ).subtract(const Duration(seconds: 1));
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  ({String title, String detail, IconData icon, bool warning}) _summary() {
    if (sync.busy) {
      return (
        title: '正在同步',
        detail: '正在更新卡片与离线授权',
        icon: TpIcons.refresh,
        warning: false,
      );
    }
    if (sync.hasError) {
      return (
        title: '同步未完成',
        detail: sync.message ?? '请稍后重试',
        icon: TpIcons.info,
        warning: true,
      );
    }
    if (!sync.enabled) {
      return (
        title: '未开启',
        detail: sync.message == '已取消授权，手表连接后会清除校园卡'
            ? '取消授权将在手表连接后生效'
            : '开启后，手表会保存校园卡 OPENID，可独立获取在线码或使用离线码',
        icon: TpIcons.watch,
        warning: false,
      );
    }
    if (!sync.isAcknowledged) {
      return (
        title: '等待手表接收',
        detail: '在手表上打开 TechPie 即可继续同步',
        icon: TpIcons.deadlines,
        warning: false,
      );
    }
    final expires = sync.status['watchExpiresAt'];
    final onlineReady = sync.status['onlineReady'] == true;
    if (expires is! num) {
      if (onlineReady) {
        return (
          title: '已同步',
          detail: '在线码可独立获取；离线码尚未授权',
          icon: TpIcons.checkCircle,
          warning: false,
        );
      }
      return (
        title: '待同步离线授权',
        detail: '请先在手机校园卡中开通或续期，再更新同步',
        icon: TpIcons.info,
        warning: true,
      );
    }
    if (expires * 1000 <= DateTime.now().millisecondsSinceEpoch) {
      if (onlineReady) {
        return (
          title: '已同步',
          detail: '在线码可独立获取；离线授权已到期',
          icon: TpIcons.checkCircle,
          warning: false,
        );
      }
      return (
        title: '离线授权已到期',
        detail: '点击下方按钮更新授权',
        icon: TpIcons.info,
        warning: true,
      );
    }
    return (
      title: '已同步',
      detail: '${onlineReady ? '在线码可独立获取；' : ''}离线使用至 ${_date(expires)}',
      icon: TpIcons.checkCircle,
      warning: false,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          final colors = context.tpColors;
          final summary = _summary();
          final statusColor =
              summary.warning ? colors.dangerRed : colors.brandInk;
          final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
            context,
            extra: TpTokens.space4,
          );
          return ListView(
            padding: EdgeInsets.fromLTRB(
              TpTokens.pageHorizontalPadding,
              topInset,
              TpTokens.pageHorizontalPadding,
              AppShellMetrics.bottomContentPaddingOf(context, margin: 32),
            ),
            children: [
              TpPageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TpCard(
                      padding: const EdgeInsets.all(TpTokens.space4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                TpIcons.watch,
                                size: TpTokens.iconM,
                                color: colors.brandInk,
                              ),
                              const SizedBox(width: TpTokens.space2),
                              Expanded(
                                child: Text(
                                  '校园卡',
                                  style: TpTypography.cardTitle(colors)
                                      .copyWith(fontSize: 16),
                                ),
                              ),
                              Semantics(
                                label: 'Apple Watch 校园卡授权',
                                child: AdaptiveSwitch(
                                  value: sync.enabled,
                                  enabled: !sync.busy,
                                  onChanged: (enabled) => unawaited(
                                    enabled ? sync.enable() : sync.disable(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: TpTokens.space3,
                            ),
                            child: Divider(
                              height: 1,
                              thickness: 0.5,
                              color: colors.divider,
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Icon(
                                  summary.icon,
                                  size: TpTokens.iconM,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(width: TpTokens.space2),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      summary.title,
                                      key: const Key('watch-sync-summary'),
                                      style: TpTypography.itemTitle(colors)
                                          .copyWith(color: statusColor),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      summary.detail,
                                      style: TpTypography.itemMeta(colors),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (sync.enabled) ...[
                      const SizedBox(height: TpTokens.space4),
                      AdaptiveButton(
                        label: '更新并同步',
                        icon: TpIcons.refresh,
                        sfSymbol: 'arrow.triangle.2.circlepath',
                        role: AdaptiveButtonRole.prominent,
                        loading: sync.busy,
                        width: double.infinity,
                        height: 46,
                        onPressed: sync.busy
                            ? null
                            : () => unawaited(sync.synchronize(refresh: true)),
                      ),
                    ],
                    const SizedBox(height: TpTokens.space4),
                    TpCard(
                      child: Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          key: const PageStorageKey('watch-sync-details'),
                          title: Text(
                            '同步详情',
                            style: TpTypography.itemTitle(colors),
                          ),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: TpTokens.cardPaddingHorizontal,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            TpTokens.cardPaddingHorizontal,
                            0,
                            TpTokens.cardPaddingHorizontal,
                            TpTokens.space4,
                          ),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          children: [
                            _DetailRow(
                              label: '连接状态',
                              value: sync.ready ? '已识别配对手表' : '等待手表连接',
                            ),
                            _DetailRow(
                              label: '手机授权有效期',
                              value: _date(sync.status['phoneExpiresAt']),
                            ),
                            _DetailRow(
                              label: '手表授权有效期',
                              value: _date(sync.status['watchExpiresAt']),
                            ),
                            _DetailRow(
                              label: '同步版本',
                              value:
                                  '${sync.status['acknowledged'] ?? 0} / ${sync.status['revision'] ?? 0}',
                            ),
                            const SizedBox(height: TpTokens.space4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '本次操作记录',
                                style: TpTypography.cardMeta(colors).copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: TpTokens.space2),
                            if (sync.events.isEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '暂无操作记录',
                                  style: TpTypography.itemMeta(colors),
                                ),
                              ),
                            for (final event in sync.events.reversed)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 70,
                                      child: Text(
                                        '${event.at.hour.toString().padLeft(2, '0')}:${event.at.minute.toString().padLeft(2, '0')}:${event.at.second.toString().padLeft(2, '0')}',
                                        style: TpTypography.itemMeta(colors),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        event.text,
                                        style: TpTypography.itemMeta(colors)
                                            .copyWith(
                                          color: event.isError
                                              ? colors.dangerRed
                                              : colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TpTypography.itemMeta(colors).copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: TpTokens.space3),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TpTypography.itemMeta(colors),
            ),
          ),
        ],
      ),
    );
  }
}
