import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/pages/elrc_recordings_page.dart';
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
import 'package:techpie/widgets/design_system/design_system.dart';

void main() {
  testWidgets(
    'ElrcRecordingsPage renders unified TpCard state on unsupported desktop target',
    (tester) async {
      SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final logger = DebugLogger();
      final http = LoggingHttpClient(logger);
      final uniAuth = UniAuthService();
      final auth = AuthService(storage, http, uniAuth);
      final tpAuth = ThirdPartyAuthService(storage, http);
      final themeService = ThemeService(storage);
      final schedule = ScheduleService(storage, http, auth, tpAuth);
      final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
      final campusCard = CampusCardService();
      final allowance = StudentAllowanceService(auth, tpAuth);
      addTearDown(campusCard.dispose);
      addTearDown(allowance.dispose);
      addTearDown(http.close);

      await tester.pumpWidget(
        ServiceProvider(
          authService: auth,
          debugLogger: logger,
          storageService: storage,
          themeService: themeService,
          scheduleService: schedule,
          assignmentService: assignments,
          thirdPartyAuthService: tpAuth,
          oaGymService: OaGymService(auth, storage, tpAuth),
          egateAppService: EgateAppService(auth, storage, tpAuth),
          studentAllowanceService: allowance,
          uniAuthService: uniAuth,
          syncService: SyncService(auth, tpAuth, storage),
          updateService: UpdateService(),
          campusCardService: campusCard,
          ecardBindService: EcardBindService(),
          child: MaterialApp(
            theme: themeService.lightTheme,
            home: const ElrcRecordingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('课程录播'), findsOneWidget);
      expect(find.text('请在 iPhone 或 Android 手机中观看录播'), findsOneWidget);
      expect(find.byType(TpCard), findsOneWidget);
      expect(find.byType(TpPageBody), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
