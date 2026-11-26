import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/pages/ids_bind_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/ids/ids_client.dart';
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

import 'support/fake_ids_client.dart';

Future<Widget> _host(_CaptchaAuth tpAuth, {ThirdPartyAccount? legacy, double scale = 1}) async {
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
      home: IdsBindPage(legacyAccount: legacy),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: inner!,
      ),
    ),
  );
}

class _CaptchaAuth extends ThirdPartyAuthService {
  _CaptchaAuth(this.storage) : super(storage, LoggingHttpClient(DebugLogger()));
  final StorageService storage;
  int refreshCalls = 0;
  String? submittedCode;
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7XQAAAAASUVORK5CYII=',
  );
  @override
  Future<ThirdPartyAccount> bindIds({
    required String account,
    required String password,
    required IdsCaptchaPrompt promptCaptcha,
    bool Function()? isCancelled,
  }) async {
    submittedCode = await promptCaptcha(
      image,
      null,
      refresh: () async {
        refreshCalls++;
        return image;
      },
    );
    if (submittedCode == null) throw const IdsException('cancelled');
    return FakeIdsClient.account(account);
  }
}

void main() {
  for (final legacy in [false, true]) {
    testWidgets(
        'CAPTCHA remains actionable with large text during ${legacy ? "upgrade" : "sign-in"}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final auth = _CaptchaAuth(StorageService(await SharedPreferences.getInstance()));
      final old = ThirdPartyAccount(
        platform: ThirdPartyPlatform.ids,
        account: 'synthetic-student',
        password: 'synthetic-password',
        token: '',
        boundAt: DateTime(2026),
      );
      await tester.pumpWidget(await _host(auth, legacy: legacy ? old : null));
      await tester.pumpAndSettle();
      if (!legacy) {
        final fields = find.byType(EditableText);
        await tester.enterText(fields.first, 'synthetic-student');
        final password = find.byWidgetPredicate((w) => w is EditableText && w.obscureText);
        await tester.tap(password);
        tester.testTextInput.enterText('synthetic-password');
        await tester.pump();
      }
      await tester.tap(find.text(legacy ? 'Upgrade to a passkey' : 'Connect account'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(await _host(auth, legacy: legacy ? old : null, scale: 3));
      await tester.pumpAndSettle();
      expect(find.text('Enter the verification code'), findsOneWidget);
      expect(find.text('synthetic-student'), findsNothing);
      expect(find.text('Sign in manually'), findsNothing);
      await tester.ensureVisible(find.text('New image'));
      await tester.tap(find.text('New image'));
      await tester.pumpAndSettle();
      expect(auth.refreshCalls, 1);
      final field = find.byWidgetPredicate((w) => w is EditableText && !w.obscureText);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'sample-code');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(auth.submittedCode, 'sample-code');
      expect(find.text('Campus account connected'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
