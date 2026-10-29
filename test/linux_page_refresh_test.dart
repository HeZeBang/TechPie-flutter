import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/presentation/screens/card_manage_screen.dart';
import 'package:techpie/features/campus_card/presentation/screens/payment_code_page.dart';
import 'package:techpie/models/course_table.dart';
import 'package:techpie/pages/assignments_page.dart';
import 'package:techpie/pages/egate_app_page.dart';
import 'package:techpie/pages/schedule_page.dart';
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
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/page_refresh.dart';

void main() {
  testWidgets(
    'schedule refresh preserves the week and awaits both sources',
    (tester) async {
      tester.view.physicalSize = const Size(480, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final services = await _Services.create();
      await tester.pumpWidget(services.host(const SchedulePage()));
      expect(find.text('课表加载失败，点击右上角刷新重试'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsNothing);
      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      services.assignments.examGate = Completer<void>();
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      expect(services.schedule.refreshCalls, 1);
      expect(services.assignments.examCalls, 1);
      expect(find.byTooltip('正在刷新'), findsOneWidget);
      expect(find.text('第 2 周'), findsOneWidget);
      services.assignments.examGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byTooltip('刷新'), findsOneWidget);
      expect(find.text('第 2 周'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'empty deadlines can refresh from their header',
    (tester) async {
      final services = await _Services.create();
      await tester.pumpWidget(services.host(const AssignmentsPage()));
      expect(find.byType(RefreshIndicator), findsNothing);
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      expect(services.assignments.refreshCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'check-in error can retry and logout disables the header action',
    (tester) async {
      final services = await _Services.create();
      await tester.pumpWidget(services.host(const EgateAppPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('test offline'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsNothing);
      services.egate.fail = false;
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(services.egate.calls, 2);
      expect(find.textContaining('test offline'), findsNothing);
      services.auth.signedIn = false;
      services.auth.notifyListeners();
      await tester.pump();
      final action =
          find.descendant(of: find.byType(PageRefreshButton), matching: find.byType(IconButton));
      expect(tester.widget<IconButton>(action).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );

  for (final platform in [TargetPlatform.linux, TargetPlatform.android]) {
    testWidgets(
      'campus card pages retain platform-specific refresh controls',
      (tester) async {
        tester.view.physicalSize = const Size(480, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final runtime = await buildDemoRuntime();
        await runtime.auth.signIn(const DemoAuthCredential());
        final scope = ProviderContainer(overrides: [appRuntimeProvider.overrideWithValue(runtime)]);

        Widget host(Widget page) =>
            UncontrolledProviderScope(container: scope, child: MaterialApp(home: page));
        await tester.pumpWidget(host(const PaymentCodePage()));
        await tester.pumpAndSettle();
        expect(
          find.byType(PageRefreshButton),
          platform == TargetPlatform.linux ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
          platform == TargetPlatform.linux ? findsNothing : findsOneWidget,
        );
        if (platform == TargetPlatform.linux) {
          await tester.tap(find.byTooltip('刷新'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(host(const CardManageScreen()));
        await tester.pumpAndSettle();
        expect(
          find.byType(PageRefreshButton),
          findsNothing,
          reason: 'The information tab has no activity refresh.',
        );
        await tester.tap(find.text('使用明细'));
        await tester.pumpAndSettle();
        expect(
          find.byType(PageRefreshButton),
          platform == TargetPlatform.linux ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
          platform == TargetPlatform.linux ? findsNothing : findsOneWidget,
        );
        if (platform == TargetPlatform.linux) {
          await tester.tap(find.byTooltip('刷新'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        scope.dispose();
        await tester.pump();
        await runtime.dispose();
      },
      variant: TargetPlatformVariant({platform}),
    );
  }
}

class _Services {
  _Services(
    this.storage,
    this.http,
    this.auth,
    this.tpAuth,
    this.schedule,
    this.assignments,
    this.egate,
  );
  final StorageService storage;
  final LoggingHttpClient http;
  final _Auth auth;
  final ThirdPartyAuthService tpAuth;
  final _Schedule schedule;
  final _Assignments assignments;
  final _Egate egate;

  static Future<_Services> create() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final http = LoggingHttpClient(DebugLogger());
    final auth = _Auth(storage, http, UniAuthService());
    final tp = _ThirdParty(storage, http);
    final schedule = _Schedule(storage, http, auth, tp);
    final assignments = _Assignments(storage, http, auth, tp, schedule);
    final egate = _Egate(auth, storage, tp);
    addTearDown(() {
      assignments.dispose();
      schedule.dispose();
      tp.dispose();
      auth.dispose();
      http.close();
      egate.dispose();
    });
    return _Services(storage, http, auth, tp, schedule, assignments, egate);
  }

  Widget host(Widget page) => ServiceProvider(
        authService: auth,
        debugLogger: DebugLogger(),
        storageService: storage,
        themeService: ThemeService(storage),
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: OaGymService(auth, storage, tpAuth),
        egateAppService: egate,
        uniAuthService: UniAuthService(),
        syncService: SyncService(auth, tpAuth, storage),
        updateService: UpdateService(),
        campusCardService: CampusCardService.withStore(InMemorySecureCredentialStore()),
        ecardBindService: EcardBindService(),
        child: MaterialApp(home: page),
      );
}

class _Auth extends AuthService {
  _Auth(super.storage, super.http, super.uniAuth);
  bool signedIn = true;
  @override
  bool get isLoggedIn => signedIn;
}

class _ThirdParty extends ThirdPartyAuthService {
  _ThirdParty(super.storage, super.http);
  @override
  bool get hasCpdailyBinding => true;
}

class _Schedule extends ScheduleService {
  _Schedule(super.storage, super.http, super.auth, super.tpAuth);
  int refreshCalls = 0;
  @override
  SemesterInfo get semesterInfo => const SemesterInfo(
        semesters: {},
        defaultSemester: 'test',
        tableId: 'test',
      );
  @override
  String? get error => refreshCalls == 0 ? 'test offline' : null;
  @override
  Future<void> fetchAll() async {
    refreshCalls++;
    notifyListeners();
  }
}

class _Assignments extends AssignmentService {
  _Assignments(super.storage, super.http, super.auth, super.tpAuth, super.schedule);
  int refreshCalls = 0;
  int examCalls = 0;
  Completer<void>? examGate;
  @override
  Future<void> fetchAssignments() async {
    refreshCalls++;
    notifyListeners();
  }

  @override
  Future<void> fetchPlatform(String platformId) async {
    examCalls++;
    await examGate?.future;
    notifyListeners();
  }
}

class _Egate extends EgateAppService {
  _Egate(super.auth, super.storage, super.tpAuth);
  bool fail = true;
  int calls = 0;
  @override
  Future<String> fetchSignMessage() async {
    calls++;
    if (fail) throw StateError('test offline');
    return 'Ready';
  }

  @override
  Future<List<EgateAppSignRecord>> fetchSignHistory() async => [];
}
