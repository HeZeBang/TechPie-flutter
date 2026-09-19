import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../widgets/apple_wallet_components.dart';
import '../widgets/gp_state.dart';

/// Shown when the saved binding cannot be turned into an online session right
/// now — an expired session, or a credential that could not be read.
///
/// Deliberately not the sign-in screen: the OPENID is still saved, so the user
/// has nothing to re-enter. This offers the retry that fixes it.
final class SessionRestoreScreen extends ConsumerWidget {
  const SessionRestoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      key: const Key('ecard-session-restore-page'),
      body: AppleWalletPage(
        child: ApplePinnedHeaderLayout(
          title: '恢复校园卡连接',
          leading: CampusCardHeaderAction(
            id: 'back',
            sfSymbol: 'chevron.left',
            icon: GpPlatformIcons.back(context),
            label: '返回',
            onPressed: () => popCampusCard(context),
          ),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              ApplePinnedHeaderLayout.contentTop,
              20,
              52,
            ),
            children: [
              if (auth.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CupertinoActivityIndicator(radius: 13)),
                )
              else
                GpStateView(
                  title: '恢复校园卡连接',
                  description: auth.hasError
                      ? GpStateView.safeUiError(auth.error!)
                      : '校园卡连接暂时不可用，解锁后重试即可。无需重新设置 OPENID。',
                  actionLabel: '重试',
                  onAction: () => ref.invalidate(authControllerProvider),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
