import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/elearning_models.dart';
import 'package:techpie/models/feature.dart';
import 'package:techpie/models/oa_gym.dart';
import 'package:techpie/models/quick_shortcuts.dart';
import 'package:techpie/models/student_allowance.dart';
import 'package:techpie/models/study_plan.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/academic_certificates_page.dart';
import 'package:techpie/pages/campus_feature_navigation.dart';
import 'package:techpie/pages/campus_jobs_page.dart';
import 'package:techpie/pages/course_catalog_search_page.dart';
import 'package:techpie/pages/egate_app_page.dart';
import 'package:techpie/pages/elearning_course_detail_page.dart';
import 'package:techpie/pages/grades_page.dart';
import 'package:techpie/pages/holiday_travel_page.dart';
import 'package:techpie/pages/student_allowance_page.dart';
import 'package:techpie/pages/study_plan_page.dart';
import 'package:techpie/services/academic_certificate_service.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus/campus_clients.dart';
import 'package:techpie/services/campus/eams_client.dart';
import 'package:techpie/services/campus/elearning_client.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/course_catalog_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/elearning_service.dart';
import 'package:techpie/services/grade_service.dart';
import 'package:techpie/services/holiday_travel_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_allowance_service.dart';
import 'package:techpie/services/study_plan_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/theme/tp_icons.dart';
import 'package:techpie/widgets/campus_prerequisite_view.dart';
import 'package:techpie/widgets/design_system/design_system.dart';
import 'package:techpie/widgets/gym/gym_booking_tab.dart';
import 'package:techpie/widgets/gym/gym_profile_tab.dart';

import 'campus/campus_fixture.dart';

class _MutableAuth extends AuthService {
  _MutableAuth(super.storage, super.http, super.uniAuth, {this.signedIn = true});

  bool signedIn;
  String uid = 'u-1';

  @override
  bool get isLoggedIn => signedIn;

  @override
  UserSession? get session => signedIn
      ? UserSession(
          userId: uid,
          userName: '测试同学',
          schoolName: 'ShanghaiTech',
          createdAt: DateTime.utc(2026),
        )
      : null;

  void setSignedIn(bool value, {String? userId}) {
    signedIn = value;
    if (userId != null) uid = userId;
    notifyListeners();
  }
}

class _MutableThirdPartyAuth extends ThirdPartyAuthService {
  _MutableThirdPartyAuth(super.storage, super.http);

  bool bound = true;
  String studentId = '20240001';

  @override
  bool get hasIdsBinding => bound;

  @override
  String get idsStudentId => bound ? studentId : '';

  @override
  ThirdPartyAccount? get idsAccount => bound
      ? ThirdPartyAccount(
          platform: ThirdPartyPlatform.ids,
          account: studentId,
          sid: studentId,
          name: '测试同学',
          email: 'test@shanghaitech.edu.cn',
          token: 'mock',
          boundAt: DateTime.utc(2026),
        )
      : null;

  void setBound(bool value, {String? id}) {
    bound = value;
    if (id != null) studentId = id;
    notifyListeners();
  }
}

class _OfflineSchedule extends ScheduleService {
  _OfflineSchedule(super.storage, super.http, super.auth, super.tpAuth);

  @override
  void requestFetch({bool force = false}) {}
}

class _FakeAllowanceService extends StudentAllowanceService {
  _FakeAllowanceService(super.auth, super.tpAuth, this.reportToReturn);

  final StudentAllowanceReport reportToReturn;

  @override
  StudentAllowanceAccess get access => StudentAllowanceAccess.ready;

  @override
  Future<StudentAllowanceReport> query(StudentAllowancePeriod period) async =>
      reportToReturn;
}

class _FakeEgateAppService extends EgateAppService {
  _FakeEgateAppService(super.auth, super.storage, super.tpAuth);

  String message = '活动公告 A';
  List<EgateAppSignRecord> records = const [
    EgateAppSignRecord(
      wid: '1',
      activityName: '新生讲座 A',
      typeDisplay: '讲座',
      statusDisplay: '已签到',
      date: '2026-10-01',
    ),
  ];

