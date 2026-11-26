import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/home_page.dart';
import 'package:techpie/pages/settings_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_allowance_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/utils/user_display_name.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';

String _encodeJwt(Map<String, Object?> payload) {
  String b64(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${b64(const {'alg': 'HS256', 'typ': 'JWT'})}.${b64(payload)}.sig';
}

UserSession _session({
  String userId = 'u-1',
  String userName = 'sample_handle',
  String? geekpieToken,
}) =>
    UserSession(
      userId: userId,
      userName: userName,
      schoolName: '上海科技大学',
      createdAt: DateTime(2026, 1, 1),
      geekpieToken: geekpieToken,
    );

class _FakeAuthService extends AuthService {
  _FakeAuthService(
    super.storage,
    super.http,
    super.uniAuth, {
    UserSession? session,
  }) : _current = session;

  UserSession? _current;

  @override
  bool get isLoggedIn => _current != null;

  @override
  UserSession? get session => _current;

  void setTestSession(UserSession? next) {
    _current = next;
    notifyListeners();
  }
}

class _FakeThirdPartyAuth extends ThirdPartyAuthService {
  _FakeThirdPartyAuth(
    super.storage,
    super.http, {
    ThirdPartyAccount? ids,
  }) : _ids = ids;

  ThirdPartyAccount? _ids;

  @override
  bool get hasIdsBinding => _ids != null;

  @override
  ThirdPartyAccount? get idsAccount => _ids;

  void setIdsAccount(ThirdPartyAccount? next) {
    _ids = next;
    notifyListeners();
  }
}

Future<Widget> _wrapWithServices({
  required AuthService auth,
  required ThirdPartyAuthService tpAuth,
  required StorageService storage,
  required DebugLogger logger,
  required LoggingHttpClient httpClient,
  required UniAuthService uniAuth,
  required Widget child,
}) async {
  final themeService = ThemeService(storage);
  final schedule = ScheduleService(storage, httpClient, auth, tpAuth);
  await schedule.loadCachedData();
  final assignments = AssignmentService(storage, httpClient, auth, tpAuth, schedule)
    ..loadCached();
  return ServiceProvider(
    authService: auth,
    debugLogger: logger,
    storageService: storage,
    themeService: themeService,
    scheduleService: schedule,
    assignmentService: assignments,
    thirdPartyAuthService: tpAuth,
    oaGymService: OaGymService(auth, storage, tpAuth),
    egateAppService: EgateAppService(auth, storage, tpAuth),
    studentAllowanceService: StudentAllowanceService(auth, tpAuth),
    uniAuthService: uniAuth,
    syncService: SyncService(auth, tpAuth, storage),
    updateService: UpdateService(),
    campusCardService: CampusCardService(),
    ecardBindService: EcardBindService(),
    child: MaterialApp(
      theme: themeService.lightTheme,
      darkTheme: themeService.darkTheme,
      builder: (_, inner) => AdaptiveFeedbackHost(
        child: inner ?? const SizedBox.shrink(),
      ),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveUserDisplayName', () {
    test('returns empty string when signed out even if campus bindings exist', () {
      expect(
        resolveUserDisplayName(
          session: null,
          idsRealName: '王同学',
          campusCardOwnerName: '李示例',
        ),
        '',
      );
    });

    test('prefers IDS real name over eCard, JWT displayName, session userName, and userId', () {
      final jwt = _encodeJwt(const {
        'name': 'sample_handle',
        'displayName': '陈示例',
      });
      final s = _session(userName: 'sample_handle', geekpieToken: jwt);

      expect(
        resolveUserDisplayName(
          session: s,
          idsRealName: '  王同学  ',
          campusCardOwnerName: '李示例',
        ),
        '王同学',
      );
      expect(
        resolveUserDisplayName(
          session: s,
          idsRealName: ' ',
          campusCardOwnerName: ' 李示例 ',
        ),
        '李示例',
      );
      expect(
        resolveUserDisplayName(
          session: s,
          idsRealName: null,
          campusCardOwnerName: null,
        ),
        '陈示例',
      );
      expect(
        resolveUserDisplayName(
          session: _session(userName: '张示例', geekpieToken: jwt),
        ),
        '张示例',
      );
      expect(
        resolveUserDisplayName(
          session: _session(userId: '20240001', userName: ''),
        ),
        '20240001',
      );
    });

    test('userAvatarLabel handles CJK, ASCII, and empty names', () {
      expect(userAvatarLabel('王同学'), '王');
      expect(userAvatarLabel('alice'), 'AL');
      expect(userAvatarLabel(' '), 'GP');
    });
  });

  group('AuthService Casdoor JWT displayName extraction', () {
    test('geekpieLogin and tryRenewSession upgrade username-only session name from JWT displayName', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final logger = DebugLogger();
      final httpClient = LoggingHttpClient(
        logger,
        inner: MockClient((request) async {
          expect(request.url.path, '/api/auth/geekpie');
          return http.Response(
            jsonEncode({
              'success': true,
              'userId': 'u-1',
              'userName': 'sample_handle',
            }),
            200,
          );
        }),
      );
      addTearDown(httpClient.close);

      final refreshedJwt = _encodeJwt(const {
        'name': 'sample_handle',
        'displayName': '赵同学',
      });
      final uniAuth = UniAuthService(
        refreshRequest: (_) async => http.Response(
          jsonEncode({
            'access_token': refreshedJwt,
            'refresh_token': 'rt-2',
            'expires_in': 7200,
          }),
          200,
        ),
      );
      final auth = AuthService(storage, httpClient, uniAuth);

      final initialJwt = _encodeJwt(const {
        'name': 'sample_handle',
        'displayName': '陈同学',
      });
      final loggedIn = await auth.geekpieLogin(
        SsoTokens(
          accessToken: initialJwt,
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        ),
      );
      expect(loggedIn.userName, '陈同学');

      await storage.saveSession(
        UserSession(
          userId: 'u-1',
          userName: 'sample_handle',
          schoolName: '上海科技大学',
          createdAt: DateTime(2026, 1, 1),
          geekpieToken: 'stale-token',
          geekpieExpiresAt:
              DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
          geekpieRefreshToken: 'rt-1',
        ),
      );
      await auth.loadSession();
      final result = await auth.tryRenewSession(force: true);
      expect(result, SessionRenewalResult.renewed);
      expect(auth.session?.userName, '赵同学');
    });
  });

  testWidgets('HomePage and SettingsPage display IDS real name and react to IDS updates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final logger = DebugLogger();
    final httpClient = LoggingHttpClient(logger);
    addTearDown(httpClient.close);
    final uniAuth = UniAuthService();

    final auth = _FakeAuthService(
      storage,
      httpClient,
      uniAuth,
      session: _session(userId: 'u-1', userName: 'sample_handle'),
    );
    final tpAuth = _FakeThirdPartyAuth(storage, httpClient);

    await tester.pumpWidget(
      await _wrapWithServices(
        auth: auth,
        tpAuth: tpAuth,
        storage: storage,
        logger: logger,
        httpClient: httpClient,
        uniAuth: uniAuth,
        child: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home.greeting-header')),
        matching: find.textContaining('，sample_handle'),
      ),
      findsOneWidget,
    );

    tpAuth.setIdsAccount(
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.ids,
        account: '20240001',
        name: '周同学',
        token: '',
        boundAt: DateTime(2026, 1, 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home.greeting-header')),
        matching: find.textContaining('，周同学'),
      ),
      findsOneWidget,
    );
    expect(find.text('sample_handle'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home.avatar')),
        matching: find.text('周'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      await _wrapWithServices(
        auth: auth,
        tpAuth: tpAuth,
        storage: storage,
        logger: logger,
        httpClient: httpClient,
        uniAuth: uniAuth,
        child: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('周同学'), findsOneWidget);
    expect(find.text('sample_handle'), findsNothing);
  });
}
