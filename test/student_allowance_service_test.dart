import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/ids_passkey.dart';
import 'package:techpie/models/student_allowance.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/home_page.dart';
import 'package:techpie/pages/student_allowance_page.dart';
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
import 'package:techpie/services/student_allowance_client.dart';
import 'package:techpie/services/student_allowance_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';

import 'support/fake_ids_client.dart';
import 'support/student_allowance_finance_fixture.dart';

typedef Finance = StudentAllowanceFinanceFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final period = StudentAllowancePeriod(DateTime(2026, 1), DateTime(2026, 2));
  Matcher failsWith(StudentAllowanceFailure reason) => throwsA(
        isA<StudentAllowanceException>().having((e) => e.failure, 'failure', reason),
      );

  test('requires both primary login and an IDS binding without contacting finance', () async {
    final fixture = await _Fixture.create(loggedIn: false, bound: false);
    expect(fixture.service.access, StudentAllowanceAccess.signIn);
    await expectLater(fixture.service.query(period), failsWith(StudentAllowanceFailure.signIn));
    await fixture.signIn();
    expect(fixture.service.access, StudentAllowanceAccess.bindIds);
    await expectLater(fixture.service.query(period), failsWith(StudentAllowanceFailure.bindIds));
    expect(fixture.finance.requests, isEmpty);
  });

  test('an IDS rejection renews through the existing Passkey binding once', () async {
    final fixture = await _Fixture.create();
    final revision = fixture.service.accountRevision;
    fixture.finance.intercept = (request) =>
        request.uri.host == Finance.idsHost && request.headers['Cookie'] == 'CASTGC=tgc-value'
            ? Finance.response(request, status: 401)
            : null;
    final report = await fixture.service.query(period);
    expect(report.months, hasLength(2));
    expect(fixture.ids.logins, 1);
    expect(fixture.service.accountRevision, revision);
    expect(
      fixture.finance.requests
          .where((r) => r.uri.host == Finance.idsHost)
          .map((r) => r.headers['Cookie']),
      ['CASTGC=tgc-value', 'CASTGC=synthetic-renewal-1'],
    );
    expect(fixture.logger.entries, isEmpty);
  });

  test('limits retries when IDS keeps returning the login page', () async {
    final fixture = await _Fixture.create();
    fixture.finance.intercept = (request) => request.uri.host == Finance.idsHost
        ? Finance.response(request, body: '<form><input name="execution"></form>')
        : null;
    await expectLater(fixture.service.query(period), failsWith(StudentAllowanceFailure.idsSession));
    expect(fixture.ids.logins, 1);
    expect(fixture.finance.requests.where((r) => r.uri.host == Finance.idsHost), hasLength(2));
  });

  test('a finance refusal does not trigger an IDS renewal', () async {
    final fixture = await _Fixture.create();
    fixture.finance.intercept = (request) =>
        request.uri.path == Finance.queryPath ? Finance.response(request, status: 403) : null;
    await expectLater(
      fixture.service.query(period),
      failsWith(StudentAllowanceFailure.financeSession),
    );
    expect(fixture.ids.logins, 0);
    expect(fixture.finance.requests.where((r) => r.uri.path == Finance.queryPath), hasLength(1));
  });

  test('discards an in-flight result across logout and login to the same account', () async {
    final fixture = await _Fixture.create();
    final started = Completer<void>();
    final release = Completer<void>();
    fixture.finance.intercept = (request) async {
      if (request.uri.path == Finance.queryPath) {
        started.complete();
        await release.future;
      }
      return null;
    };
    final checked = expectLater(
      fixture.service.query(period),
      failsWith(StudentAllowanceFailure.accessChanged),
    );
    await started.future;
    await fixture.auth.logout();
    await fixture.signIn();
    release.complete();
    await checked;
    expect(fixture.ids.logins, 0);
  });

  testWidgets('opens from narrow Home, queries on demand, and clears results on IDS replacement',
      (tester) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = await _Fixture.create();
    await tester.pumpWidget(fixture.app(const HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('学生津贴'));
    await tester.pumpAndSettle();
    expect(find.byType(StudentAllowancePage), findsOneWidget);
    expect(fixture.finance.requests, isEmpty);
    expect(find.textContaining('开始：'), findsOneWidget);
    expect(find.textContaining('结束：'), findsOneWidget);

    await tester.tap(find.text('查询津贴'));
    await tester.pumpAndSettle();
    expect(find.text('查询区间合计'), findsOneWidget);
    expect(find.text('实发 ¥1,429.25'), findsOneWidget);
    expect(find.text('2026年2月'), findsOneWidget);
    await tester.tap(find.text('2026年2月'));
    await tester.pumpAndSettle();
    expect(find.text('合成助研津贴'), findsOneWidget);
    expect(find.textContaining('SYNTHETIC-STUDENT'), findsNothing);

    await fixture.thirdParty.applyIdsSyncBinding(
      IdsSyncBinding(
        credential: FakeIdsClient.key('other-fixture-campus-account'),
        updatedAt: DateTime.utc(2026, 3),
        deviceId: 'fixture',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('查询区间合计'), findsNothing);
    expect(find.text('实发 ¥1,429.25'), findsNothing);
    expect(find.text('查询津贴'), findsOneWidget);
    expect(fixture.finance.requests.where((r) => r.uri.path == Finance.queryPath), hasLength(1));
  });

  testWidgets('keeps failures separate from no records and supports retry', (tester) async {
    final fixture = await _Fixture.create();
    await tester.pumpWidget(fixture.app(const StudentAllowancePage()));
    fixture.finance.html = '<div>UNKNOWN-SYNTHETIC-RESPONSE</div>';
    await tester.tap(find.text('查询津贴'));
    await tester.pumpAndSettle();
    expect(find.text('无法识别学校财务返回的数据，请稍后重试'), findsOneWidget);
    expect(find.textContaining('UNKNOWN-SYNTHETIC'), findsNothing);
    expect(find.text('所选月份没有津贴发放记录'), findsNothing);

    fixture.finance.html = '<div>暂无数据</div>';
    await tester.tap(find.text('查询津贴'));
    await tester.pumpAndSettle();
    expect(find.text('所选月份没有津贴发放记录'), findsOneWidget);
  });

  testWidgets('the month picker keeps the submitted range valid', (tester) async {
    final fixture = await _Fixture.create();
    fixture.finance.html = '<div>暂无数据</div>';
    await tester.pumpWidget(fixture.app(const StudentAllowancePage()));
    await tester.tap(find.textContaining('结束：'));
    await tester.pumpAndSettle();
    expect(find.text('结束月份'), findsOneWidget);
    final picker = tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    picker.onDateTimeChanged(DateTime(2001, 5));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('开始：2001年5月'), findsOneWidget);
    expect(find.text('结束：2001年5月'), findsOneWidget);

    await tester.tap(find.text('查询津贴'));
    await tester.pumpAndSettle();
    expect(Uri.splitQueryString(fixture.finance.requests.last.data as String), {
      'SearchYearMonthB': '2001-05',
      'SearchYearMonthE': '2001-05',
      'ConfigID': '22',
    });
  });
}

