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
/// OpenID entry lives in TechPie's Account settings rather than in this flow.
final class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final openAccount = ref.watch(campusCardAccountProvider);

    return Scaffold(
      body: AppleWalletPage(
        child: ApplePinnedHeaderLayout(
          leading: CampusCardHeaderAction(
            id: 'back',
            sfSymbol: 'chevron.left',
            icon: GpPlatformIcons.back(context),
            label: '返回',
            onPressed: () {
              popCampusCard(context);
            },
          ),
          title: 'eCard',
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              24,
              ApplePinnedHeaderLayout.contentTop + 36,
              24,
              36,
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
                '连接 eCard',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                '请在 TechPie 的 Account 设置中配置 OPENID。eCard 会自动使用该账号建立会话。',
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
                label: '打开 Account 设置',
                role: AdaptiveButtonRole.prominent,
                loading: auth.isLoading,
                width: double.infinity,
                accessibilityLabel: '打开 Account 设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
