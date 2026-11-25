import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/pages/third_party_bind_page.dart';
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

Future<Widget> _host(
  _BindingAuth tpAuth, {
  ThirdPartyPlatform platform = ThirdPartyPlatform.gradescope,
  double scale = 1,
  bool dark = false,
  double keyboardInset = 0,
}) async {
  final storage = tpAuth.storage;
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  final uniAuth = UniAuthService();
  final auth = AuthService(storage, http, uniAuth);
  final themeService = ThemeService(storage);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
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
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: ThirdPartyBindPage(platform: platform),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),),
        child: inner!,
      ),
    ),
  );
}

class _BindingAuth extends ThirdPartyAuthService {
  _BindingAuth(this.storage) : super(storage, LoggingHttpClient(DebugLogger()));
  final StorageService storage;
  Object? failure;
  Completer<void>? pending;
  int calls = 0;
  bool? renewal;
  List<String>? domains;
  String? origin;
  String? username;

  @override
  Future<ThirdPartyAccount> bind({
    required ThirdPartyPlatform platform,
    required String account,
    required String password,
    String? hydroOrigin,
    List<String>? hydroDomains,
    bool autoRenew = false,
    bool forceSyncPush = false,
  }) async {
    calls++;
    renewal = autoRenew;
    domains = hydroDomains;
    origin = hydroOrigin;
    username = account;
    if (pending != null) await pending!.future;
    if (failure case final error?) throw error;
    return ThirdPartyAccount(
      platform: platform,
      account: account,
      token: 'test',
      boundAt: DateTime(2026),
    );
  }
}

