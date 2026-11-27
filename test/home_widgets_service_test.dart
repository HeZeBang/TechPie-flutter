import 'dart:async';
import 'dart:convert';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/models/card_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/auth_port.dart';
import 'package:techpie/features/campus_card/domain/ports/card_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/credential_store.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course.dart';
import 'package:techpie/models/course_table.dart';
import 'package:techpie/models/custom_course.dart';
import 'package:techpie/pages/schedule_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/home_widgets_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/app_shell/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Friday 2026-11-27 09:00 local time.
  final localNow = DateTime(2026, 11, 27, 9, 0);
  const channel = MethodChannel('test/home_widgets');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late StorageService storage;
  late LoggingHttpClient http;
  late AuthService auth;
  late ThirdPartyAuthService thirdParty;
  late ScheduleService schedule;
  late AssignmentService assignments;
  late AppRuntime runtime;
  late _StubCardRepository cardRepo;
  late CampusCardService campusCard;
  late HomeWidgetsService service;
  late List<MethodCall> calls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    http = LoggingHttpClient(DebugLogger());
    auth = AuthService(storage, http, UniAuthService());
    thirdParty = ThirdPartyAuthService(storage, http);

    // Seed an active undergraduate semester with EAMS course, custom session,
    // and exam entry across the 7-day window starting 2026-11-27.
    const semesterId = 'sem-2026-fall';
    await storage.saveSemesters(
      const SemesterInfo(
        semesters: {
          '2026-2027': {'秋': semesterId},
        },
        defaultSemester: semesterId,
        tableId: 'undergrad',
      ),
    );
    await storage.setSelectedSemester(semesterId);
    await storage.saveTermCalendar(
      semesterId,
      TermCalendar(
        code: 200,
        schoolYearTerm: '2026-2027 秋',
        termBegin: DateTime(2026, 9, 7),
        snapshotDate: localNow,
        snapshotWeekOfTerm: 12,
        allTeachWeeks: 16,
        allTermWeeks: 18,
        amClasses: 4,
        pmClasses: 4,
        eveClasses: 4,
      ),
    );
    await storage.saveCourseTable(
      semesterId,
      const CourseTable(
        periods: [
          CoursePeriod(index: 1, timeRange: '08:15-09:00'),
          CoursePeriod(index: 2, timeRange: '09:10-09:55'),
        ],
        courses: [
          EamsCourse(
            name: 'Algorithms(CS101.01)',
            classroom: 'SIST 1A-204',
            teachers: 'Prof. Ada',
            // Week 12 active.
            weeks: '011111111111111110',
            times: {
              DateTime.friday: [1, 2],
            },
          ),
        ],
      ),
    );
    await storage.saveCustomCourses(semesterId, [
      CustomCourse(
        id: 'custom-1',
        semesterId: semesterId,
        name: 'Lab Discussion',
        location: 'SIST 1B-102',
        date: DateTime(2026, 11, 28),
        time: const ClockCourseTime(startTime: '14:00', endTime: '15:30'),
        color: CourseColor.green,
      ),
    ]);
    await storage.saveCachedAssignments([
      ExamAssignment(
        id: 'exam-1',
        title: 'Algorithms Midterm',
        course: 'Algorithms',
        due: DateTime(2026, 11, 29, 10, 0),
        lateDue: DateTime(2026, 11, 29, 12, 0),
        semesterId: semesterId,
        location: 'H2-201',
        batchName: '期中考试',
      ).toJson(),
    ]);

    schedule = ScheduleService(storage, http, auth, thirdParty);
    await schedule.loadCachedData();
    assignments = AssignmentService(storage, http, auth, thirdParty, schedule)
      ..loadCached();

    final baseRuntime = await buildDemoRuntime();
    final secureStore = InMemorySecureCredentialStore();
    final sessionStore = SecureSessionCredentialStore(secureStore);
    final stubAuth = _StaticAuthPort(sessionStore);
    cardRepo = _StubCardRepository();
    runtime = AppRuntime(
      environment: baseRuntime.environment,
      capabilities: baseRuntime.capabilities,
      auth: stubAuth,
      cards: cardRepo,
      paymentCodes: baseRuntime.paymentCodes,
      scanPayments: baseRuntime.scanPayments,
      transactions: baseRuntime.transactions,
      securitySettings: baseRuntime.securitySettings,
      offlinePayments: baseRuntime.offlinePayments,
      brightness: baseRuntime.brightness,
      connectivity: baseRuntime.connectivity,
      lifecycle: baseRuntime.lifecycle,
      feedback: baseRuntime.feedback,
      scanner: baseRuntime.scanner,
      disposeRuntime: () async {
        await cardRepo.dispose();
        await stubAuth.dispose();
        await baseRuntime.dispose();
      },
    );
    campusCard = CampusCardService.withStore(
      secureStore,
      runtimeFactory: () => runtime,
    );

    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    service = HomeWidgetsService(
      storage,
      schedule,
      assignments,
      campusCard,
      channel: channel,
      now: () => localNow,
      enabled: true,
    );

    addTearDown(() async {
      appShellPendingSchedule.value = false;
      service.dispose();
      campusCard.dispose();
      await runtime.dispose();
      assignments.dispose();
      schedule.dispose();
      thirdParty.dispose();
      auth.dispose();
      http.close();
      messenger.setMockMethodCallHandler(channel, null);
    });
  });

  test(
    'publishes 7-day schedule snapshot with OKLCH colors, deduplicates, and clears on logout',
    () async {
      service.initialize();
      await service.flush();

      final scheduleCalls = calls
          .where((c) => c.method == 'publishSchedule')
          .toList();
      expect(scheduleCalls, hasLength(1));

      final payload =
          jsonDecode(scheduleCalls.single.arguments as String)
              as Map<String, dynamic>;
      expect(payload['schemaVersion'], 1);
      expect(payload['weekNumber'], 12);

      final days = payload['days'] as List<dynamic>;
      expect(days, hasLength(7));
      expect((days.first as Map)['date'], '2026-11-27');
      expect((days.last as Map)['date'], '2026-12-03');

      final fridayCourses = (days[0] as Map)['courses'] as List<dynamic>;
      expect(fridayCourses, hasLength(1));
      final alg = fridayCourses.single as Map<String, dynamic>;
      expect(alg['title'], 'Algorithms(CS101.01)');
      expect(alg['location'], 'SIST 1A-204');
      expect(alg['isExam'], isFalse);
      expect(alg['periodLabel'], '1-2');
      expect(
        RegExp(r'^#[0-9A-F]{6}$').hasMatch(alg['colorLightHex'] as String),
        isTrue,
      );
      expect(
        RegExp(r'^#[0-9A-F]{6}$').hasMatch(alg['colorDarkHex'] as String),
        isTrue,
      );
      expect((alg['startAt'] as String).endsWith('Z'), isTrue);

      final saturdayCourses = (days[1] as Map)['courses'] as List<dynamic>;
      expect(saturdayCourses, hasLength(1));
      expect((saturdayCourses.single as Map)['title'], 'Lab Discussion');

      final sundayCourses = (days[2] as Map)['courses'] as List<dynamic>;
      expect(sundayCourses, hasLength(1));
      expect((sundayCourses.single as Map)['isExam'], isTrue);
      expect((sundayCourses.single as Map)['location'], 'H2-201');

      // Resuming with unchanged data deduplicates the native write.
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await service.flush();
      expect(
        calls.where((c) => c.method == 'publishSchedule'),
        hasLength(1),
      );

      // Logout clears cached schedule snapshot once.
      await service.clearSchedule();
      await service.clearSchedule();
      expect(
        calls.where((c) => c.method == 'clearSchedule'),
        hasLength(1),
      );
    },
  );

  test(
    'publishes ecard snapshot reactively with balance mask and zero secrets',
    () async {
      service.initialize();
      await service.flush();

      final initial =
          jsonDecode(
                calls
                        .lastWhere((c) => c.method == 'publishEcard')
                        .arguments
                    as String,
              )
              as Map<String, dynamic>;
      expect(initial['configured'], isFalse);
      expect(initial['balanceText'], isNull);
      expect(initial['hideBalance'], isFalse);

      await campusCard.connect('SYNTHETIC_OPENID_SECRET_TOKEN_0123456789');
      cardRepo.emit(
        const CampusCard(
          id: 'SECRET_CARD_999',
          maskedNumber: '••••0001',
          ownerName: 'SECRET_OWNER',
          balance: MoneyFen(8620),
          status: CampusCardStatus.normal,
          positionName: 'Student',
          offlineCodeAllowed: true,
        ),
      );
      await service.flush();

      final linked =
          jsonDecode(
                calls
                        .lastWhere((c) => c.method == 'publishEcard')
                        .arguments
                    as String,
              )
              as Map<String, dynamic>;
      expect(linked['configured'], isTrue);
      expect(linked['balanceText'], '¥ 86.20');
      expect(linked['hideBalance'], isFalse);
      expect(linked.keys.toSet(), {
        'schemaVersion',
        'generatedAt',
        'configured',
        'balanceText',
        'hideBalance',
      });
      final rawJson = jsonEncode(linked);
      expect(rawJson, isNot(contains('SYNTHETIC_OPENID_SECRET_TOKEN')));
      expect(rawJson, isNot(contains('SECRET_CARD_999')));
      expect(rawJson, isNot(contains('SECRET_OWNER')));

      // Toggling hide balance in StorageService pushes an immediate update.
      await storage.setHideCampusCardBalance(true);
      await service.flush();
      final masked =
          jsonDecode(
                calls
                        .lastWhere((c) => c.method == 'publishEcard')
                        .arguments
                    as String,
              )
              as Map<String, dynamic>;
      expect(masked['hideBalance'], isTrue);
    },
  );

  testWidgets('cold and warm schedule widget routes invoke handler and ack', (
    tester,
  ) async {
    const routeChannel = MethodChannel('test/home_widgets_routes');
    final recorded = <String>[];
    messenger.setMockMethodCallHandler(routeChannel, (call) async {
      recorded.add(call.method);
      if (call.method == 'consumePendingRoute') return 'schedule';
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(routeChannel, null));

    final routeService = HomeWidgetsService(
      storage,
      schedule,
      assignments,
      campusCard,
      channel: routeChannel,
      now: () => localNow,
      enabled: true,
    );
    addTearDown(routeService.dispose);

    var opened = 0;
    routeService.initialize();
    await tester.pump();
    routeService.setOpenScheduleHandler(() async => opened++);
    await tester.pump();

    expect(opened, 1);
    expect(
      recorded,
      containsAllInOrder(['consumePendingRoute', 'acknowledgePendingRoute']),
    );

    await messenger.handlePlatformMessage(
      routeChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('openSchedule'),
      ),
      (_) {},
    );
    await tester.pump();
    expect(opened, 2);
  });

  testWidgets(
    'appShellPendingSchedule switches AppShell directly to Schedule tab',
    (tester) async {
      const feedbackChannel = MethodChannel('techpie/feedback');
      messenger.setMockMethodCallHandler(feedbackChannel, (_) async => null);
      addTearDown(
        () => messenger.setMockMethodCallHandler(feedbackChannel, null),
      );

      final theme = ThemeService(storage);
      addTearDown(theme.dispose);
      final appCampusCard = CampusCardService();

      await tester.pumpWidget(
        TechPieApp(
          authService: auth,
          debugLogger: DebugLogger(),
          storageService: storage,
          themeService: theme,
          scheduleService: schedule,
          assignmentService: assignments,
          thirdPartyAuthService: thirdParty,
          oaGymService: OaGymService(auth, storage, thirdParty),
          egateAppService: EgateAppService(auth, storage, thirdParty),
          uniAuthService: UniAuthService(),
          syncService: SyncService(auth, thirdParty, storage),
          updateService: UpdateService(),
          ecardBindService: EcardBindService(),
          campusCardService: appCampusCard,
          homeWidgetsService: service,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<CNTabBar>(find.byType(CNTabBar)).currentIndex, 0);

      appShellPendingSchedule.value = true;
      await tester.pumpAndSettle();

      expect(tester.widget<CNTabBar>(find.byType(CNTabBar)).currentIndex, 1);
      expect(find.byType(SchedulePage), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

final class _StubCardRepository implements CardRepository, CardSnapshotSource {
  final _snapshots = StreamController<CampusCard?>.broadcast(sync: true);
  CampusCard? _latest;

  void emit(CampusCard? card) {
    _latest = card;
    _snapshots.add(card);
  }

  @override
  Stream<CampusCard?> get snapshots => _snapshots.stream;

  @override
  Future<CampusCard?> currentCard() async => _latest;

  @override
  Future<BindCardResult> bind(BindCardCommand command) async =>
      const BindCardResult(offlineCodeAllowed: true);

  @override
  Future<void> unbind({required String cardPassword}) async {}

  Future<void> dispose() => _snapshots.close();
}

final class _StaticAuthPort implements AuthPort, OpenIdAuthVerifier {
  _StaticAuthPort(this._sessionStore);

  final SessionCredentialStore _sessionStore;
  final _changes = StreamController<AuthSnapshot>.broadcast(sync: true);

  @override
  Stream<AuthSnapshot> get changes => _changes.stream;

  @override
  Future<AuthSnapshot> restoreLocal() => restore();

  @override
  Future<AuthSnapshot> restore() async {
    final openId = await _sessionStore.readOpenId();
    return openId == null
        ? const AuthSnapshot(state: AuthState.signedOut)
        : const AuthSnapshot(
            state: AuthState.authenticated,
            session: AuthSession(
              subjectId: 'synthetic',
              orgId: '2',
              maskedIdentity: 'SYNT****CDEF',
            ),
          );
  }

  @override
  Future<void> verifyOpenId(
    String openId, {
    EcardOpenIdChannel channel = EcardOpenIdChannel.wechat,
  }) async {}

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async {
    final cred = credential as OpenIdAuthCredential;
    await _sessionStore.writeSession(
      sessionCookie: 'JSESSIONID=synthetic',
      openId: cred.openId,
      orgId: '2',
      verifiedIdSerial: 'SYNTHETIC-STUDENT',
      verifiedCardId: 'SECRET_SID_888',
      channel: cred.channel,
    );
    const snap = AuthSnapshot(
      state: AuthState.authenticated,
      session: AuthSession(
        subjectId: 'synthetic',
        orgId: '2',
        maskedIdentity: 'SYNT****CDEF',
      ),
    );
    _changes.add(snap);
    return snap;
  }

  @override
  Future<void> signOut() async {
    await _sessionStore.clear();
    const snap = AuthSnapshot(state: AuthState.signedOut);
    _changes.add(snap);
  }

  Future<void> dispose() => _changes.close();
}
