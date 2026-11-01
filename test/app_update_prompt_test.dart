import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/main.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';

void main() {
  // The check that runs by itself used to ask the widget above MaterialApp for
  // the dialog, which has neither MaterialLocalizations nor a navigator: the
  // prompt was raised, threw, and never appeared.
  testWidgets('the launch check shows its dialog through the app navigator', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The running version comes from a platform plugin the harness has no
    // implementation for; without it the check has nothing to compare against.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => call.method == 'getAll'
          ? {
              'appName': 'TechPie',
              'packageName': 'club.geekpie.techpie',
              'version': '1.0.1',
              'buildNumber': '1',
            }
          : null,
    );

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final logger = DebugLogger();
    final httpClient = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, httpClient, uniAuth);
    final theme = ThemeService(storage);
    final tpAuth = ThirdPartyAuthService(storage, httpClient);
    final schedule = ScheduleService(storage, httpClient, auth, tpAuth);
    final assignments =
        AssignmentService(storage, httpClient, auth, tpAuth, schedule);
    final oaGym = OaGymService(auth, storage, tpAuth);
    final egateApp = EgateAppService(auth, storage, tpAuth);
    final sync = SyncService(auth, tpAuth, storage);
    final updates = UpdateService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'v1.0.2+7',
            'name': 'v1.0.2',
            'body': '## 变更\n\n- 修好了某件事',
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await tester.pumpWidget(
      TechPieApp(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: theme,
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: oaGym,
        egateAppService: egateApp,
        uniAuthService: uniAuth,
        syncService: sync,
        updateService: updates,
        campusCardService: CampusCardService(),
        ecardBindService: EcardBindService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v1.0.2'), findsOneWidget);
    expect(find.text('前往更新'), findsOneWidget);
  });
}
