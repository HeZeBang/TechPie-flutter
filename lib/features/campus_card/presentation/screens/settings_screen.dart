import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/debug_mode_controller.dart';
import '../../core/config/debug_mode_features.dart';
import '../../core/config/feedback_settings.dart';
import '../../core/config/payment_code_preferences.dart';
import '../../core/config/scan_payment_preferences.dart';
import '../../domain/models/feedback_models.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../widgets/apple_wallet_components.dart';

final class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debugMode = ref.watch(debugModeProvider);
    final skipScanConfirmation = ref.watch(skipScanConfirmationProvider);
    final maximizeBrightness =
        ref.watch(maximizePaymentCodeBrightnessProvider).valueOrNull;
    final offlineCodeFirst = ref.watch(offlineCodeFirstProvider).valueOrNull;
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
          title: '设置',
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              ApplePinnedHeaderLayout.contentTop,
              20,
              52,
            ),
            children: [
              AppleSection(
                footer: '开启后付款码先用本机离线码显示（每次生成消耗一次离线授权），'
                    '在线码就绪后自动切换。默认开启。',
                children: [
                  AppleListRow(
                    icon: GpPlatformIcons.offline(context),
                    label: '离线码优先',
                    verticalPadding: 4,
                    trailing: _SettingsSwitch(
                      key: const Key('offline-code-first'),
                      value: offlineCodeFirst ?? true,
                      onChanged: offlineCodeFirst == null
                          ? null
                          : (enabled) => unawaited(
                                ref
                                    .read(offlineCodeFirstProvider.notifier)
                                    .setEnabled(enabled),
                              ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AppleSection(
                footer: '开启后，显示付款码时使用最大亮度，离开后恢复。默认关闭，使用系统亮度。',
                children: [
                  AppleListRow(
                    icon: GpPlatformIcons.brightness(context),
                    label: '付款码最大亮度',
                    verticalPadding: 4,
                    trailing: _SettingsSwitch(
                      key: const Key('maximize-payment-code-brightness'),
                      value: maximizeBrightness ?? false,
                      onChanged: maximizeBrightness == null
                          ? null
                          : (enabled) => unawaited(
                                ref
                                    .read(
                                      maximizePaymentCodeBrightnessProvider
                                          .notifier,
                                    )
                                    .setEnabled(enabled),
                              ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AppleSection(
                footer:
                    debugModeFeaturesAvailable ? '开启后会添加用于测试的模拟活动记录。' : null,
                children: [
                  AppleListRow(
                    icon: GpPlatformIcons.scan(context),
                    label: '小额免密扫码跳过确认',
                    verticalPadding: 4,
                    trailing: _SettingsSwitch(
                      value: skipScanConfirmation,
                      onChanged: (value) => unawaited(
                        ref
                            .read(skipScanConfirmationProvider.notifier)
                            .setEnabled(value),
                      ),
                    ),
                  ),
                  if (debugModeFeaturesAvailable)
                    AppleListRow(
                      icon: GpPlatformIcons.debug(context),
                      label: '调试模式',
                      verticalPadding: 4,
                      trailing: _SettingsSwitch(
                        value: debugMode,
                        onChanged: (value) => unawaited(
                          ref
                              .read(debugModeProvider.notifier)
                              .setEnabled(value),
                        ),
                      ),
                    ),
                ],
              ),
              if (Theme.of(context).platform == TargetPlatform.iOS ||
                  Theme.of(context).platform == TargetPlatform.android)
                for (final scenario in FeedbackScenario.values) ...[
                  const SizedBox(height: 24),
                  _FeedbackSection(scenario: scenario),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _FeedbackSection extends ConsumerWidget {
  const _FeedbackSection({required this.scenario});

  final FeedbackScenario scenario;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(feedbackSettingsProvider(scenario)).valueOrNull;
    final header = switch (scenario) {
      FeedbackScenario.paymentSuccess => '支付成功',
      FeedbackScenario.networkDisconnected => '确认断网',
      FeedbackScenario.interaction => '其他操作',
    };
    return AppleSection(
      header: header,
      footer: scenario == FeedbackScenario.interaction
          ? '按钮、扫码识别等操作的震动反馈。'
          : null,
      children: [
        for (final channel in FeedbackChannel.values)
          if (channel == FeedbackChannel.vibration ||
              scenario != FeedbackScenario.interaction)
            AppleListRow(
              icon: channel == FeedbackChannel.vibration
                  ? GpPlatformIcons.vibration(context)
                  : GpPlatformIcons.sound(context),
              label: channel == FeedbackChannel.vibration ? '震动' : '音效',
              verticalPadding: 4,
              trailing: _SettingsSwitch(
                key: ValueKey('feedback-${scenario.name}-${channel.name}'),
                value: options == null
                    ? true
                    : channel == FeedbackChannel.vibration
                        ? options.vibration
                        : options.sound,
                onChanged: options == null
                    ? null
                    : (enabled) => unawaited(
                          ref
                              .read(feedbackSettingsProvider(scenario).notifier)
                              .setEnabled(channel, enabled),
                        ),
              ),
            ),
      ],
    );
  }
}

final class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) =>
      Switch.adaptive(value: value, onChanged: onChanged);
}