  @override
  Future<String> fetchSignMessage() async => message;

  @override
  Future<List<EgateAppSignRecord>> fetchSignHistory() async => records;
}

class _FakeOaGymService extends OaGymService {
  _FakeOaGymService(super.auth, super.storage, super.tpAuth);

  int bookCalls = 0;
  bool failSaveProfile = false;

  @override
  Future<List<OaAvailability>> checkAvailability({
    required Set<OaSport> sports,
    required String date,
    required int startSlot,
    required int endSlot,
    void Function(List<OaAvailability>)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    return [
      for (final sport in sports)
        for (var slot = startSlot; slot <= endSlot; slot++)
          OaAvailability(
            sport: sport,
            date: date,
            timeSlot: slot,
            availableCourts: slot == 8 ? const [1] : const [],
            totalCourts: 6,
          ),
    ];
  }

  @override
  Future<OaBookingResult> bookCourt({
    required OaSport sport,
    required String date,
    required int timeSlot,
    required int courtNumber,
    required int playersCount,
  }) async {
    bookCalls++;
    return const OaBookingResult(success: true, message: '预约成功');
  }

  @override
  Future<void> saveBookingProfile(OaBookingProfile profile) async {
    if (failSaveProfile) {
      throw OaGymException('模拟保存失败');
    }
    await super.saveBookingProfile(profile);
  }
}

class _CustomCampusClients extends CampusClients {
  _CustomCampusClients(
    super.auth,
    super.bindings,
    this.customBlackboard,
    StorageService storage,
  ) : super(storage: storage);

  final ElearningService customBlackboard;

