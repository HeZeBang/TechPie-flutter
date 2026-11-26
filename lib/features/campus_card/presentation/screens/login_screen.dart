import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:techpie/widgets/adaptive_button.dart';

import '../../app/app_providers.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../widgets/apple_wallet_components.dart';
import '../widgets/gp_state.dart';

/// Account prerequisite shown when TechPie has no campus-card OpenID.
final class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final zh = View.of(context).platformDispatcher.locale.languageCode == 'zh';
    final connect = zh ? '连接我的校园卡' : 'Connect my card';
    final openAccount = ref.watch(campusCardAccountProvider);

    return Scaffold(
      body: AppleWalletPage(
        child: ApplePinnedHeaderLayout(
          leading: CampusCardHeaderAction(
            id: 'back',
            sfSymbol: 'chevron.left',
            icon: GpPlatformIcons.back(context),
            label: zh ? '返回' : 'Back',
            onPressed: () {
              popCampusCard(context);
            },
          ),
          title: 'eCard',
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              24,
              ApplePinnedHeaderLayout.contentTop(context) + 36,
              24,
              ApplePinnedHeaderLayout.contentBottom(context, 36),
            ),
            children: [
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    GpPlatformIcons.verifiedUser(context),
                    size: 46,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                zh ? '连接校园卡' : 'Connect your eCard',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                zh
                    ? '在 TechPie 中使用校园卡付款、查看交易记录。'
                    : 'Use your campus card for payments and recent activity in TechPie.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.gpColors.textSecondary,
                      height: 1.45,
                    ),
              ),
              if (auth case AsyncError(:final error)) ...[
                const SizedBox(height: 16),
                Text(
                  GpStateView.safeUiError(error),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.gpColors.danger),
                ),
              ],
              const SizedBox(height: 28),
              AdaptiveButton(
                onPressed: auth.isLoading ? null : openAccount,
                icon: Icons.manage_accounts_outlined,
                sfSymbol: 'person.crop.circle.badge.plus',
                label: connect,
                role: AdaptiveButtonRole.prominent,
                loading: auth.isLoading,
                width: double.infinity,
                accessibilityLabel: connect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
