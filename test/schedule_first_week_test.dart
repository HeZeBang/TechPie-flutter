import 'dart:convert';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/course_table.dart';
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

/// The timetable only draws for a signed-in user with a campus session.
class _SignedIn extends AuthService {
  _SignedIn(super.storage, super.http, super.uniAuth);

  @override
  bool get isLoggedIn => true;
}

class _Bound extends ThirdPartyAuthService {
  _Bound(super.storage, super.http);

  @override
  bool get hasCpdailyBinding => true;
}

void main() {
  late AppRuntime runtime;

  setUp(() async {
    // Seven weeks and a day into term: the current week is the 8th.
    final termBegin = DateTime.now().subtract(const Duration(days: 7 * 7 + 1));
    SharedPreferences.setMockInitialValues({
      // This test is about the timetable's first frame, not the consent gate.
      'privacy_accepted_v1': true,
      'schedule_selected_semester': 'term',
      'schedule_term_begin_term': jsonEncode(
        TermCalendar(
          code: 200,
          schoolYearTerm: '',
          termBegin: termBegin,
          snapshotDate: null,
          snapshotWeekOfTerm: null,
          allTeachWeeks: 16,
          allTermWeeks: 18,
          amClasses: 0,
          pmClasses: 0,
          eveClasses: 0,
        ).toJson(),
      ),
    });
    runtime = await buildDemoRuntime();
  });

  tearDown(() => runtime.dispose());

  testWidgets(
    'the first visit draws the current week from its first frame',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final logger = DebugLogger();
      final http = LoggingHttpClient(logger);
      final uniAuth = UniAuthService();
      final auth = _SignedIn(storage, http, uniAuth);
      final tpAuth = _Bound(storage, http);
      final schedule = ScheduleService(storage, http, auth, tpAuth);
      await schedule.loadCachedData();
      expect(schedule.currentWeek(), 8);

      await tester.pumpWidget(
        TechPieApp(
          authService: auth,
          debugLogger: logger,
          storageService: storage,
          themeService: ThemeService(storage),
          scheduleService: schedule,
          assignmentService:
              AssignmentService(storage, http, auth, tpAuth, schedule),
          thirdPartyAuthService: tpAuth,
          oaGymService: OaGymService(auth, storage, tpAuth),
          egateAppService: EgateAppService(auth, storage, tpAuth),
          uniAuthService: uniAuth,
          syncService: SyncService(auth, tpAuth, storage),
          updateService: UpdateService(),
          ecardBindService: EcardBindService(),
          campusCardService: CampusCardService.withStore(
            InMemorySecureCredentialStore(),
            runtimeFactory: () => runtime,
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.widget<CNTabBar>(find.byType(CNTabBar)).onTap(1);
      // One frame: the page as it is first drawn, before any post-frame jump.
      await tester.pump();

      // With no timetable cached, each week is drawn as its empty state.
      expect(find.byKey(const ValueKey<String>('empty-8')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('empty-1')), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