  @override
  ElearningService get blackboard => customBlackboard;
}

Future<Widget> _wrapWithProviders({
  required Widget home,
  required StorageService storage,
  _MutableAuth? auth,
  _MutableThirdPartyAuth? tpAuth,
  StudyPlanService? studyPlanService,
  bool includeStudyPlan = true,
  StudentAllowanceService? allowanceService,
  EgateAppService? egateAppService,
  OaGymService? oaGymService,
  CampusClients? campusClients,
}) async {
  final logger = DebugLogger();
  final http = LoggingHttpClient(
    logger,
    inner: MockClient((_) async => throw StateError('unexpected HTTP')),
  );
  final uniAuth = UniAuthService();
  final authSvc = auth ?? _MutableAuth(storage, http, uniAuth);
  final tpSvc = tpAuth ?? _MutableThirdPartyAuth(storage, http);
  final theme = ThemeService(storage);
  final schedule = _OfflineSchedule(storage, http, authSvc, tpSvc);
  final assignments = AssignmentService(storage, http, authSvc, tpSvc, schedule);
  final allowance = allowanceService ?? StudentAllowanceService(authSvc, tpSvc);
  final egate = egateAppService ?? EgateAppService(authSvc, storage, tpSvc);
  final gym = oaGymService ?? OaGymService(authSvc, storage, tpSvc);
  final card = CampusCardService();
  addTearDown(() {
    schedule.dispose();
    assignments.dispose();
    if (allowanceService == null) allowance.dispose();
    if (egateAppService == null) egate.dispose();
    if (oaGymService == null) gym.dispose();
    card.dispose();
    http.close();
  });

  return ServiceProvider(
    authService: authSvc,
    debugLogger: logger,
    storageService: storage,
    studyPlanService: includeStudyPlan ? studyPlanService : null,
    themeService: theme,
    scheduleService: schedule,
    assignmentService: assignments,
    thirdPartyAuthService: tpSvc,
    oaGymService: gym,
    egateAppService: egate,
    studentAllowanceService: allowance,
    uniAuthService: uniAuth,
    syncService: SyncService(authSvc, tpSvc, storage),
    updateService: UpdateService(),
    campusClients: campusClients,
    campusCardService: card,
    ecardBindService: EcardBindService(),
    child: MaterialApp(home: home),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('1. featureEntries use unique Lucide icons per category and 5 default pins',
      () {
    expect(featureEntries, hasLength(15));
    expect(
      featureEntries.where((f) => f.pinnedByDefault),
      hasLength(maxPinnedQuickFeatures),
    );
    for (final entry in featureEntries) {
      expect(
        entry.icon.icon?.fontPackage,
        'flutter_lucide',
        reason: '${entry.id} must use TpIcons (flutter_lucide)',
      );
    }
    for (final category in CampusServiceCategory.values) {
      final inCat = featureEntries.where((f) => f.category == category).toList();
      final codePoints = inCat.map((f) => f.icon.icon!.codePoint).toSet();
      expect(
        codePoints,
        hasLength(inCat.length),
        reason: 'Duplicate icon inside category ${category.name}',
      );
    }
  });

  testWidgets('2. openCampusFeature exempts campus_card from TechPie login gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    final storage = StorageService(await SharedPreferences.getInstance());
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final auth = _MutableAuth(storage, http, UniAuthService(), signedIn: false);
    addTearDown(http.close);

    var opened = false;
    final cardFeature = Feature(
      id: 'campus_card',
      description: '校园卡',
      mode: FeatureMode.native,
      icon: const Icon(TpIcons.wallet),
      nativeEntry: (_) => opened = true,
    );

    await tester.pumpWidget(
      await _wrapWithProviders(
        storage: storage,
        auth: auth,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(openCampusFeature(context, cardFeature)),
              child: const Text('打开校园卡'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开校园卡'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(auth.isLoggedIn, isFalse);
  });

  testWidgets(
      '3. GradesPage search toggle, independent duplicate trial rows, delta badge and reset',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final http = LoggingHttpClient(DebugLogger());
    final auth = _MutableAuth(storage, http, UniAuthService());
    final tpAuth = _MutableThirdPartyAuth(storage, http);
    final f = CampusFixture(
      'https://eams.shanghaitech.edu.cn',
      (r) => respond(
        '<table><tr><th>课程名称</th><th>最终</th><th>学分</th><th>绩点</th><th>学年学期</th></tr>'
        '<tr><td>Alpha</td><td>B</td><td>3</td><td>3.0</td><td>2025-2026 春</td></tr>'
        '<tr><td>Beta</td><td>A</td><td>3</td><td>4.0</td><td>2025-2026 春</td></tr>'
        '</table>',
      ),
    )..identity = (user: 'u-1', ids: '20240001');
    final service = GradeService(
      EamsClient(f.session, minInterval: Duration.zero, retryDelay: Duration.zero),
      storage,
      auth,
      tpAuth,
    );
    addTearDown(() {
      service.dispose();
      http.close();
    });

    await tester.pumpWidget(MaterialApp(home: GradesPage(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.byTooltip('搜索课程'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索课程名称或代码'), 'Alpha');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);

    // Close search bar before adding trial courses.
    await tester.tap(find.byTooltip('收起搜索'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('本地 GPA 试算'));
    await tester.tap(find.text('本地 GPA 试算'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('添加假设课程'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '2');
      await tester.tap(find.text('4.0'));
      await tester.pump();
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
    }

    expect(find.text('假设课程'), findsNWidgets(2));
    expect(find.text('重置试算'), findsOneWidget);
    expect(find.byType(TpBadge), findsWidgets);

    // Unchecking the first identical trial course must leave the second checked.
    final checkBoxes = find.byType(Checkbox);
    final totalCheckboxes = tester.widgetList<Checkbox>(checkBoxes).length;
    final firstTrialIdx = totalCheckboxes - 2;
    await tester.ensureVisible(checkBoxes.at(firstTrialIdx));
    await tester.tap(checkBoxes.at(firstTrialIdx));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(checkBoxes.at(firstTrialIdx)).value, isFalse);
    expect(tester.widget<Checkbox>(checkBoxes.at(firstTrialIdx + 1)).value, isTrue);

    // Removing one trial row individually leaves one.
    final removeBtn = find.byTooltip('移除假设课程').first;
    await tester.ensureVisible(removeBtn);
    await tester.tap(removeBtn);
    await tester.pumpAndSettle();
    expect(find.text('假设课程'), findsOneWidget);

    await tester.ensureVisible(find.text('重置试算'));
    await tester.tap(find.text('重置试算'));
    await tester.pumpAndSettle();
    expect(find.text('假设课程'), findsNothing);
  });

  testWidgets(
      '4. StudyPlanPage handles null service, merges status by rank and clears search',
      (tester) async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    final storage = StorageService(await SharedPreferences.getInstance());

    await tester.pumpWidget(
      await _wrapWithProviders(
        storage: storage,
        includeStudyPlan: false,
        home: const StudyPlanPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CampusPrerequisiteView), findsOneWidget);
    expect(find.text('需要绑定 IDS 账号'), findsOneWidget);
    expect(find.textContaining('培养计划复用已绑定的校园 IDS 登录态'), findsOneWidget);

    // Cross-module status merge prefers passed over unknown.
    const owner = '["user","bound"]';
    final summaryPlan = StudyPlanSnapshot(
      [
        PlanCategoryProgress(
          '通识',
          0,
          courses: [
            const PlanCourseItem(
              'CS100',
              '导论',
              3,
              '1',
              true,
              '信息学院',
              PlanCourseStatus.unknown,
            ),
          ],
        ),
        PlanCategoryProgress(
          '专业',
          0,
          courses: [
            const PlanCourseItem(
              'CS100',
              '导论',
              3,
              '1',
              true,
              '信息学院',
              PlanCourseStatus.passed,
            ),
          ],
        ),
      ],
      12,
      3,
      DateTime(2026),
    );
    final fullPlan = StudyPlanSnapshot(
      [
        PlanCategoryProgress(
          '完整方案模块',
          0,
          courses: [
            const PlanCourseItem(
              'CS100',
              '导论',
              3,
              '1',
              true,
              '信息学院',
              PlanCourseStatus.unknown,
            ),
          ],
        ),
      ],
      12,
      3,
      DateTime(2026),
    );
    await storage.saveStudyPlanCache(
      false,
      {'owner': owner, 'snapshot': summaryPlan.toJson()},
    );
    await storage.saveStudyPlanCache(
      true,
      {'owner': owner, 'snapshot': fullPlan.toJson()},
    );

    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) => respond(''));
    final service = StudyPlanService(
      EamsClient(f.session),
      storage,
      () => f.identity,
      ChangeNotifier(),
    );
    addTearDown(service.dispose);

    await tester.pumpWidget(MaterialApp(home: StudyPlanPage(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('完整方案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完整方案模块'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已通过'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'NOPE');
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的课程或模块'), findsOneWidget);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('完整方案模块'), findsOneWidget);
  });

  testWidgets(
      '5. CourseCatalogSearchPage badge, non-querying reset, and detail copy code',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    var searchRequests = 0;
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) {
      if (r.uri.path.endsWith('!search.action')) {
        searchRequests++;
        return respond(
          '<table class="gridtable"><tr><th>课程代码</th><th>课程名称</th><th>开课院系</th><th>学分</th><th>教师</th></tr>'
          '<tr><td>CS101</td><td>数据结构</td><td>信息学院</td><td>4</td><td>张老师</td></tr>'
          '</table>',
        );
      }
      return respond('<select name="course.department.id"><option value="">不限</option></select>');
    });
    final service = CourseCatalogService(
      EamsClient(f.session, minInterval: Duration.zero, retryDelay: Duration.zero),
      storage,
      ChangeNotifier(),
      ChangeNotifier(),
    );
    addTearDown(service.dispose);

    await tester.pumpWidget(MaterialApp(home: CourseCatalogSearchPage(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('筛选条件'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '学分'), '4');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(searchRequests, 1);

    // Collapse filters and inspect active filter badge '1'.
    await tester.tap(find.text('筛选条件'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    // Re-expand and reset filters when keyword is empty -> no new search.
    await tester.tap(find.text('筛选条件'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重置筛选'));
    await tester.tap(find.text('重置筛选'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(searchRequests, 1);

    // Collapse filters and search for CS101, then copy course code in detail sheet.
    await tester.tap(find.text('筛选条件'));
    await tester.pumpAndSettle();
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final keywordField = find.widgetWithText(TextField, '课程名称或代码');
    await tester.ensureVisible(keywordField);
    await tester.enterText(keywordField, 'CS101');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('数据结构'), findsOneWidget);

    await tester.tap(find.text('数据结构'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制代码 CS101'));
    await tester.pumpAndSettle();
    expect(copied, 'CS101');
  });

  testWidgets(
      '6. AcademicCertificatesPage disables readOnly dropdowns and syncs summary',
      (tester) async {
    const listHtml = '''
      <script>var action=bar.addEntityAction('stdPrinterApply',page_grid1);
      bar.addItem("申请",action.add());</script>
      <table><tr><th>申请时间</th></tr></table>''';
    const editorHtml = '''
      <form action="/eams/teach/grade/transcript/stdPrinterApply!save.action" method="post">
      <input type="hidden" name="stdPrinterApply.id" value="">
      <label for="kind">语言</label>
      <select id="kind" name="lang" readonly>
        <option value="zh" selected>中文</option>
        <option value="en">英文</option>
      </select>
      <textarea title="申请理由" name="stdPrinterApply.applyReason"></textarea>
      </form>''';
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) {
      if (r.uri.path.endsWith('!search.action')) return respond(listHtml);
      if (r.uri.path.endsWith('!edit.action')) return respond(editorHtml);
      return respond('<div class="success">申请成功</div>');
    });
    SharedPreferences.setMockInitialValues({});
    final s = AcademicCertificateService(
      EamsClient(f.session, minInterval: Duration.zero, retryDelay: Duration.zero),
      StorageService(await SharedPreferences.getInstance()),
      ValueNotifier(0),
      ValueNotifier(0),
    );
    addTearDown(s.dispose);

    await tester.pumpWidget(MaterialApp(home: AcademicCertificatesPage(service: s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新申请'));
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(dropdown.onChanged, isNull);

    await tester.enterText(find.byType(TextFormField), '留学需要');
    await tester.tap(find.text('核对申请'));
    await tester.pumpAndSettle();
    expect(find.textContaining('语言 · 中文'), findsOneWidget);
    expect(find.textContaining('申请理由 · 留学需要'), findsOneWidget);
  });

  testWidgets(
      '7. ElearningCourseDetailPage retries failed folder attachments cleanly',
      (tester) async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    final storage = StorageService(await SharedPreferences.getInstance());
    final http = LoggingHttpClient(DebugLogger());
    final auth = _MutableAuth(storage, http, UniAuthService());
    final tpAuth = _MutableThirdPartyAuth(storage, http);
    var attachmentAttempts = 0;

    final f = CampusFixture('https://elearning.shanghaitech.edu.cn', (r) {
      final path = r.uri.path;
      if (path.endsWith('/contents')) {
        return respond({
          'results': [
            {
              'id': 'folder-1',
              'title': '实验目录',
              'body': '目录说明',
              'hasChildren': true,
              'contentHandler': {'id': 'resource/x-bb-folder'},
            },
          ],
        });
      }
      if (path.endsWith('/children')) return respond({'results': <Object>[]});
      if (path.endsWith('/attachments')) {
        attachmentAttempts++;
        if (attachmentAttempts == 1) return respond('server error', status: 500);
        return respond({
          'results': [
            {'id': 'att-1', 'fileName': 'lab_manual.pdf'},
          ],
        });
      }
      return respond({'results': <Object>[]});
    });

    final blackboard = ElearningService(ElearningClient(f.session));
    final clients = _CustomCampusClients(
      auth,
      tpAuth,
      blackboard,
      storage,
    );
    addTearDown(() {
      blackboard.dispose();
      clients.dispose();
      http.close();
    });

    await tester.pumpWidget(
      await _wrapWithProviders(
        storage: storage,
        auth: auth,
        tpAuth: tpAuth,
        campusClients: clients,
        home: const ElearningCourseDetailPage(
          course: BlackboardCourse('c1', 'CS101', '数据结构', '秋'),
          owner: (user: 'user', ids: 'bound'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('实验目录'));
    await tester.pumpAndSettle();

    expect(find.byType(TpStateCard), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('lab_manual.pdf'), findsOneWidget);
  });

  testWidgets(
      '8. CampusJobsPage filters openings and preserves pay eye toggle when totalError != null',
      (tester) async {
    final f = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      if (r.uri.path.contains('/getAppConfig/')) return respond({});
      final model = r.uri.pathSegments.last.split('.').first;
      if (model == 'tjje') return respond({'code': '-1', 'msg': 'rejected'});
      final rows = switch (model) {
        'ksqdgwcx' => [
            {'GWMC': '图书馆助理', 'DWMC': '图书馆', 'WID': '1'},
            {'GWMC': '食堂协调员', 'DWMC': '后勤处', 'WID': '2'},
          ],
        'cxsgsqxx' => <Map<String, dynamic>>[],
        'cxgwxx' => <Map<String, dynamic>>[],
        'xzmx' => [
            {'FFYF': '2026-01', 'SFJE': '1837.42', 'GS': 16, 'BCBZ': 22},
          ],
        _ => <Map<String, dynamic>>[],
      };
      return respond({
        'code': 0,
        'datas': {
          model: {'rows': rows, 'totalSize': rows.length},
        },
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CampusJobPanels(
          client: EmapClient(f.session),
          studentId: '20240001',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('图书馆助理'), findsOneWidget);
    expect(find.text('食堂协调员'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '搜索岗位、用工单位或类别'),
      '图书馆',
    );
    await tester.pumpAndSettle();
    expect(find.text('图书馆助理'), findsOneWidget);
    expect(find.text('食堂协调员'), findsNothing);

    await tester.tap(find.text('在岗薪资'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('显示金额'), findsOneWidget);
    expect(find.textContaining('1837.42'), findsNothing);

    await tester.tap(find.byTooltip('显示金额'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1837.42'), findsOneWidget);
  });

  testWidgets('9. HolidayTravelPage exits compose cleanly via 取消编辑',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    final f = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      if (r.uri.path.contains('getAppConfig')) return respond({});
      return respond({
        'code': 0,
        'datas': {
          'xsdjlsjlbg': {'rows': <Object>[], 'totalSize': 0},
        },
      });
    });
    final service = HolidayTravelService(EmapClient(f.session), storage, account);
    addTearDown(() {
      service.dispose();
      account.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: HolidayTravelPage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建离校登记'));
    await tester.pumpAndSettle();
    expect(find.text('提交离校登记'), findsOneWidget);

    await tester.tap(find.text('取消编辑'));
    await tester.pumpAndSettle();
    expect(find.text('提交离校登记'), findsNothing);
    expect(find.text('新建离校登记'), findsOneWidget);
  });

  testWidgets(
      '10. StudentAllowancePage presets, privacy mask toggle, and null month safety',
      (tester) async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    final storage = StorageService(await SharedPreferences.getInstance());
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final auth = _MutableAuth(storage, http, UniAuthService());
    final tpAuth = _MutableThirdPartyAuth(storage, http);
    final allowance = _FakeAllowanceService(
      auth,
      tpAuth,
      StudentAllowanceReport(
        months: [
          StudentAllowanceEntry(
            month: null,
            categories: const [],
            grossFen: 50000,
            deductionsFen: 0,
            taxFen: 0,
            netFen: 50000,
          ),
        ],
        total: StudentAllowanceEntry(
          month: null,
          categories: const [],
          grossFen: 50000,
          deductionsFen: 0,
          taxFen: 0,
          netFen: 50000,
        ),
      ),
    );
    addTearDown(() {
      allowance.dispose();
      http.close();
    });

    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final currentMonth = DateTime(now.year, now.month);
    final threeMonthsAgo = DateTime(currentMonth.year, currentMonth.month - 2);

    await tester.pumpWidget(
      await _wrapWithProviders(
        storage: storage,
        auth: auth,
        tpAuth: tpAuth,
        allowanceService: allowance,
        home: const StudentAllowancePage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('近 3 个月'));
    await tester.pumpAndSettle();
    expect(
      find.text('开始：${threeMonthsAgo.year}年${threeMonthsAgo.month}月'),
      findsOneWidget,
    );

    await tester.tap(find.text('查询津贴'));
    await tester.pumpAndSettle();
    expect(find.text('未知月份'), findsOneWidget);
    expect(find.text('实发 ¥500.00'), findsNWidgets(2));

    await tester.tap(find.byTooltip('隐藏金额'));
    await tester.pumpAndSettle();
    expect(find.text('实发 ¥****'), findsNWidgets(2));

    await tester.tap(find.byTooltip('显示金额'));
    await tester.pumpAndSettle();
    expect(find.text('实发 ¥500.00'), findsNWidgets(2));
  });

  testWidgets('11. EgateAppPage resets stale announcement & history on sign-out',
      (tester) async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    final storage = StorageService(await SharedPreferences.getInstance());
    final http = LoggingHttpClient(DebugLogger());
    final auth = _MutableAuth(storage, http, UniAuthService());
    final tpAuth = _MutableThirdPartyAuth(storage, http);
    final egate = _FakeEgateAppService(auth, storage, tpAuth);
    addTearDown(() {
      egate.dispose();
      http.close();
    });

    await tester.pumpWidget(
      await _wrapWithProviders(
        storage: storage,
        auth: auth,
        tpAuth: tpAuth,
        egateAppService: egate,
        home: const EgateAppPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('活动公告 A'), findsOneWidget);
    expect(find.text('新生讲座 A'), findsOneWidget);

    auth.setSignedIn(false);
    await tester.pumpAndSettle();
    expect(find.text('活动公告 A'), findsNothing);
    expect(find.text('新生讲座 A'), findsNothing);
    expect(find.text('需要先登录 TechPie'), findsOneWidget);
  });

  testWidgets(
      '12. GymBookingTab confirms before booking and GymProfileTab handles save error',
      (tester) async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    final storage = StorageService(await SharedPreferences.getInstance());
    final http = LoggingHttpClient(DebugLogger());
    final auth = _MutableAuth(storage, http, UniAuthService());
    final tpAuth = _MutableThirdPartyAuth(storage, http);
    final gym = _FakeOaGymService(auth, storage, tpAuth);
    addTearDown(() {
      gym.dispose();
      http.close();
    });

    await tester.pumpWidget(
      await _wrapWithProviders(
        storage: storage,
        auth: auth,
        tpAuth: tpAuth,
        oaGymService: gym,
        home: const Scaffold(body: GymBookingTab()),
      ),
    );
    await tester.pumpAndSettle();

    final courtChip = find.text('羽毛球场地1号').first;
    await tester.ensureVisible(courtChip);
    await tester.tap(courtChip);
    await tester.pumpAndSettle();

    final submitBtn = find.text('提交预约 (1)');
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(find.text('确认提交场馆预约？'), findsOneWidget);
    expect(gym.bookCalls, 0);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(gym.bookCalls, 0);

    await tester.tap(submitBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认预约'));
    await tester.pumpAndSettle();
    expect(gym.bookCalls, 1);

    // GymProfileTab save failure should show feedback cleanly without crashing.
    gym.failSaveProfile = true;
    await tester.pumpWidget(
      await _wrapWithProviders(
        storage: storage,
        auth: auth,
        tpAuth: tpAuth,
        oaGymService: gym,
        home: const Scaffold(body: GymProfileTab()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '姓名'), '张三');
    await tester.enterText(find.widgetWithText(TextField, '手机号'), '13800138000');
    final saveBtn = find.text('保存');
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();
    expect(find.textContaining('模拟保存失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
