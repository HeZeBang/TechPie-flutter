import 'dart:async';

import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../services/watch_sync_service.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_switch.dart';
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
    unawaited(ServiceProvider.of(context)
        .campusCardService
        .watchSync
        .refreshStatus(),);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: IosNativeNavigationBar(
          title: 'Apple Watch',
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
            if (id == 'back') unawaited(maybePopAdaptivePage<void>(context));
          },
        ),
        body: WatchSettingsContent(
            sync: ServiceProvider.of(context).campusCardService.watchSync,),
      );
}

/// One actionable summary; transport details and session history stay collapsed.
class WatchSettingsContent extends StatelessWidget {
  const WatchSettingsContent({super.key, required this.sync});
  final WatchSyncService sync;

  static String _date(Object? seconds) {
    if (seconds is! num) return '暂无';
    final date = DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(),
            isUtc: true,)
        .subtract(const Duration(seconds: 1));
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  ({String title, String detail, IconData icon, bool warning}) _summary() {
    if (sync.busy) {
      return (
        title: '正在同步',
        detail: '正在更新卡片与离线授权',
        icon: Icons.sync,
        warning: false
      );
    }
    if (sync.hasError) {
      return (
        title: '同步未完成',
        detail: sync.message ?? '请稍后重试',
        icon: Icons.error_outline,
        warning: true
      );
    }
    if (!sync.enabled) {
      return (
        title: '未开启',
        detail: sync.message == '已取消授权，手表连接后会清除校园卡'
            ? '取消授权将在手表连接后生效'
            : '开启后，手表可离线展示校园卡消费码',
        icon: Icons.watch_outlined,
        warning: false
      );
    }
    if (!sync.isAcknowledged) {
      return (
        title: '等待手表接收',
        detail: '在手表上打开 TechPie 即可继续同步',
        icon: Icons.schedule,
        warning: false
      );
    }
    final expires = sync.status['watchExpiresAt'];
    if (expires is! num) {
      return (
        title: '待同步离线授权',
        detail: '请先在手机校园卡中开通或续期，再更新同步',
        icon: Icons.info_outline,
        warning: true
      );
    }
    if (expires * 1000 <= DateTime.now().millisecondsSinceEpoch) {
      return (
        title: '离线授权已到期',
        detail: '点击下方按钮更新授权',
        icon: Icons.info_outline,
        warning: true
      );
    }
    return (
      title: '已同步',
      detail: '离线使用至 ${_date(expires)}',
      icon: Icons.check_circle_outline,
      warning: false
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final summary = _summary();
          final statusColor = summary.warning ? colors.error : colors.primary;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.45),),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.watch_outlined, color: colors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text('校园卡',
                                  style: theme.textTheme.titleMedium,),),
                          Semantics(
                            label: 'Apple Watch 校园卡授权',
                            child: AdaptiveSwitch(
                              value: sync.enabled,
                              enabled: !sync.busy,
                              onChanged: (enabled) => unawaited(
                                  enabled ? sync.enable() : sync.disable(),),
                            ),
                          ),
                        ],),
                        const Divider(height: 28),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(summary.icon,
                                      size: 20, color: statusColor,),),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(summary.title,
                                        key: const Key('watch-sync-summary'),
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(color: statusColor),),
                                    const SizedBox(height: 5),
                                    Text(summary.detail,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color:
                                                    colors.onSurfaceVariant,),),
                                  ],),),
                            ],),
                      ],),
                ),
              ),
              if (sync.enabled) ...[
                const SizedBox(height: 16),
                AdaptiveButton(
                  label: '更新并同步',
                  icon: Icons.sync,
                  sfSymbol: 'arrow.triangle.2.circlepath',
                  role: AdaptiveButtonRole.prominent,
                  loading: sync.busy,
                  width: double.infinity,
                  onPressed: sync.busy
                      ? null
                      : () => unawaited(sync.synchronize(refresh: true)),
                ),
              ],
              const SizedBox(height: 20),
              ExpansionTile(
                key: const PageStorageKey('watch-sync-details'),
                title: const Text('同步详情'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  _DetailRow(
                      label: '连接状态', value: sync.ready ? '已识别配对手表' : '等待手表连接',),
                  _DetailRow(
                      label: '手机授权有效期',
                      value: _date(sync.status['phoneExpiresAt']),),
                  _DetailRow(
                      label: '手表授权有效期',
                      value: _date(sync.status['watchExpiresAt']),),
                  _DetailRow(
                      label: '同步版本',
                      value:
                          '${sync.status['acknowledged'] ?? 0} / ${sync.status['revision'] ?? 0}',),
                  const SizedBox(height: 20),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text('本次操作记录', style: theme.textTheme.labelLarge),),
                  const SizedBox(height: 8),
                  if (sync.events.isEmpty)
                    const Align(
                        alignment: Alignment.centerLeft, child: Text('暂无操作记录'),),
                  for (final event in sync.events.reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                                width: 70,
                                child: Text(
                                  '${event.at.hour.toString().padLeft(2, '0')}:${event.at.minute.toString().padLeft(2, '0')}:${event.at.second.toString().padLeft(2, '0')}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,),
                                ),),
                            Expanded(
                                child: Text(event.text,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: event.isError
                                            ? colors.error
                                            : colors.onSurface,),),),
                          ],),
                    ),
                ],
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),),
          const SizedBox(width: 12),
          Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,),),),
        ],),
      );
}
