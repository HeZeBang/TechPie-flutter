import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/elearning_models.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/elearning_course_detail_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus/campus_clients.dart';
import 'package:techpie/services/campus/campus_file_share.dart';
import 'package:techpie/services/campus/elearning_client.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/elearning_service.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('matches course codes and names, leaves ambiguous sections unlinked', () {
    const a = BlackboardCourse('_c', '2026_EE115A_section1', '电路导论', '秋');
    const b = BlackboardCourse('_b', '2026_EE115B', '进阶电路', '秋');
    expect(matchBlackboardCourse('电路课 (EE115A)', [a, b]), a);
    expect(matchBlackboardCourse('电路导论-1班', [a, b]), a);
    expect(matchBlackboardCourse('EE115A', [a, a, b]), isNull);
    expect(matchBlackboardCourse('EE115', [a, b]), isNull);
  });

  test('lists complete courses, caches in memory, downloads bytes and clears campus cache',
      () async {
    var meCalls = 0;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = StorageService(prefs);
    final f = CampusFixture('https://elearning.shanghaitech.edu.cn:8443', (r) {
      final path = r.uri.path;
      Object rows(List<Object> rows) => {'results': rows};
      if (path == '/learn/api/public/v1/users/me') {
        meCalls++;
        return respond({'id': 'me', 'name': 'private name'});
      }
      if (path.endsWith('/users/me/courses')) {
        return respond(
          rows([
            {'courseId': 'c'},
          ]),
        );
      }
      if (path.endsWith('/terms')) {
        return respond(
          rows([
            {'id': 't', 'name': '秋'},
          ]),
        );
      }
      if (path.endsWith('/courses/c')) {
        return respond({'id': 'c', 'name': '电路', 'courseId': 'EE115A', 'termId': 't'});
      }
      if (path.endsWith('/contents')) {
        return respond(
          rows([
            {'id': 'folder', 'title': '课件', 'hasChildren': true},
          ]),
        );
      }
      if (path.endsWith('/children')) {
        return respond(
          rows([
            {'id': 'item', 'title': '课件一', 'body': '<p>内容</p>'},
          ]),
        );
      }
      if (path.endsWith('/attachments')) {
        return respond(
          rows([
            {'id': 'file', 'fileName': '../../notes.pdf'},
          ]),
        );
      }
      if (path.endsWith('/download')) {
        return respond(
          '',
          status: 302,
          headers: {
            'location': ['/bbcswebdav/file'],
          },
        );
      }
      if (path == '/bbcswebdav/file') return respond([1, 2, 3]);
      if (path.endsWith('/columns')) {
        return respond(
          rows([
            {
              'id': 'col',
              'name': '报告',
              'score': {'possible': 100},
            }
          ]),
        );
      }
      if (path.endsWith('/gradebook/users/me')) {
        return respond(
          rows([
            {'columnId': 'col', 'score': 85, 'status': 'Graded', 'private': 'secret grade note'},
          ]),
        );
      }
      if (path.endsWith('/groups')) {
        return respond(
          rows([
            {'id': 'g', 'name': '小组一'},
          ]),
        );
      }
      if (path.endsWith('/announcement')) {
        return respond(
          '<ul id="announcementList"><li><h3>通知</h3><div class="vtbegenerated">周二上课</div></li></ul>',
        );
      }
      fail(path);
    });
    final service = ElearningService(
      ElearningClient(f.session),
      storage: store,
    );
    expect((await service.courses()).single.term, '秋');
    expect(meCalls, 1);
    // In-memory course cache avoids re-querying on second call unless refresh is true.
    expect((await service.courses()).single.id, 'c');
    expect(meCalls, 1);
    await service.courses(refresh: true);
    expect(meCalls, 2);

    final folder = (await service.contents('c')).single;
    expect(folder.folder, isTrue);
    final content = (await service.contents('c', folder.id)).single;
    expect(content.body, '内容');
    final attachment = (await service.attachments('c', content.id)).single;
    expect(CampusFileShare.sanitizeFilename(attachment.name), 'notes.pdf');
    expect(await service.downloadBytes('c', content.id, attachment), [1, 2, 3]);
    final grade = (await service.grades('c')).single;
    expect((grade.score, grade.possible), ('85', '100'));
    expect((await service.groups('c')).single.name, '小组一');
    expect((await service.announcements()).single.text, '周二上课');
    expect((await service.announcements('c')).single.title, '通知');

    final restored = ElearningService(service.client, storage: store);
    expect(restored.cachedCourses.single.id, 'c');
    expect(restored.cachedAnnouncements.single.title, '通知');
    expect(store.blackboardIndex, {
      'owner': matches(r'^[a-f0-9]{64}$'),
      'courses': [
        {'id': 'c', 'courseId': 'EE115A', 'name': '电路', 'term': '秋'},
      ],
      'announcements': [
        {'title': '通知', 'text': '周二上课'},
      ],
    });
    await store.clearCampusCaches();
    expect(store.blackboardIndex, isNull);

    await store.saveBlackboardIndex({'owner': 'x'});
    f.identity = (user: 'other', ids: 'different');
    await service.accountChanged();
    expect(store.blackboardIndex, isNull);
    expect(service.cachedCourses, isEmpty);
    await service.courses();
    expect(meCalls, 4);
  });

  test('follows REST pagination only within the original collection', () async {
    var nextPage = '/learn/api/public/v1/courses/c/contents?offset=1';
    final f = CampusFixture('https://elearning.shanghaitech.edu.cn:8443', (request) {
      final second = request.uri.queryParameters['offset'] == '1';
      return respond({
        'results': [
          {'id': second ? 'second' : 'first'},
        ],
        if (!second) 'paging': {'nextPage': nextPage},
      });
    });
    final client = ElearningClient(f.session);
    final rows = await ElearningService(client).contents('c');
    expect(rows.map((r) => r.id), ['first', 'second']);
    nextPage = 'https://other.invalid/learn/api/public/v1/courses/c/contents?offset=1';
    await expectLater(client.getCourseContents('c', allPages: true), throwsException);
    expect(f.requests, hasLength(3));
  });

  test('calendar IDs, window params, term filtering and Shanghai wall time survive DDL migration',
      () async {
    final requestedColumns = <String>[];
    String? startParam;
    String? endParam;
    final f = CampusFixture('https://elearning.shanghaitech.edu.cn:8443', (r) {
      final path = r.uri.path;
      if (path.endsWith('/allCourseEvents')) {
        startParam = r.uri.queryParameters['start'];
        endParam = r.uri.queryParameters['end'];
        return respond([
          {
            'itemSourceId': 'col1',
            'calendarName': '电路',
            'title': '实验',
            'end': '2030-02-03 10:00:00',
            'attemptable': true,
          },
          {'calendarId': 'personal', 'title': '报告', 'start': 1800000000, 'attemptable': false},
        ]);
      }
      if (path == '/learn/api/public/v1/users/me') return respond({'id': 'u'});
      if (path.endsWith('/users/u/courses')) {
        return respond({
          'results': [
            {'courseId': 'c'},
            {'courseId': 'old_c'},
          ],
        });
      }
      if (path.endsWith('/courses/c')) return respond({'id': 'c', 'name': '电路', 'termId': 't_cur'});
      if (path.endsWith('/courses/old_c')) {
        return respond({'id': 'old_c', 'name': '旧课', 'termId': 't_old'});
      }
      if (path.endsWith('/terms')) {
        return respond({
          'results': [
            {'id': 't_cur', 'name': '当前学期'},
            {
              'id': 't_old',
              'name': '两年前学期',
              'duration': {'end': '2020-01-01T00:00:00Z'},
            },
          ],
        });
      }
      if (path.endsWith('/columns')) {
        requestedColumns.add(path);
        return respond({
          'results': [
            {
              'id': 'col1',
              'name': '实验',
              'grading': {'due': '2030-02-03T02:00:00Z'},
            },
            {
              'id': 'col2',
              'name': '另一份作业',
              'contentId': 'item',
              'grading': {'due': '2030-02-05T02:00:00Z'},
            },
            {
              'id': 'col_ancient',
              'name': '三年前作业',
              'grading': {'due': '2020-01-02T00:00:00Z'},
            },
            {'id': 'col3', 'name': '无日期'},
          ],
        });
      }
      fail(path);
    });
    final service = ElearningService(ElearningClient(f.session));
    final deadlines = await service.deadlines();
    expect(int.tryParse(startParam ?? ''), isNotNull);
    expect(int.tryParse(endParam ?? ''), greaterThan(int.parse(startParam!)));
    expect(requestedColumns, ['/learn/api/public/v1/courses/c/gradebook/columns']);
    expect(deadlines.map((item) => item.id), ['col1', 'personal:报告:1800000000', 'col2']);
    expect(deadlines.first.due.toUtc(), DateTime.utc(2030, 2, 3, 2));
    expect(deadlines.first.url, endsWith('GradableItem-col1'));
    expect(deadlines[1].status, 'Closed');
    expect(deadlines.last.url, contains('content_id=item'));
  });

  testWidgets('folder node detail renders body, attachments and child contents', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    await storage.saveSession(
      UserSession(
        userId: 'user',
        userName: 'User',
        schoolName: 'ShanghaiTech',
        createdAt: DateTime(2026),
      ),
    );
    await storage.saveThirdPartyAccount(FakeIdsClient.account('bound'));
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    await auth.loadSession();
    final tpAuth = ThirdPartyAuthService(storage, http, idsClient: FakeIdsClient());
    await tpAuth.initialize();
    final schedule = ScheduleService(storage, http, auth, tpAuth);
    final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
    final egate = EgateAppService(auth, storage, tpAuth);
    final oa = OaGymService(auth, storage, tpAuth);
    final card = CampusCardService(storage: storage);
    final sync = SyncService(auth, tpAuth, storage, ecard: card);
    final theme = ThemeService(storage);
    final bind = EcardBindService();
    final allowance = StudentAllowanceService(auth, tpAuth);
    final update = UpdateService();
    final f = CampusFixture('https://elearning.shanghaitech.edu.cn:8443', (r) {
      final path = r.uri.path;
      if (path.endsWith('/courses/c/contents')) {
        return respond({
          'results': [
            {
              'id': 'folder1',
              'title': '实验指导目录',
              'body': '<p>目录说明文字</p>',
              'hasChildren': true,
              'contentHandler': {'id': 'resource/x-bb-folder'},
            },
          ],
        });
      }
      if (path.endsWith('/folder1/attachments')) {
        return respond({
          'results': [
            {'id': 'att1', 'fileName': 'folder_guide.pdf'},
          ],
        });
      }
      if (path.endsWith('/folder1/children')) {
        return respond({
          'results': [
            {'id': 'child1', 'title': '子节点文档'},
          ],
        });
      }
      if (path.endsWith('/announcements') || path.endsWith('/announcement')) {
        return respond('');
      }
      return respond({'results': <Object>[]});
    });

    final clients = _FixtureCampusClients(auth, tpAuth, ElearningClient(f.session), storage);
    addTearDown(() {
      clients.blackboard.dispose();
      clients.dispose();
      schedule.dispose();
      assignments.dispose();
      egate.dispose();
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
        campusClients: clients,
        studentAllowanceService: allowance,
        uniAuthService: uniAuth,
        syncService: sync,
        updateService: update,
        campusCardService: card,
        ecardBindService: bind,
        child: const MaterialApp(
          home: ElearningCourseDetailPage(
            course: BlackboardCourse('c', 'CS100', '导论', '秋'),
            owner: (user: 'user', ids: 'bound'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('实验指导目录'));
    await tester.pumpAndSettle();
    expect(find.text('目录说明文字'), findsOneWidget);
    expect(find.text('folder_guide.pdf'), findsOneWidget);
    expect(find.text('子节点文档'), findsOneWidget);
  });
}

class _FixtureCampusClients extends CampusClients {
  _FixtureCampusClients(
    super.auth,
    super.bindings,
    this._customElearning,
    StorageService storage,
  ) : super(storage: storage);

  final ElearningClient _customElearning;

  @override
  ElearningClient get elearning => _customElearning;

  @override
  // ignore: overridden_fields
  late final ElearningService blackboard = ElearningService(_customElearning);
}
