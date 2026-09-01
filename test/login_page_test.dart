import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/pages/login_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  testWidgets('login failure keeps the login button reachable on a short screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = _FailingUniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    final thirdPartyAuth = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, thirdPartyAuth);
    final assignments =
        AssignmentService(storage, http, auth, thirdPartyAuth, schedule);

    await tester.pumpWidget(
      ServiceProvider(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: ThemeService(storage),
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: thirdPartyAuth,
        oaGymService: OaGymService(auth, storage, thirdPartyAuth),
        uniAuthService: uniAuth,
        syncService: SyncService(auth, thirdPartyAuth, storage),
        child: const MaterialApp(home: LoginPage()),
      ),
    );

    final loginButton = find.widgetWithText(
      FilledButton,
      '通过 GeekPie Uni-Auth 登录',
    );
    await tester.ensureVisible(loginButton);
    await tester.pumpAndSettle();
    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('登录失败：'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(loginButton);
    await tester.pumpAndSettle();
    final buttonRect = tester.getRect(loginButton);
    expect(buttonRect.top, greaterThanOrEqualTo(0));
    expect(buttonRect.bottom, lessThanOrEqualTo(480));
  });
}

class _FailingUniAuthService extends UniAuthService {
  @override
  Future<SsoTokens> login(BuildContext context) {
    throw Exception(
      '模拟一段足够长的认证错误，确保错误文本换行后不会盖住登录按钮。',
    );
  }
}
