import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/elearning_models.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/elearning_course_detail_page.dart';
import 'package:techpie/pages/elearning_hub_page.dart';
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

  test('deadlines merge submitted and graded states with calendar and gradebook dates',
      () async {
    final requestedColumns = <String>[];
    var gradePageRequests = 0;
    final now = DateTime.now();
    final recentPast = now.subtract(const Duration(days: 3)).toUtc().toIso8601String();
    final personalDue = now.add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000;
    String? startParam;
    String? endParam;
    final f = CampusFixture('https://elearning.shanghaitech.edu.cn:8443', (r) {
      final path = r.uri.path;
      if (path.endsWith('/allCourseEvents')) {
        startParam = r.uri.queryParameters['start'];
        endParam = r.uri.queryParameters['end'];
        return respond([
          {
            'itemSourceId': '_101_1',
            'calendarName': '电路',
            'title': '实验',
            'end': '2030-02-03 10:00:00',
            'attemptable': true,
          },
          {'calendarId': 'personal', 'title': '报告', 'start': personalDue, 'attemptable': false},
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
      if (path.endsWith('/myGrades')) {
        gradePageRequests++;
        expect(r.uri.queryParameters['course_id'], 'c');
        return respond('''
<div id="101" class="sortable_item_row upcoming_item_row">
  <div class="gradeStatus"><img src="/images/needs_grading.png"></div>
</div>
<div id="102" class="sortable_item_row upcoming_item_row">
  <div class="gradeStatus"><img src="/images/needs_grading.png"></div>
</div>
<div id="103" class="sortable_item_row graded_item_row"></div>
''');
      }
      if (path.endsWith('/columns')) {
        requestedColumns.add(path);
        return respond({
          'results': [
            {
              'id': '_101_1',
              'name': '实验',
              'grading': {'due': '2030-02-03T02:00:00Z'},
            },
            {
              'id': '_102_1',
              'name': '另一份作业',
              'contentId': 'item',
              'grading': {'due': recentPast},
            },
            {
              'id': '_103_1',
              'name': 'Graded assignment',
              'grading': {'due': recentPast},
            },
            {
              'id': '_104_1',
              'name': 'Upcoming assignment',
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
    expect(gradePageRequests, 1);
    expect(
      deadlines.map((item) => item.id),
      ['_101_1', 'personal:报告:$personalDue', '_102_1', '_103_1', '_104_1'],
    );
    expect(
      deadlines.map((item) => item.status),
      ['Submitted', 'Closed', 'Submitted', 'Graded', 'Open'],
    );
    expect(
      deadlines.where((item) => item.submitted).map((item) => item.id),
      ['_101_1', '_102_1', '_103_1'],
    );
    expect(deadlines.first.due.toUtc(), DateTime.utc(2030, 2, 3, 2));
    expect(deadlines.first.url, endsWith('GradableItem-_101_1'));
    expect(deadlines[2].url, contains('content_id=item'));
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

  test(
      'parseBlackboardTermSortKey and compareBlackboardTermNames order terms newest-first with unassigned last',
      () {
    expect(parseBlackboardTermSortKey('2024-2025学年 第一学期'), 202409);
    expect(parseBlackboardTermSortKey('2024-2025学年 第二学期'), 202502);
    expect(parseBlackboardTermSortKey('2025-2026学年 第一学期'), 202509);
    expect(parseBlackboardTermSortKey('2025-2026学年 第二学期'), 202602);
    expect(parseBlackboardTermSortKey('2025-2026学年 暑期学期'), 202607);
    expect(parseBlackboardTermSortKey('2025 Fall'), 202509);
    expect(parseBlackboardTermSortKey('2026 Spring'), 202602);
    expect(parseBlackboardTermSortKey('2026 Summer'), 202607);
    expect(parseBlackboardTermSortKey('2026 Fall'), 202609);
    expect(parseBlackboardTermSortKey('2025-2026-1'), 202509);
    expect(parseBlackboardTermSortKey('2025-2026-2'), 202602);
    expect(parseBlackboardTermSortKey('20261'), 202609);
    expect(parseBlackboardTermSortKey('长期开放课程'), isNull);
    expect(parseBlackboardTermSortKey(''), isNull);
    expect(parseBlackboardTermSortKey('其他学期'), isNull);

    final labels = [
      '',
      '2024-2025学年 第一学期',
      '长期开放课程',
      '2025-2026-2',
      '2025-2026学年 暑期学期',
      '2024-2025学年 第二学期',
      '其他学期',
      '2026 Fall',
      '2025 Fall',
    ]..sort(compareBlackboardTermNames);

    expect(labels, [
      '2026 Fall',
      '2025-2026学年 暑期学期',
      '2025-2026-2',
      '2025 Fall',
      '2024-2025学年 第二学期',
      '2024-2025学年 第一学期',
      '长期开放课程',
      '',
      '其他学期',
    ]);
  });

  test(
      'ElearningService.courses sorts fetched courses newest-term-first using term names and duration and restores legacy caches sorted',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = StorageService(await SharedPreferences.getInstance());
    final f = CampusFixture('https://elearning.shanghaitech.edu.cn:8443', (r) {
      final path = r.uri.path;
      if (path == '/learn/api/public/v1/users/me') return respond({'id': 'me'});
      if (path.endsWith('/users/me/courses')) {
        return respond({
          'results': [
            {'courseId': 'c_empty'},
            {'courseId': 'c_old'},
            {'courseId': 'c_spring_a'},
            {'courseId': 'c_dur'},
            {'courseId': 'c_spring_b'},
            {'courseId': 'c_summer'},
            {'courseId': 'c_fall'},
          ],
        });
      }
      if (path.endsWith('/terms')) {
        return respond({
          'results': [
            {'id': '_10_1', 'name': '2024-2025学年 第一学期'},
            {'id': '_11_1', 'name': '2025-2026学年 第二学期'},
            {
              'id': '_99_1',
              'name': '特别学期',
              'duration': {'start': '2026-06-15T00:00:00Z'},
            },
            {'id': '_12_1', 'name': '2025-2026学年 暑期学期'},
            {'id': '_13_1', 'name': '2026-2027学年 第一学期'},
          ],
        });
      }
      if (path.endsWith('/courses/c_empty')) {
        return respond({'id': 'c_empty', 'courseId': 'GEN001', 'name': '导学'});
      }
      if (path.endsWith('/courses/c_old')) {
        return respond({'id': 'c_old', 'courseId': 'CS100', 'name': '旧课', 'termId': '_10_1'});
      }
      if (path.endsWith('/courses/c_spring_a')) {
        return respond({'id': 'c_spring_a', 'courseId': 'CS201', 'name': '春甲', 'termId': '_11_1'});
      }
      if (path.endsWith('/courses/c_spring_b')) {
        return respond({'id': 'c_spring_b', 'courseId': 'CS202', 'name': '春乙', 'termId': '_11_1'});
      }
      if (path.endsWith('/courses/c_dur')) {
        return respond({'id': 'c_dur', 'courseId': 'SP101', 'name': '专题', 'termId': '_99_1'});
      }
      if (path.endsWith('/courses/c_summer')) {
        return respond({'id': 'c_summer', 'courseId': 'SUM1', 'name': '夏课', 'termId': '_12_1'});
      }
      if (path.endsWith('/courses/c_fall')) {
        return respond({'id': 'c_fall', 'courseId': 'CS301', 'name': '新课', 'termId': '_13_1'});
      }
      fail(path);
    });

    final service = ElearningService(ElearningClient(f.session), storage: store);
    final loaded = await service.courses();
    expect(
      loaded.map((c) => c.id),
      ['c_fall', 'c_summer', 'c_dur', 'c_spring_a', 'c_spring_b', 'c_old', 'c_empty'],
    );

    await store.saveBlackboardIndex({
      'owner': store.blackboardIndex!['owner'],
      'courses': [
        {'id': 'l_old', 'courseId': 'C1', 'name': '旧课', 'term': '2024-2025学年 第一学期'},
        {'id': 'l_empty', 'courseId': 'C0', 'name': '无学期', 'term': ''},
        {'id': 'l_new', 'courseId': 'C2', 'name': '新课', 'term': '2026-2027学年 第一学期'},
      ],
      'announcements': const <Object>[],
    });
    final restored = ElearningService(ElearningClient(f.session), storage: store);
    expect(restored.cachedCourses.map((c) => c.id), ['l_new', 'l_old', 'l_empty']);
  });

  testWidgets('ElearningHubPage renders newest semester sections at top and unassigned term last',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
      if (path == '/learn/api/public/v1/users/me') return respond({'id': 'u'});
      if (path.endsWith('/users/u/courses')) {
        return respond({
          'results': [
            {'courseId': 'c_none'},
            {'courseId': 'c_25_fall'},
            {'courseId': 'c_26_spring'},
            {'courseId': 'c_26_summer'},
            {'courseId': 'c_26_fall'},
          ],
        });
      }
      if (path.endsWith('/terms')) {
        return respond({
          'results': [
            {'id': 't1', 'name': '2025-2026学年 第一学期'},
            {'id': 't2', 'name': '2025-2026学年 第二学期'},
            {'id': 't3', 'name': '2025-2026学年 暑期学期'},
            {'id': 't4', 'name': '2026-2027学年 第一学期'},
          ],
        });
      }
      if (path.endsWith('/courses/c_none')) {
        return respond({'id': 'c_none', 'courseId': 'GEN', 'name': '通识导论'});
      }
      if (path.endsWith('/courses/c_25_fall')) {
        return respond({'id': 'c_25_fall', 'courseId': 'C1', 'name': '大一秋', 'termId': 't1'});
      }
      if (path.endsWith('/courses/c_26_spring')) {
        return respond({'id': 'c_26_spring', 'courseId': 'C2', 'name': '大一春', 'termId': 't2'});
      }
      if (path.endsWith('/courses/c_26_summer')) {
        return respond({'id': 'c_26_summer', 'courseId': 'C3', 'name': '暑期课', 'termId': 't3'});
      }
      if (path.endsWith('/courses/c_26_fall')) {
        return respond({'id': 'c_26_fall', 'courseId': 'C4', 'name': '大二秋', 'termId': 't4'});
      }
      if (path.endsWith('/announcement')) return respond('');
      fail(path);
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
        child: const MaterialApp(home: ElearningHubPage()),
      ),
    );
    await tester.pumpAndSettle();

    final y26Fall = tester.getTopLeft(find.text('2026-2027学年 第一学期')).dy;
    final y26Summer = tester.getTopLeft(find.text('2025-2026学年 暑期学期')).dy;
    final y26Spring = tester.getTopLeft(find.text('2025-2026学年 第二学期')).dy;
    final y25Fall = tester.getTopLeft(find.text('2025-2026学年 第一学期')).dy;
    final yOther = tester.getTopLeft(find.text('其他学期')).dy;

    expect(y26Fall, lessThan(y26Summer));
    expect(y26Summer, lessThan(y26Spring));
    expect(y26Spring, lessThan(y25Fall));
    expect(y25Fall, lessThan(yOther));
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
