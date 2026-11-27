import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/egate_app_page.dart';
import 'package:techpie/pages/egate_discovery.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/emap_client.dart';
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
import 'campus/campus_fixture.dart';
import 'support/fake_ids_client.dart';

const origin = 'https://egate.shanghaitech.edu.cn';
Map<String, dynamic> page(String model, List<Map<String, dynamic>> rows, {int? total}) => {
      'code': '0',
      'datas': {
        model: {'totalSize': total ?? rows.length, 'rows': rows},
      },
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StorageService storage;
  late ChangeNotifier accounts;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
    accounts = ChangeNotifier();
  });
  EgateAppService service(CampusFixture f) =>
      EgateAppService.withClient(EmapClient(f.session), storage, accounts, () => 'fixture-student');
  test('reads and caches scoped activity, attendance and summary fields', () async {
    final fixture = CampusFixture(origin, (r) {
      final path = r.uri.pathSegments.last;
      if (path == 'dqnxxqgrhz.do') {
        expect(r.method, 'GET');
        return respond({
          'data': [
            {'BT': '公告'},
          ],
        });
      }
      if (path == 'cxhdsqxx.do') {
        expect((r.data as Map)['XSBH'], 'fixture-student');
        return respond(
          page('cxhdsqxx', [
            {
              'WID': 'w',
              'HDBH': 'a',
              'HDMC': '活动',
              'RCQD': '入场',
              'LCQD': '离场',
              'PRIVATE': 'hidden',
            },
          ]),
        );
      }
      if (path == 'cxjqjxhd.do' || path == 'hdllxxcx.do') {
        return respond(
          page(
            path.split('.').first,
            [
              {'WID': 'a', 'HDMC': '活动', 'HDDD': '会堂', 'BMZT_DISPLAY': '已报名', 'PRIVATE': 'hidden'},
            ],
            total: 22,
          ),
        );
      }
      return respond({});
    });
    final s = service(fixture);
    expect(await s.fetchSignMessage(), '公告');
    expect((await s.fetchRecentActivities()).single.registered, isTrue);
    expect((await s.fetchAllActivities(1)).hasNext, isTrue);
    final history = (await s.fetchSignHistory()).single;
    expect([history.activityName, history.entrance, history.exit], ['活动', '入场', '离场']);
    final key = s.revision;
    s.dispose();
    final restored = service(fixture);
    expect(restored.history.single.fields['HDBH'], 'a');
    expect(restored.all.single.id, 'a');
    expect(storage.readEmapCache('student_activities'), isNot(contains('hidden')));
    fixture.identity = (user: 'new-user', ids: 'new-binding');
    // Check the same hook the list calls when it gets an account change.
    expect(() => restored.check(key), throwsA(isA<CampusRequestException>()));
    expect(restored.history, isEmpty);
    expect(storage.readEmapCache('student_activities'), isNull);
    restored.dispose();
  });
  test('posts enrollment and shows both positive and negative business replies verbatim', () async {
    var msg = '报名成功';
    final fixture = CampusFixture(origin, (r) {
      if (r.uri.path.contains('getAppConfig')) return respond({});
      expect(r.uri.path, '/xsfw/sys/xshdapp/MobileXshdController/xshdbm.do');
      expect(r.data, {'HDBH': 'a', 'FKPZ': ''});
      return respond({
        'datas': {'MSG': msg},
      });
    });
    final s = service(fixture);
    final activity = EgateActivity({'WID': 'w1', 'HDBH': 'a', 'BMZT_DISPLAY': '可报名'});
    expect(activity.id, 'a');
    expect(EgateActivity({'WID': 'w2', 'BMZT_DISPLAY': '报名中'}).canRegister, isTrue);
    expect(EgateActivity({'WID': 'w3', 'BMZT_DISPLAY': '立即报名'}).canRegister, isTrue);
    expect(await s.registerActivity(activity), '报名成功');
    final sent = fixture.requests.length;
    await expectLater(
      s.registerActivity(EgateActivity({'WID': 'a', 'BMZT': 1})),
      fails(CampusErrorKind.rejected),
    );
    expect(fixture.requests, hasLength(sent));
    msg = '名额已满';
    expect(await s.registerActivity(activity), '名额已满');
    msg = '';
    await expectLater(s.registerActivity(activity), fails(CampusErrorKind.parseFailed));
    s.dispose();
  });

  test('fetchSignHistory rejects non-zero code and tolerates omitted totalSize', () async {
    var code = '1';
    final fixture = CampusFixture(origin, (r) {
      if (r.uri.path.contains('getAppConfig')) return respond({});
      return respond({
        'code': code,
        'datas': {
          'cxhdsqxx': {
            'rows': [
              {'WID': 'w', 'HDBH': 'a', 'HDMC': '讲座'},
            ],
          },
        },
      });
    });
    final s = service(fixture);
    await expectLater(s.fetchSignHistory(), fails(CampusErrorKind.rejected));
    code = '0';
    final rows = await s.fetchSignHistory();
    expect(rows.single.activityName, '讲座');
    s.dispose();
  });

  testWidgets('discovery confirms enrollment, searches case-insensitively and caps scan pages',
      (tester) async {
    final fixture = _DiscoveryFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EgateDiscovery(service: fixture, onChanged: () async {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('读书会'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('报名'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(fixture.registrations, 0);
    await tester.tap(find.text('报名'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('报名')));
    await tester.pumpAndSettle();
    expect(fixture.registrations, 1);

    // Case-insensitive recent filter.
    await tester.enterText(find.byType(TextField), 'talk');
    await tester.pump();
    expect(find.text('AI Talk'), findsOneWidget);
    expect(find.text('读书会'), findsNothing);

    await tester.tap(find.text('全部活动'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ai talk');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('AI Talk 专场'), findsOneWidget);
    expect(find.text('前往网页版'), findsOneWidget);
    expect(find.text('合唱团'), findsNothing);

    // Nonexistent search keyword stops after at most 10 pages instead of looping forever.
    fixture.requestedPages.clear();
    fixture.infinitePages = true;
    await tester.enterText(find.byType(TextField), '不存在的关键字');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(fixture.requestedPages, hasLength(10));
    expect(find.text('已连续翻页搜索，暂未找到匹配活动'), findsOneWidget);
  });

  testWidgets('EgateAppPage preserves discovery search state across tab switches',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    await storage.saveSession(
      UserSession(
        userId: 'u1',
        userName: 'User',
        schoolName: 'ShanghaiTech',
        createdAt: DateTime(2026),
      ),
    );
    await storage.saveThirdPartyAccount(FakeIdsClient.account('student-1'));
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    await auth.loadSession();
    final tpAuth = ThirdPartyAuthService(storage, http, idsClient: FakeIdsClient());
    await tpAuth.initialize();
    final schedule = ScheduleService(storage, http, auth, tpAuth);
    final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
    final egate = _PageFixture();
    final oa = OaGymService(auth, storage, tpAuth);
    final card = CampusCardService(storage: storage);
    final sync = SyncService(auth, tpAuth, storage, ecard: card);
    final theme = ThemeService(storage);
    final bind = EcardBindService();
    final allowance = StudentAllowanceService(auth, tpAuth);
    final update = UpdateService();
    addTearDown(() {
      egate.dispose();
      schedule.dispose();
      assignments.dispose();
      oa.dispose();
      card.dispose();
      allowance.dispose();
    });

    await tester.pumpWidget(
      ServiceProvider(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: theme,
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: oa,
        egateAppService: egate,
        studentAllowanceService: allowance,
        uniAuthService: uniAuth,
        syncService: sync,
        updateService: update,
        campusCardService: card,
        ecardBindService: bind,
        child: const MaterialApp(home: EgateAppPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(egate.recentCalls, 1);
    await tester.enterText(find.byType(TextField), 'talk');
    await tester.pump();
    expect(find.text('AI Talk'), findsOneWidget);
    expect(find.text('读书会'), findsNothing);

    await tester.tap(find.text('我的活动'));
    await tester.pumpAndSettle();
    expect(find.text('暂无签到记录'), findsOneWidget);
    expect(find.text('AI Talk'), findsNothing);

    await tester.tap(find.text('发现活动'));
    await tester.pumpAndSettle();
    expect(find.text('AI Talk'), findsOneWidget);
    expect(find.text('读书会'), findsNothing);
    expect(egate.recentCalls, 1);
  });

  for (final html in [true, false]) {
    test('renews ${html ? 'HTML' : '401'} during bootstrap before posting a scanned WID', () async {
      var bootstraps = 0, writes = 0;
      final fixture = CampusFixture(origin, (r) {
        if (r.uri.path.contains('getAppConfig')) {
          if (bootstraps++ == 0) {
            return html ? respond('<!DOCTYPE html><html>登录</html>') : respond({}, status: 401);
          }
          return respond({});
        }
        writes++;
        expect(r.uri.path, '/xsfw/sys/xshdapp/MobileXshdController/xsqd.do');
        expect(r.data, {'WID': 'fixture-code'});
        return respond('签到码已过期');
      });
      final s = service(fixture);
      expect(await s.submitCheckin(' fixture-code '), '签到码已过期');
      expect(writes, 1);
      expect(fixture.renewals, 1);
      s.dispose();
    });
  }
  for (final enroll in [true, false]) {
    for (final status in [200, 401, 403, 307, 308]) {
      test(
          '${enroll ? 'enrollment' : 'check-in'} sends one POST when confirmation ends with $status',
          () async {
        var writes = 0;
        final fixture = CampusFixture(origin, (r) {
          if (r.uri.path.contains('getAppConfig')) return respond({});
          writes++;
          expect(r.method, 'POST');
          return respond(
            status == 200 ? '<html>登录</html>' : '',
            status: status,
            headers: {
              if (status == 307 || status == 308) 'location': ['/xsfw/sys/xshdapp/redirected.do'],
            },
          );
        });
        final s = service(fixture);
        final result = enroll
            ? s.registerActivity(EgateActivity({'WID': 'a', 'BMZT_DISPLAY': '可报名'}))
            : s.submitCheckin('fixture-code');
        await expectLater(result, throwsA(isA<CampusRequestException>()));
        expect(writes, 1);
        s.dispose();
      });
    }
  }
}

class _PageFixture extends _DiscoveryFixture {
  @override
  List<EgateAppSignRecord> get history => const [];
  @override
  Future<String> fetchSignMessage() async => '当前公告';
  @override
  Future<List<EgateAppSignRecord>> fetchSignHistory() async => const [];
}

class _DiscoveryFixture extends ChangeNotifier implements EgateAppService {
  int registrations = 0;
  int recentCalls = 0;
  bool infinitePages = false;
  final List<int> requestedPages = [];
  @override
  int get revision => 1;
  @override
  void check(int expected) => expect(expected, revision);
  @override
  List<EgateActivity> get recent => [
        EgateActivity({'WID': 'fixture-id', 'HDMC': '读书会', 'HDDD': '图书馆', 'BMZT_DISPLAY': '可报名'}),
        EgateActivity({'WID': 'talk-id', 'HDMC': 'AI Talk', 'HDDD': '报告厅'}),
      ];
  @override
  Future<List<EgateActivity>> fetchRecentActivities() async {
    recentCalls++;
    return recent;
  }

  @override
  List<EgateActivity> get all => [];
  @override
  Future<({List<EgateActivity> rows, bool hasNext})> fetchAllActivities(int page) async {
    requestedPages.add(page);
    if (infinitePages) {
      return (
        rows: [EgateActivity({'WID': 'inf-$page', 'HDMC': '普通讲座 $page'})],
        hasNext: true,
      );
    }
    return (
      rows: [
        EgateActivity({'WID': 'p$page', 'HDMC': page == 1 ? '合唱团' : 'AI Talk 专场'}),
      ],
      hasNext: page < 2
    );
  }

  @override
  Future<String> registerActivity(EgateActivity activity) async {
    expect(activity.id, 'fixture-id');
    registrations++;
    return '已收到申请';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
