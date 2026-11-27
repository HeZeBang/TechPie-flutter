import 'package:flutter/material.dart';

import '../pages/third_party_accounts_page.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/uni_auth_login.dart';

/// Shared signed-out / unbound-IDS state card for Campus Services pages.
///
/// Safely falls back when mounted inside isolated widget tests that omit
/// [ServiceProvider].
class CampusPrerequisiteView extends StatelessWidget {
  const CampusPrerequisiteView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.fallbackText = '请登录并绑定学校账号后使用',
    this.isSignedIn,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String fallbackText;
  final bool? isSignedIn;

  @override
  Widget build(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<ServiceProvider>();
    if (services == null) {
      final signedIn = isSignedIn ?? false;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(TpTokens.pageHorizontalPadding),
          child: TpPageBody(
            child: TpStateCard.prerequisite(
              icon: signedIn ? icon : TpIcons.login,
              leading: signedIn ? null : const TpBrandMark(size: 48),
              title: fallbackText,
              message: message,
              primaryActionLabel: signedIn ? '绑定 IDS 账号' : '登录 TechPie',
              primaryActionIcon: signedIn ? TpIcons.linkedAccounts : TpIcons.login,
              primaryActionSfSymbol:
                  signedIn ? 'key.horizontal' : 'person.crop.circle',
              onPrimaryAction: null,
            ),
          ),
        ),
      );
    }

    final signedIn = isSignedIn ?? services.authService.isLoggedIn;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TpTokens.pageHorizontalPadding),
        child: TpPageBody(
          child: TpStateCard.prerequisite(
            icon: signedIn ? icon : TpIcons.login,
            leading: signedIn ? null : const TpBrandMark(size: 48),
            title: signedIn ? '需要绑定 IDS 账号' : '需要先登录 TechPie',
            message: message ?? '$title复用已绑定的校园 IDS 登录态，不额外保存学校密码。',
            primaryActionLabel: signedIn ? '绑定 IDS 账号' : '登录 TechPie',
            primaryActionIcon: signedIn ? TpIcons.linkedAccounts : TpIcons.login,
            primaryActionSfSymbol:
                signedIn ? 'key.horizontal' : 'person.crop.circle',
            onPrimaryAction: () async {
              if (!signedIn) {
                await startUniAuthLogin(context);
              } else {
                await pushAdaptivePage<void>(
                  context,
                  builder: (_) => const ThirdPartyAccountsPage(),
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