void main() {
  late _BindingAuth auth;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    auth = _BindingAuth(StorageService(await SharedPreferences.getInstance()));
  });

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> credentials(WidgetTester tester) async {
    await tester.enterText(find.byType(EditableText).first, 'student@example.edu');
    final password = find.byWidgetPredicate((w) => w is EditableText && w.obscureText);
    await tester.tap(password);
    tester.testTextInput.enterText('test-password');
    await tester.pump();
  }

  testWidgets('Hydro validates courses, edits its site, and preserves entries on back',
      (tester) async {
    await tester.pumpWidget(await _host(auth, platform: ThirdPartyPlatform.hydro));
    await tap(tester, 'Continue');
    expect(find.text('Enter at least one course domain.'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'course1, course2，course1');
    await tap(tester, 'Campus site · Change');
    await tester.enterText(find.byType(EditableText), 'invalid');
    await tap(tester, 'Use this site');
    expect(find.textContaining('Enter a site address'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'https://hydro.example.edu/');
    await tap(tester, 'Use this site');
    await tap(tester, 'Continue');
    await credentials(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('course1, course2，course1'), findsOneWidget);
    await tap(tester, 'Continue');
    await tap(tester, 'Connect Hydro');
    expect(auth.origin, 'https://hydro.example.edu');
    expect(auth.domains, ['course1', 'course2']);
    expect(auth.renewal, false);
    expect(find.text('Hydro connected'), findsOneWidget);
  });

  testWidgets('renewal needs consent and can be disabled before binding', (tester) async {
    await tester.pumpWidget(await _host(auth));
    await credentials(tester);
    await tap(tester, 'Automatic sign-in');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Off · Change'), findsOneWidget);
    await tap(tester, 'Automatic sign-in');
    await tap(tester, 'Allow automatic sign-in');
    expect(find.text('On · Change'), findsOneWidget);
    await tap(tester, 'Automatic sign-in');
    await tap(tester, 'Keep automatic sign-in off');
    await tap(tester, 'Connect Gradescope');
    expect(auth.renewal, false);
    expect(find.text('Gradescope connected'), findsOneWidget);
  });

  for (final platform in [ThirdPartyPlatform.hydro, ThirdPartyPlatform.gradescope]) {
    testWidgets('${platform.label} localizes a sign-in failure and preserves retry state',
        (tester) async {
      final dispatcher = tester.platformDispatcher;
      dispatcher.localeTestValue = const Locale('en');
      addTearDown(dispatcher.clearLocaleTestValue);
      final serverMessage = platform == ThirdPartyPlatform.hydro ? 'Login rejected' : '服务器登录失败';
      auth.failure = ThirdPartyBindException(platform, serverMessage);
      await tester.pumpWidget(await _host(auth, platform: platform));
      if (platform == ThirdPartyPlatform.hydro) {
        await tester.enterText(find.byType(EditableText), 'course1');
        await tap(tester, 'Continue');
      }
      await credentials(tester);
      await tap(tester, 'Automatic sign-in');
      await tap(tester, 'Allow automatic sign-in');
      await tap(tester, 'Connect ${platform.label}');
      final englishError = find.text('Could not sign in to ${platform.label}. Please try again.');
      expect(englishError, findsOneWidget);
      expect(find.text(serverMessage), findsNothing);
      expect(find.text('Try again'), findsOneWidget);

      dispatcher.localeTestValue = const Locale('zh', 'CN');
      await tester.pumpAndSettle();
      final chineseError = find.text('无法登录 ${platform.label}，请重试。');
      expect(chineseError, findsOneWidget);
      expect(englishError, findsNothing);
      expect(find.text(serverMessage), findsNothing);
      await tap(tester, '自动登录');
      expect(chineseError, findsNothing);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(chineseError, findsOneWidget);

      auth.failure = null;
      await tap(tester, '重试');
      expect(auth.calls, 2);
      expect(auth.renewal, true);
      expect(auth.username, 'student@example.edu');
      expect(find.text('${platform.label} 已连接'), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
    });
  }

  testWidgets('connection failure has a localized network prompt', (tester) async {
    final dispatcher = tester.platformDispatcher;
    dispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(dispatcher.clearLocaleTestValue);
    auth.failure = StateError('Network unavailable');
    await tester.pumpWidget(await _host(auth));
    await credentials(tester);
    await tap(tester, '连接 Gradescope');
    expect(find.text('无法连接。请检查网络后重试。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('pending sign-in blocks duplicate submits and back navigation', (tester) async {
    auth.pending = Completer<void>();
    await tester.pumpWidget(await _host(auth));
    await credentials(tester);
    final button = find.widgetWithText(FilledButton, 'Connect Gradescope');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(auth.calls, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Automatic sign-in'), findsOneWidget);
    auth.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Gradescope connected'), findsOneWidget);
  });

  testWidgets('small screen with large text keeps consent and actions reachable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(await _host(auth, scale: 2));
    await tap(tester, 'Automatic sign-in');
    await tap(tester, 'Allow automatic sign-in');
    expect(find.text('On · Change'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Chinese iOS entry uses native setup action and validates credentials',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.platformDispatcher.clearLocaleTestValue();
    });
    await tester.pumpWidget(await _host(auth));
    await tester.pumpAndSettle();
    final button = find.byWidgetPredicate((w) => w is CNButton && w.label == '连接 Gradescope');
    expect(button, findsOneWidget);
    tester.widget<CNButton>(button).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('请填写邮箱。'), findsOneWidget);
    expect(auth.calls, 0);
    await tap(tester, '自动登录');
    expect(find.text('保持账号连接？'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  for (final dark in [false, true]) {
    for (final platform in [ThirdPartyPlatform.hydro, ThirdPartyPlatform.gradescope]) {
      testWidgets(
          'Material ${platform.name} works in ${dark ? "dark" : "light"} mode with keyboard and large text',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
            await _host(auth, platform: platform, dark: dark, scale: 1.5, keyboardInset: 280),);
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(find.byType(ThirdPartyBindPage))).useMaterial3, isTrue);
        expect(find.byType(CNButton), findsNothing);
        expect(find.byType(TextField), findsWidgets);
        if (platform == ThirdPartyPlatform.hydro) {
          await tester.enterText(find.byType(EditableText), 'course1');
          await tap(tester, 'Continue');
        }
        await tap(tester, 'Automatic sign-in');
        await tap(tester, 'Allow automatic sign-in');
        expect(find.text('On · Change'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
