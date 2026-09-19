import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../widgets/apple_wallet_components.dart';
import 'security_limit_screen.dart';
import 'security_password_screen.dart';

final class SecurityHubScreen extends ConsumerWidget {
  const SecurityHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(appRuntimeProvider).capabilities;
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
          title: '安全中心',
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
                children: [
                  AppleListRow(
                    icon: GpPlatformIcons.password(context),
                    label: '修改消费密码',
                    value: caps.changeSpendingPassword
                        ? null
                        : '服务暂未开放',
                    onTap: caps.changeSpendingPassword
                        ? () => unawaited(
                              pushCampusCardPage<void>(context, builder: (_) => const SecurityPasswordScreen()),
                            )
                        : null,
                  ),
                  AppleListRow(
                    icon: GpPlatformIcons.limits(context),
                    label: '消费限额',
                    value: caps.spendingLimits ? null : '服务暂未开放',
                    onTap: caps.spendingLimitsRead
                        ? () => unawaited(
                              pushCampusCardPage<void>(context, builder: (_) => const SecurityLimitScreen()),
                            )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
