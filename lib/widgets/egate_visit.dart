import 'package:flutter/material.dart';

import '../pages/third_party_accounts_page.dart';
import '../services/campus/campus_errors.dart';
import '../services/campus/emap_client.dart';
import '../services/service_provider.dart';
import '../theme/tp_tokens.dart';
import 'adaptive_page_navigation.dart';
import 'design_system/design_system.dart';
import 'uni_auth_login.dart';

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
      listenable: Listenable.merge([services.authService, services.thirdPartyAuthService]),
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
          appBar: AppBar(title: Text(title)),
          body: Center(
            child: TextButton(
              onPressed: () async {
                if (signedIn) {
                  await pushAdaptivePage<void>(
                    context,
                    builder: (_) => const ThirdPartyAccountsPage(),
                  );
                } else {
                  await startUniAuthLogin(context);
                }
              },
              child: Text(signedIn ? '绑定 IDS 账号' : '登录 TechPie'),
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
            return TpCard(
              child: ListTile(
                title: Text(
                  switch (state.error) {
                    CampusRequestException(:final message) => message,
                    _ => '读取失败',
                  },
                ),
                trailing: TextButton(onPressed: retry, child: const Text('重试')),
              ),
            );
          }
          return widget.builder(state.data as T);
        },
      );
}

class EgateVisitBody extends StatelessWidget {
  const EgateVisitBody({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: TpPageBody(
          child: ListView.separated(
            padding: const EdgeInsets.all(TpTokens.pageHorizontalPadding),
            itemCount: children.length,
            itemBuilder: (_, i) => children[i],
            separatorBuilder: (_, i) => const SizedBox(height: TpTokens.sectionGap),
          ),
        ),
      );
}
