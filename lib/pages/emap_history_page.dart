import 'dart:async';

import 'package:flutter/material.dart';

import '../models/feature.dart';
import '../services/campus/campus_errors.dart';
import '../services/campus/emap_account_cache.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/campus_prerequisite_view.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/page_refresh.dart';
import 'generic_webview_page.dart';

/// Shared history and official-form navigation for the two EGATE registrations.
class EmapHistoryPage extends StatelessWidget {
  const EmapHistoryPage({
    super.key,
    required this.service,
    required this.title,
    required this.webUrl,
    required this.webLabel,
    this.primaryAction,
    required this.refresh,
    required this.content,
  });

  final EmapAccountCache service;
  final String title, webUrl, webLabel;
  final Widget Function(Widget schoolFormButton)? primaryAction;
  final Future<void> Function() refresh;
  final Widget Function(bool loaded) content;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: service,
        builder: (_, __) => _AccountHistory(
          key: ValueKey((service, service.revision)),
          page: this,
        ),
      );
}

class _AccountHistory extends StatefulWidget {
  const _AccountHistory({super.key, required this.page});
  final EmapHistoryPage page;

  @override
  State<_AccountHistory> createState() => _AccountHistoryState();
}

class _AccountHistoryState extends State<_AccountHistory> {
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.page.service.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(refresh());
      });
    }
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.page.refresh();
    } catch (e) {
      if (mounted) {
        error = e is CampusRequestException ? e.message : '读取学校记录失败';
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final page = widget.page;
    final ready = page.service.ready;
    final loaded = page.service.values.containsKey('history');
    final schoolFormButton = Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton.icon(
        onPressed: () => pushAdaptivePage<void>(
          context,
          builder: (_) => GenericWebViewPage(
            title: page.title,
            url: page.webUrl,
            cookieType: CookieType.egateApp,
          ),
        ),
        icon: const Icon(TpIcons.externalLink),
        label: Text(page.webLabel),
      ),
    );
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: BlurredAppBar(
        title: Text(page.title),
        actions: [
          PageRefreshButton(
            onRefresh: refresh,
            enabled: ready,
            refreshing: busy,
          ),
          if (!isDesktop())
            IconButton(
              tooltip: '刷新',
              icon: const Icon(TpIcons.refresh),
              onPressed: busy || !ready ? null : refresh,
            ),
        ],
      ),
      body: !ready
          ? CampusPrerequisiteView(
              icon: TpIcons.linkedAccounts,
              title: page.title,
              fallbackText: page.service.identity().user == null
                  ? '请先登录 TechPie'
                  : '需要绑定 IDS 账号',
              isSignedIn: page.service.identity().user != null &&
                  (context
                          .dependOnInheritedWidgetOfExactType<ServiceProvider>()
                          ?.authService
                          .isLoggedIn ??
                      true),
            )
          : PageRefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  TpTokens.pageHorizontalPadding,
                  TpTokens.space4,
                  TpTokens.pageHorizontalPadding,
                  AppShellMetrics.bottomContentPaddingOf(context),
                ),
                children: [
                  TpPageBody(
                    maxWidth: 880,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        page.primaryAction?.call(schoolFormButton) ??
                            schoolFormButton,
                        const SizedBox(height: TpTokens.sectionGap),
                        if (busy) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: TpTokens.space2),
                        ],
                        if (error != null) ...[
                          TpStateCard.error(
                            title: error!,
                            message: loaded ? '当前显示上次读取的记录' : null,
                            compact: true,
                            onPrimaryAction: refresh,
                          ),
                          const SizedBox(height: TpTokens.space3),
                        ],
                        page.content(loaded),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
