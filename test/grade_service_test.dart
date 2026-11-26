import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/grade_record.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/grades_page.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus/campus_clients.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/eams_client.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/grade_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

import 'campus/campus_fixture.dart';
import 'support/fake_ids_client.dart';

String table(List<List<String>> records) => '<table><tr>'
    '<th>学分</th><th>最终</th><th>课程 名称</th><th>绩点</th><th>学年学期</th><th>学期</th><th>考试性质</th></tr>'
    '${records.map((r) => '<tr>${r.map((v) => '<td>$v</td>').join()}</tr>').join()}</table>';
final transcript = table([
  ['2', 'A', 'Alpha', '4', '2025–26', '1', ''],
  ['1', 'B+', 'Beta', '3.3', '2025–26', '2', '重修'],
  ['1', '92', 'Gamma', '4', '2025–26', '2', ''],
  ['2', 'P', 'Pass/fail', '0', '2025–26', '2', ''],
  ['1', 'NP', 'Failed pass/fail', '0', '2025–26', '2', ''],
  ['1', 'W', 'Withdrawn', '0', '2025–26', '2', ''],
  ['1', 'I', 'Incomplete', '0', '2025–26', '2', ''],
  ['1', 'F', 'Failed', '0', '2025–26', '2', ''],
  ['0', 'A-', 'Seminar', '3.7', '2025–26', '2', ''],
]);
const englishHtml =
    '<table><tr><th>成绩</th><th>考试名称</th><th>是否通过</th></tr><tr><td>560</td><td>英语测试</td><td>是</td></tr></table>';

class _Auth extends AuthService {
  _Auth(super.storage, super.http, super.uniAuth);
  UserSession? current = UserSession(
    userId: 'u',
    userName: 'Demo',
    schoolName: 'School',
    createdAt: DateTime.utc(2026),
  );
  @override
  UserSession? get session => current;
  void signOutForTest() {
    current = null;
    notifyListeners();
  }
}

