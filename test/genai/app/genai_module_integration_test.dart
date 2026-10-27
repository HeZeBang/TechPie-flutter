import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/genai/presentation/genai_login_page.dart';
import 'package:techpie/features/genai/presentation/genai_page.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/pages/third_party_bind_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_fixture.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';

void main() {
  testWidgets('GenAI opens from TechPie Home, connects and returns to the shell', (tester) async {
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await initializeDebugFixture();
    final storage = StorageService(await SharedPreferences.getInstance());
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger, inner: debugFixtureHttpClient());
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    await auth.loadSession();
    final bindings = ThirdPartyAuthService(storage, http);
    await bindings.initialize();
    final schedule = ScheduleService(storage, http, auth, bindings);
    await schedule.loadCachedData();
    final assignments = AssignmentService(storage, http, auth, bindings, schedule)..loadCached();
    await tester.pumpWidget(
      TechPieApp(
        preview: true,
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: ThemeService(storage),
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: bindings,
        oaGymService: OaGymService(auth, storage, bindings),
        egateAppService: EgateAppService(auth, storage, bindings),
        uniAuthService: uniAuth,
        syncService: SyncService(auth, bindings, storage),
        updateService: UpdateService(),
        campusCardService: CampusCardService(),
        ecardBindService: EcardBindService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Schedule'), findsWidgets);
    expect(find.text('Deadlines'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    await tester.ensureVisible(find.text('校园 GenAI'));
    await tester.tap(find.text('校园 GenAI'));
    await tester.pumpAndSettle();
    expect(find.byType(GenAiPage), findsOneWidget);
    final workspace = tester.widget<GenAiWorkspace>(find.byType(GenAiWorkspace));
    final runtime = ServiceProvider.of(tester.element(find.byType(GenAiPage))).genAiRuntime!;
    expect(workspace.controller.sessions, same(runtime.sessions));
    expect(runtime.sessions.owner?.studentId, '20240001');
    expect(runtime.sessions.session, isNull);

    await tester.tap(find.text('连接本地演示'));
    // The underlying connect button stays busy while its dialog is open.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('使用演示账号连接'));
    await tester.pumpAndSettle();
    expect(runtime.sessions.session, isNotNull);
    expect(workspace.controller.models, isNotEmpty);
    final sending = workspace.controller.send('帮我制定学习计划');
    for (var i = 0; i < 250 && workspace.controller.sending; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await sending;
    expect(workspace.controller.turns, hasLength(1));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(GenAiPage), findsNothing);
    expect(find.text('Home'), findsWidgets);
    // The feature shares the app runtime, so opening it again retains its login.
    await tester.tap(find.text('校园 GenAI'));
    await tester.pumpAndSettle();
    final reopened = tester.widget<GenAiWorkspace>(find.byType(GenAiWorkspace));
    expect(reopened.controller.sessions, same(runtime.sessions));
    expect(reopened.controller.connected, isTrue);
    expect(reopened.controller, same(workspace.controller));
    expect(reopened.controller.turns.single.answer, isNotEmpty);
    await reopened.controller.disconnect();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('GenAI 账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用 TechPie IDS 登录'));
    await tester.pumpAndSettle();
    final login = tester.widget<ThirdPartyBindPage>(find.byType(ThirdPartyBindPage));
    expect(login.platform, ThirdPartyPlatform.cpdaily);
    expect(runtime.sessions.owner?.studentId, '20240001');
    expect(runtime.sessions.session, isNull);
    // This is the existing TechPie password/SMS page, without a duplicate form.
    Navigator.of(tester.element(find.byType(ThirdPartyBindPage))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await bindings.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
        account: '20249999',
        token: 'real-cpdaily-token',
        boundAt: DateTime(2026),
        raw: const {'tgc': 'existing-ids-tgc'},
      ),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('genai-connect')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final genaiLogin = tester.widget<GenAiLoginPage>(find.byType(GenAiLoginPage));
    expect(genaiLogin.campusSession?.node, same(bindings.cpdailyNode));
    expect(
      genaiLogin.campusSession!.cookies.any(
        (cookie) => cookie.name == 'CASTGC' && cookie.value == 'existing-ids-tgc',
      ),
      isTrue,
    );
    expect(runtime.sessions.owner?.studentId, '20249999');
    Navigator.of(tester.element(find.byType(GenAiLoginPage))).pop();
    await tester.pumpAndSettle();
    // Keep the synthetic production-login check independent of course fetching.
    bindings.removeListener(schedule.requestFetch);
    // The production app also offers IDS identity resolution for an SMS binding.
    await bindings.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
        account: '13800138000',
        sid: '00000000-0000-0000-0000-000000000001',
        token: 'cpdaily-token',
        boundAt: DateTime(2026),
        raw: const {'tgc': 'existing-ids-tgc'},
      ),
    ]);
    final app = tester.widget<TechPieApp>(find.byType(TechPieApp));
    await tester.pumpWidget(
      TechPieApp(
        authService: app.authService,
        debugLogger: app.debugLogger,
        storageService: app.storageService,
        themeService: app.themeService,
        scheduleService: app.scheduleService,
        assignmentService: app.assignmentService,
        thirdPartyAuthService: app.thirdPartyAuthService,
        oaGymService: app.oaGymService,
        egateAppService: app.egateAppService,
        uniAuthService: app.uniAuthService,
        syncService: app.syncService,
        updateService: app.updateService,
        campusCardService: app.campusCardService,
        ecardBindService: app.ecardBindService,
      ),
    );
    await tester.pumpAndSettle();
    final production = ServiceProvider.of(tester.element(find.byType(GenAiPage))).genAiRuntime!;
    expect(production.isDemo, isFalse);
    expect(production.sessions.canIssue, isTrue);
    expect(production.sessions.owner, isNull);
    expect(find.text('使用现有 IDS 会话连接'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const ValueKey('genai-connect'))).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    schedule.dispose();
    assignments.dispose();
    bindings.dispose();
    auth.dispose();
    http.close();
  });
}
