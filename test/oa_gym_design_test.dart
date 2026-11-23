import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/oa_gym_page.dart';
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
import 'package:techpie/widgets/gym/gym_booking_tab.dart';
import 'package:techpie/widgets/gym/gym_profile_tab.dart';
import 'package:techpie/widgets/gym/gym_search_tab.dart';

class _SignedInAuth extends AuthService {
  _SignedInAuth(super.storage, super.http, super.uniAuth);

  @override
  bool get isLoggedIn => true;

  @override
  UserSession? get session => UserSession(
        userId: '20240001',
        userName: '测试同学',
        schoolName: 'ShanghaiTech',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _BoundThirdParty extends ThirdPartyAuthService {
  _BoundThirdParty(super.storage, super.http);

  @override
  bool get hasIdsBinding => true;
}

Future<Widget> _buildGymHost({
  required bool loggedIn,
  required bool idsBound,
}) async {
  SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  final uniAuth = UniAuthService();
  final auth = loggedIn
      ? _SignedInAuth(storage, http, uniAuth)
      : AuthService(storage, http, uniAuth);
  final tpAuth = idsBound
      ? _BoundThirdParty(storage, http)
      : ThirdPartyAuthService(storage, http);
  final themeService = ThemeService(storage);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
  final campusCard = CampusCardService();
  final allowance = StudentAllowanceService(auth, tpAuth);
  addTearDown(campusCard.dispose);
  addTearDown(allowance.dispose);
  addTearDown(http.close);

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
    studentAllowanceService: allowance,
    uniAuthService: uniAuth,
    syncService: SyncService(auth, tpAuth, storage),
    updateService: UpdateService(),
    campusCardService: campusCard,
    ecardBindService: EcardBindService(),
    child: MaterialApp(
      theme: themeService.lightTheme,
      home: const OaGymPage(),
    ),
  );
}

void main() {
  testWidgets(
    'OaGymPage renders unified TpCard gate when signed out or unbound',
    (tester) async {
      await tester.pumpWidget(
        await _buildGymHost(loggedIn: false, idsBound: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('场馆预约'), findsOneWidget);
      expect(find.text('需要先登录 TechPie'), findsOneWidget);
      expect(find.byType(TpCard), findsOneWidget);
      expect(find.byType(TpPageBody), findsOneWidget);
    },
  );

  testWidgets(
    'OaGymPage renders modular booking, search, and profile tabs when ready',
    (tester) async {
      await tester.pumpWidget(
        await _buildGymHost(loggedIn: true, idsBound: true),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GymBookingTab), findsOneWidget);
      expect(find.text('预约条件'), findsOneWidget);

      await tester.tap(find.text('查询'));
      await tester.pumpAndSettle();
      expect(find.byType(GymSearchTab), findsOneWidget);
      expect(find.text('查询条件'), findsOneWidget);

      await tester.tap(find.text('个人信息'));
      await tester.pumpAndSettle();
      expect(find.byType(GymProfileTab), findsOneWidget);
      expect(find.text('预约提交信息'), findsOneWidget);
    },
  );
}
