import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/third_party_account.dart';
import '../../../pages/campus_session_handle.dart';
import '../../../pages/login_page.dart';
import '../../../pages/third_party_accounts_page.dart';
import '../../../pages/third_party_bind_page.dart';
import '../../../services/service_provider.dart';
import '../../../widgets/adaptive_feedback.dart';
import '../../../widgets/adaptive_page_navigation.dart';
import '../app/genai_runtime.dart';
import '../application/genai_agent_runner.dart';
import '../application/techpie_genai_tools.dart';
import '../domain/genai_session.dart';
import 'genai_login_page.dart';
import 'genai_workspace.dart';

class GenAiPage extends StatefulWidget {
  const GenAiPage({super.key});
  @override
  State<GenAiPage> createState() => _GenAiPageState();
}

class _GenAiPageState extends State<GenAiPage> {
  bool _openingLive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = ServiceProvider.of(context);
    final runtime = services.genAiRuntime;
    if (runtime == null || runtime.workspace.agentAvailable) return;
    final workspace = runtime.workspace;
    workspace.configureAgent(
      runner: GenAiAgentRunner(
        streamChat: runtime.repository.streamChat,
        tools: TechPieGenAiTools(
          schedule: services.scheduleService,
          assignments: services.assignmentService,
          gym: services.oaGymService,
          workspace: workspace,
          auth: services.authService,
          thirdPartyAuth: services.thirdPartyAuthService,
        ).createRegistry,
      ),
      scope: () {
        final accounts = [
          for (final account in services.thirdPartyAuthService.accounts)
            [
              account.platform.name,
              account.account,
              account.sid,
              account.boundAt.toUtc().toIso8601String(),
            ],
        ]..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
        return jsonEncode([services.authService.session?.userId, ...accounts]);
      },
      scopeChanges: Listenable.merge([
        services.authService,
        services.thirdPartyAuthService,
      ]),
    );
  }

  Future<void> _connectLive(GenAiRuntime runtime) async {
    if (_openingLive) return;
    setState(() => _openingLive = true);
    final services = ServiceProvider.of(context);
    final primary = services.authService.session?.userId;
    bool current() =>
        mounted &&
        identical(ServiceProvider.of(context).genAiRuntime, runtime) &&
        services.authService.session?.userId == primary;
    try {
      final bindings = services.thirdPartyAuthService;
      final cookies = bindings.cpdailyNode.cookieProvider?.cookies ?? '';
      if (!cookies.split(';').any((c) => c.trim().startsWith('CASTGC='))) {
        await pushAdaptivePage<void>(
          context,
          builder: (_) => const ThirdPartyBindPage(platform: ThirdPartyPlatform.cpdaily),
        );
      }
      if (!mounted || !current()) return;
      if (bindings.cpdailyNode.cookieProvider == null) {
        return;
      }
      if (runtime.sessions.canIssue) {
        await runtime.workspace.connectUsing(runtime.connectUsingCampusSession);
        return;
      }
      final revision = runtime.sessions.revision;
      final credential = await pushAdaptivePage<GenAiCredential>(
        context,
        builder: (_) => GenAiLoginPage(
          sessions: runtime.sessions,
          campusSession: CampusSessionHandle(bindings, bindings.cpdailyNode),
        ),
      );
      if (credential == null || !current() || revision != runtime.sessions.revision) {
        return;
      }
      await runtime.workspace.connect(credential);
    } catch (_) {
      if (mounted) {
        showAdaptiveFeedback(context: context, message: '无法完成 GenAI 登录，请重试');
      }
    } finally {
      if (mounted) setState(() => _openingLive = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = ServiceProvider.of(context);
    final runtime = services.genAiRuntime;
    if (runtime == null) {
      return const Scaffold(body: Center(child: Text('GenAI 暂不可用')));
    }
    final state = runtime.workspace;
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.authService,
        services.thirdPartyAuthService,
        runtime.sessions,
      ]),
      builder: (context, _) => GenAiWorkspace(
        controller: state,
        campusBound: services.thirdPartyAuthService.hasCpdailyBinding,
        onCampusLogin: runtime.sessions.canIssue ? () => unawaited(_connectLive(runtime)) : null,
        login: (context) async {
          if (runtime.sessions.canIssue) {
            await state.connectUsing(runtime.connectUsingCampusSession);
            return null;
          }
          return await pushAdaptivePage<GenAiCredential>(
            context,
            builder: (_) => GenAiLoginPage(
              sessions: state.sessions,
              campusSession: CampusSessionHandle(
                services.thirdPartyAuthService,
                services.thirdPartyAuthService.cpdailyNode,
              ),
            ),
          );
        },
        onSignIn:
            services.authService.isLoggedIn ? null : () => unawaited(presentLoginPage(context)),
        onBindCampus: () => unawaited(
          pushAdaptivePage<void>(
            context,
            builder: (_) => const ThirdPartyAccountsPage(),
          ),
        ),
      ),
    );
  }
}
