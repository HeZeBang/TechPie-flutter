import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../domain/models/offline_models.dart';
import '../../domain/ports/platform_ports.dart';
import '../app/navigation.dart';
import '../icons/geekpay_icons.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../widgets/apple_wallet_components.dart';
import '../widgets/gp_state.dart';

final class OfflineAuthorizationScreen extends ConsumerWidget {
  const OfflineAuthorizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(cardControllerProvider).valueOrNull;
    return Scaffold(
      body: AppleWalletPage(
        child: ApplePinnedHeaderLayout(
          leading: CampusCardHeaderAction(
            id: 'back',
            sfSymbol: 'chevron.left',
            icon: GpPlatformIcons.back(context),
            label: '返回',
            onPressed: () => popCampusCard(context),
          ),
          title: '离线授权',
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              ApplePinnedHeaderLayout.contentTop,
              20,
              52,
            ),
            children: [
              if (card == null)
                const GpStateView(
                  icon: GpIcons.card,
                  title: '绑定卡片',
                  description: '当前卡片状态无法付款',
                )
              else ...[
                Center(
                  child: SizedBox(
                    width: 170,
                    child: CampusWalletCard(
                      card: card,
                      compact: true,
                      heroTag: 'offline-card',
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                _AuthorizationBody(cardId: card.id),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _AuthorizationBody extends ConsumerWidget {
  const _AuthorizationBody({required this.cardId});

  final String cardId;

  String _date(BuildContext context, DateTime? value) => value == null
      ? '—'
      : DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offlineAuthorizationProvider(cardId));
    return switch (state) {
      AsyncError(:final error) => _PlainAuthorizationError(
          error,
          onRetry: () => ref.invalidate(offlineAuthorizationProvider(cardId)),
        ),
      AsyncLoading() => const Padding(
          padding: EdgeInsets.all(42),
          child: CupertinoActivityIndicator(radius: 13),
        ),
      AsyncData(:final value) => Column(
          children: [
            AppleSection(
              children: [
                AppleListRow(
                  icon: value.state == OfflineAuthorizationState.active ||
                          value.state == OfflineAuthorizationState.renewalDue
                      ? GpPlatformIcons.successCircle(context)
                      : GpPlatformIcons.errorCircle(context),
                  label: '账户状态',
                  value: _stateLabel(context, value.state),
                ),
                if (value.authorization?.isLimited == true)
                  AppleListRow(
                    label: '剩余次数',
                    value: value.authorization!.remaining.toString(),
                  ),
                AppleListRow(
                  label: '到期日',
                  value: _date(context, value.authorization?.expiresOn),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (value.state == OfflineAuthorizationState.unavailable ||
                value.state == OfflineAuthorizationState.missingCredential)
              FilledButton(
                onPressed: () => unawaited(
                  _runAction(
                    context,
                    ref,
                    () => ref
                        .read(offlineAuthorizationProvider(cardId).notifier)
                        .activate(),
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: context.gpColors.action,
                  minimumSize: const Size.fromHeight(54),
                  shape: const StadiumBorder(),
                ),
                child: const Text('立即开通'),
              )
            else ...[
              AppleSection(
                footer: '此操作只删除本机离线授权，不会在服务端吊销。',
                children: [
                  AppleListRow(
                    icon: GpPlatformIcons.refresh(context),
                    label: '续期',
                    onTap: () => unawaited(
                      _runAction(context, ref, () async {
                        await ref
                            .read(appRuntimeProvider)
                            .feedback
                            .play(FeedbackEvent.selection);
                        if (!context.mounted) return;
                        await ref
                            .read(offlineAuthorizationProvider(cardId).notifier)
                            .renew();
                      }),
                    ),
                  ),
                  AppleListRow(
                    icon: GpPlatformIcons.delete(context),
                    label: '移除此设备',
                    destructive: true,
                    onTap: () => unawaited(_remove(context, ref)),
                  ),
                ],
              ),
            ],
          ],
        ),
      _ => const SizedBox.shrink(),
    };
  }

  String _stateLabel(BuildContext context, OfflineAuthorizationState state) =>
      switch (state) {
        OfflineAuthorizationState.active ||
        OfflineAuthorizationState.renewalDue ||
        OfflineAuthorizationState.expired ||
        OfflineAuthorizationState.exhausted =>
          '已开通',
        OfflineAuthorizationState.missingCredential ||
        OfflineAuthorizationState.unavailable =>
          '未开通',
      };

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final accepted = await showAdaptiveDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('移除此设备'),
        content: const Text('此操作只删除本机离线授权，不会在服务端吊销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      await ref
          .read(offlineAuthorizationProvider(cardId).notifier)
          .removeFromDevice();
    }
  }

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (!context.mounted) return;
      await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.error);
      if (!context.mounted) return;
      await showAdaptiveDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => AlertDialog.adaptive(
          title: const Text('离线授权'),
          content: Text(GpStateView.safeUiError(error)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    }
  }
}

final class _PlainAuthorizationError extends StatelessWidget {
  const _PlainAuthorizationError(this.error, {required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('offline-authorization-error'),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              GpStateView.safeUiError(error),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      );
}
