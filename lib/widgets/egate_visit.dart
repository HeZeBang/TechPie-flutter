import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/third_party_accounts_page.dart';
import '../services/campus/campus_errors.dart';
import '../services/campus/emap_client.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/uni_auth_login.dart';
import 'adaptive_page_navigation.dart';

/// The current account owns this subtree, including Futures containing personal
/// records. Account or binding changes remount the child subtree.
class EgateVisit extends StatelessWidget {
  const EgateVisit({
    super.key,
    required this.title,
    required this.builder,
    this.dropWhenInactive = false,
  });

  final String title;
  final Widget Function(EmapClient client, String studentId) builder;
  final bool dropWhenInactive;

  @override
  Widget build(BuildContext context) {
    if (dropWhenInactive && !TickerMode.valuesOf(context).enabled) {
      return const SizedBox.shrink();
    }
    final services = ServiceProvider.of(context);
    return ListenableBuilder(
      listenable:
          Listenable.merge([services.authService, services.thirdPartyAuthService]),
      builder: (context, _) {
        final client = services.campusClients?.emap;
        final owner = client?.session.identity();
        final student = services.thirdPartyAuthService.idsStudentId;
        if (client != null && owner?.user != null && owner?.ids != null) {
          return KeyedSubtree(
            key: ValueKey((client, owner, student)),
            child: builder(client, student),
          );
        }
        final signedIn = services.authService.isLoggedIn;
        return Scaffold(
          backgroundColor: context.tpColors.canvas,
          appBar: AdaptiveNavigationScaffold.adaptiveBar(
            ios: () => IosNativeNavigationBar(
              title: title,
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: '返回',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回',
                  placementGroup: 'leading-main',
                ),
              ],
              onItemPressed: (_) => unawaited(maybePopAdaptivePage<void>(context)),
            ),
            material: () => BlurredAppBar(title: Text(title)),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(TpTokens.pageHorizontalPadding),
              child: TpPageBody(
                child: TpStateCard.prerequisite(
                  icon: signedIn ? TpIcons.linkedAccounts : TpIcons.login,
                  title: signedIn ? '需要绑定 IDS 账号' : '需要先登录 TechPie',
                  message: '$title复用已绑定的校园 IDS 登录态，不额外保存密码。',
                  primaryActionLabel: signedIn ? '绑定 IDS 账号' : '登录 TechPie',
                  primaryActionIcon:
                      signedIn ? TpIcons.linkedAccounts : TpIcons.login,
                  primaryActionSfSymbol:
                      signedIn ? 'key.horizontal' : 'person.crop.circle',
                  onPrimaryAction: () async {
                    if (signedIn) {
                      await pushAdaptivePage<void>(
                        context,
                        builder: (_) => const ThirdPartyAccountsPage(),
                      );
                    } else {
                      await startUniAuthLogin(context);
                    }
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Mount one query for the selected account, date or section.
class EgateQueryResult<T> extends StatefulWidget {
  const EgateQueryResult({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(T data) builder;

  @override
  State<EgateQueryResult<T>> createState() => _EgateQueryResultState<T>();
}

class _EgateQueryResultState<T> extends State<EgateQueryResult<T>> {
  late Future<T> future = widget.load();

  void retry() {
    if (!mounted) return;
    setState(() => future = widget.load()..ignore());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (state.hasError) {
            return TpStateCard.error(
              title: switch (state.error) {
                CampusRequestException(:final message) => message,
                _ => '读取失败',
              },
              compact: true,
              onPrimaryAction: retry,
            );
          }
          return widget.builder(state.data as T);
        },
      );
}

class EgateVisitBody extends StatelessWidget {
  const EgateVisitBody({
    super.key,
    required this.children,
    this.topInset = 0,
  });

  final List<Widget> children;
  final double topInset;

  @override
  Widget build(BuildContext context) => TpPageBody(
        maxWidth: 880,
        child: ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            TpTokens.pageHorizontalPadding,
            topInset + TpTokens.space4,
            TpTokens.pageHorizontalPadding,
            AppShellMetrics.bottomContentPaddingOf(context),
          ),
          itemCount: children.length,
          itemBuilder: (_, i) => children[i],
          separatorBuilder: (_, i) =>
              const SizedBox(height: TpTokens.sectionGap),
        ),
      );
}
