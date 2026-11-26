import 'dart:async';

import 'package:flutter/material.dart';

import '../models/feature.dart';
import '../services/campus/campus_errors.dart';
import '../services/campus/emap_account_cache.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/page_refresh.dart';
import '../widgets/uni_auth_login.dart';
import 'generic_webview_page.dart';
import 'third_party_accounts_page.dart';

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
      if (mounted) error = e is CampusRequestException ? e.message : '读取学校记录失败';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        icon: const Icon(Icons.open_in_new),
        label: Text(page.webLabel),
      ),
    );
    return Scaffold(
      backgroundColor: context.tpColors.canvas,
      appBar: AppBar(
        title: Text(page.title),
        actions: [PageRefreshButton(onRefresh: refresh, enabled: ready, refreshing: busy)],
      ),
      body: SafeArea(
        child: !ready
            ? Center(
                child: FilledButton(
                  onPressed: () async {
                    if (!ServiceProvider.of(context).authService.isLoggedIn) {
                      await startUniAuthLogin(context);
                    } else {
                      await pushAdaptivePage<void>(
                        context,
                        builder: (_) => const ThirdPartyAccountsPage(),
                      );
                    }
                  },
                  child: Text(page.service.identity().user == null ? '登录 TechPie' : '绑定 IDS 账号'),
                ),
              )
            : PageRefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(TpTokens.space4),
                  children: [
                    TpPageBody(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          page.primaryAction?.call(schoolFormButton) ?? schoolFormButton,
                          const SizedBox(height: TpTokens.sectionGap),
                          if (busy) const LinearProgressIndicator(),
                          if (error != null)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(error!),
                              subtitle: loaded ? const Text('显示上次读取的记录') : null,
                              trailing: TextButton(onPressed: refresh, child: const Text('重试')),
                            ),
                          page.content(loaded),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