Future<
    ({
      GradeService grades,
      _Auth auth,
      ThirdPartyAuthService bindings,
      StorageService storage,
      CampusFixture fixture
    })> setup(Reply reply) async {
  final f = CampusFixture('https://eams.shanghaitech.edu.cn', reply)
    ..identity = (user: 'u', ids: '20240000');
  final http = LoggingHttpClient(DebugLogger());
  final storage = StorageService(await SharedPreferences.getInstance());
  final auth = _Auth(storage, http, UniAuthService());
  final bindings = ThirdPartyAuthService(storage, http);
  bindings.idsNode.setAccount(
    ThirdPartyAccount(
      platform: ThirdPartyPlatform.ids,
      account: '20240000',
      token: '',
      raw: const {'authMethod': 'passkey', 'tgc': 't', 'uid': '20240000'},
      boundAt: DateTime.utc(2026),
    ),
  );
  final service = GradeService(
    EamsClient(f.session, minInterval: Duration.zero, retryDelay: Duration.zero),
    storage,
    auth,
    bindings,
  );
  addTearDown(service.dispose);
  return (grades: service, auth: auth, bindings: bindings, storage: storage, fixture: f);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reads reordered columns, grade states, separate terms and credit-weighted results', () {
    final courses = parseCourseGrades(transcript);
    final summary = GradeSummary.of(courses);
    expect(summary.gpa, closeTo(15.3 / 5, 1e-9));
    expect(summary.gradedCredits, 5);
    expect(summary.earnedCredits, 6);
    expect(summary.courseCount, 9);
    expect(courses[1].isRetake, isTrue);
    expect(courses[0].semester, '2025–26 1');
    expect(courses[1].semester, '2025–26 2');
    expect(GradeSummary.of([...courses, courses.first]).gpa, closeTo(23.3 / 7, 1e-9));
    expect(parseCourseGrades(table([])), isEmpty);
    expect(
      () => parseCourseGrades('<h1>Service unavailable</h1>'),
      throwsA(isA<CampusRequestException>()),
    );
    expect(parseEnglishGrades(englishHtml, 'Spring').single.score, '560');

    final inferred = parseCourseGrades(
      '<table><tr><th>课程名称</th><th>学分</th><th>总评成绩</th></tr>'
      '<tr><td>Pass</td><td>2</td><td>75</td></tr>'
      '<tr><td>Fail</td><td>1</td><td>58</td></tr></table>',
    );
    expect(inferred.first.passed, isTrue);
    expect(inferred.last.passed, isFalse);
  });

  test('normal refresh hits historyCourseGrade directly and warms base only on invalid shell',
      () async {
    var warmed = false;
    final ctx = await setup((r) {
      if (r.uri.path.endsWith('person.action')) {
        warmed = true;
        return respond('<html>warm</html>');
      }
      return respond(warmed ? transcript : '<html>shell</html>');
    });
    await ctx.grades.refresh(GradeScope.major);
    expect(ctx.fixture.requests.map((r) => r.uri.path).toList(), [
      '/eams/teach/grade/course/person!historyCourseGrade.action',
      '/eams/teach/grade/course/person.action',
      '/eams/teach/grade/course/person!historyCourseGrade.action',
    ]);
    ctx.fixture.requests.clear();
    await ctx.grades.refresh(GradeScope.minor);
    expect(ctx.fixture.requests.map((r) => r.uri.path).toList(), [
      '/eams/teach/grade/course/person!historyCourseGrade.action',
    ]);
  });

  test('cached results survive a restart and are cleared on IDS change, logout or cache wipe',
      () async {
    final ctx = await setup((r) => respond(transcript));
    await ctx.grades.refresh(GradeScope.major);
    expect(ctx.fixture.requests.last.uri.queryParameters['projectType'], 'MAJOR');
    final reopened = GradeService(ctx.grades.eams, ctx.storage, ctx.auth, ctx.bindings);
    addTearDown(reopened.dispose);
    expect(reopened.courses(GradeScope.major).length, 9);
    final owner = jsonEncode(['u', '20240000']);
    ctx.fixture.identity = (user: 'u', ids: '20240001');
    ctx.bindings.idsNode.setAccount(
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.ids,
        account: '20240001',
        token: '',
        raw: const {'authMethod': 'passkey', 'tgc': 't', 'uid': '20240001'},
        boundAt: DateTime.utc(2026),
      ),
    );
    expect(ctx.storage.loadGradeCache(owner, 'major'), isNull);
    expect(reopened.courses(GradeScope.major), isEmpty);
    await ctx.grades.refresh(GradeScope.minor);
    expect(ctx.storage.loadGradeCache(jsonEncode(['u', '20240001']), 'minor'), isNotNull);
    await ctx.storage.clearCampusCaches();
    expect(ctx.storage.loadGradeCache(jsonEncode(['u', '20240001']), 'minor'), isNull);
    await ctx.grades.refresh(GradeScope.minor);
    ctx.fixture.identity = (user: null, ids: '20240001');
    ctx.auth.signOutForTest();
    expect(ctx.grades.ready, isFalse);
    expect(ctx.storage.loadGradeCache(jsonEncode(['u', '20240001']), 'minor'), isNull);
  });

  test('legacy IDS account without passkey binding keeps GradeService not ready', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    final http = LoggingHttpClient(DebugLogger());
    final storage = StorageService(await SharedPreferences.getInstance());
    final auth = _Auth(storage, http, UniAuthService());
    final bindings = ThirdPartyAuthService(storage, http, idsClient: FakeIdsClient());
    final clients = CampusClients(auth, bindings);
    addTearDown(clients.dispose);
    final service = GradeService(clients.eams, storage, auth, bindings);
    addTearDown(service.dispose);

    bindings.idsNode.setAccount(
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.ids,
        account: '20240000',
        token: '',
        boundAt: DateTime.utc(2026),
      ),
    );
    expect(bindings.hasIdsBinding, isFalse);
    expect(service.ready, isFalse);

    await storage.saveThirdPartyAccount(FakeIdsClient.account('20240000'));
    await bindings.initialize();
    expect(bindings.hasIdsBinding, isTrue);
    expect(service.ready, isTrue);
  });

  test('renews an expired session; a rate limit leaves the last transcript available', () async {
    var limited = false;
    final ctx = await setup((r) {
      if (limited) return respond('请不要过快点击');
      if (r.headers['Cookie'] == 'SESSION=v0') return respond('<input name="execution">');
      return respond(transcript);
    });
    await ctx.grades.refresh(GradeScope.major);
    expect(ctx.fixture.renewals, 1);
    limited = true;
    await expectLater(ctx.grades.refresh(GradeScope.major), fails(CampusErrorKind.rateLimited));
    expect(ctx.grades.courses(GradeScope.major), hasLength(9));
  });

  testWidgets('phone simulation changes predicted GPA, credits and count without writing transcript',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ctx = await setup((r) => respond(transcript));
    await tester.pumpWidget(MaterialApp(home: GradesPage(service: ctx.grades)));
    await tester.pumpAndSettle();
    expect(find.text('3.06'), findsOneWidget);
    expect(find.text('已获 6.0 学分 · 计入 GPA 5.0 学分'), findsOneWidget);
    expect(find.text('9 门课程 · 2 个学期'), findsOneWidget);
    await tester.tap(find.text('本地 GPA 试算'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加假设课程'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.enterText(find.byType(TextField).at(1), '4');
    await tester.pump();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('3.33'), findsOneWidget);
    expect(find.text('已获 8.0 学分 · 计入 GPA 7.0 学分'), findsOneWidget);
    expect(find.text('10 门课程 · 2 个学期'), findsOneWidget);
    expect(ctx.grades.courses(GradeScope.major), hasLength(9));
  });
}