class _CountingIds extends FakeIdsClient {
  int logins = 0;

  @override
  Future<IdsSession> login(IdsPasskey secret, {bool backedUp = false}) async =>
      IdsSession(secret.username, {'tgc': 'synthetic-renewal-${++logins}'});
}

class _OfflineSchedule extends ScheduleService {
  _OfflineSchedule(super.storage, super.http, super.auth, super.tpAuth);

  // This fixture exercises allowance only, including on a campus rebind.
  @override
  void requestFetch({bool force = false}) {}
}

class _Fixture {
  _Fixture(
    this.storage,
    this.auth,
    this.thirdParty,
    this.logger,
    this.api,
    this.uniAuth,
    this.ids,
    this.finance,
    this.service,
  );

  final StorageService storage;
  final AuthService auth;
  final ThirdPartyAuthService thirdParty;
  final DebugLogger logger;
  final LoggingHttpClient api;
  final UniAuthService uniAuth;
  final _CountingIds ids;
  final Finance finance;
  final StudentAllowanceService service;

  static Future<_Fixture> create({bool loggedIn = true, bool bound = true}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    if (bound) await storage.saveThirdPartyAccount(FakeIdsClient.account('fixture-campus-account'));
    final logger = DebugLogger()..enabled = true;
    final api = LoggingHttpClient(
      logger,
      inner: MockClient((_) async {
        fail('No allowance data or credential should reach the app backend');
      }),
    );
    final ids = _CountingIds();
    final finance = Finance();
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, api, uniAuth);
    final thirdParty = ThirdPartyAuthService(storage, api, idsClient: ids);
    await thirdParty.initialize();
    final service = StudentAllowanceService(
      auth,
      thirdParty,
      client: StudentAllowanceClient(http: finance.dio),
    );
    addTearDown(service.dispose);
    final fixture =
        _Fixture(storage, auth, thirdParty, logger, api, uniAuth, ids, finance, service);
    if (loggedIn) await fixture.signIn();
    return fixture;
  }

  Future<void> signIn() async {
    await storage.saveSession(
      UserSession(
        userId: 'fixture-primary',
        userName: 'Synthetic user',
        schoolName: 'Test school',
        createdAt: DateTime.utc(2026),
      ),
    );
    await auth.loadSession();
  }

  Widget app(Widget page) {
    final schedule = _OfflineSchedule(storage, api, auth, thirdParty);
    final campus = CampusCardService();
    return ServiceProvider(
      authService: auth,
      debugLogger: logger,
      storageService: storage,
      themeService: ThemeService(storage),
      scheduleService: schedule,
      assignmentService: AssignmentService(storage, api, auth, thirdParty, schedule),
      thirdPartyAuthService: thirdParty,
      oaGymService: OaGymService(auth, storage, thirdParty),
      egateAppService: EgateAppService(auth, storage, thirdParty),
      studentAllowanceService: service,
      uniAuthService: uniAuth,
      syncService: SyncService(auth, thirdParty, storage),
      updateService: UpdateService(),
      campusCardService: campus,
      ecardBindService: EcardBindService(),
      child: MaterialApp(home: page),
    );
  }
}
