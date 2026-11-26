import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/study_plan.dart';
import 'package:techpie/pages/study_plan_page.dart';
import 'package:techpie/services/campus/eams_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/study_plan_parser.dart';
import 'package:techpie/services/study_plan_service.dart';

import 'campus/campus_fixture.dart';

const progress = '''<table><tr><td>要求学分/完成学分/实修学分:</td><td>12 / 3 / 6</td></tr></table>
<table><tr><th>课程序号</th><th>课程代码</th><th>课程名称</th><th>要求学分</th><th>完成学分</th><th>实修学分</th><th>成绩</th><th>是否通过</th><th>备注</th></tr>
<tr><td colspan="3">通识</td><td>12</td><td>3</td><td>6</td><td>缺9分</td></tr>
<tr><td style="padding-left:16px" colspan="3">数学</td><td>6</td><td>3</td><td>6</td><td>否</td></tr>
<tr><td></td><td>MA100</td><td>代数</td><td>3</td><td>3</td><td>3</td><td>A</td><td>是</td><td></td></tr>
<tr><td></td><td>MA101</td><td>分析</td><td>3</td><td>0</td><td>3</td><td>--</td><td>否</td><td>正在修读</td></tr>
<tr><td></td><td>MA102</td><td>概率</td><td>--</td><td>0</td><td>0</td><td>--</td><td>未修</td><td></td></tr>
</table><form action="myPlanCompl!compulsoryInfo.action"><input type="hidden" name="group.id" value="2"></form>''';
const catalog =
    '''<table><tr><th>课程类别</th><th>课程代码</th><th>课程名称</th><th>学分</th><th>建议修读学期</th><th>是否必修</th><th>开课院系</th></tr>
<tr><td>数学</td><td>MA100</td><td>代数</td><td>3</td><td>1</td><td>是</td><td>理学院</td></tr></table>
<form action="myPlan!exportPdf.action"><input type="hidden" name="planId" value="99"></form>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'parses EAMS nested groups, rowspan categories, missing credit figures and status in an isolate',
    () async {
      final plan = await compute(parseStudyPlan, (page: progress, detail: '', full: false));
      expect(plan.requiredCredits, 12);
      expect(plan.completionPercent, 25);
      final child = plan.categories.single.children.single;
      expect(child.depth, 1);
      expect(child.actual, 6);
      expect(child.met, isFalse);
      expect(child.courses.map((c) => c.status), [
        PlanCourseStatus.passed,
        PlanCourseStatus.studying,
        PlanCourseStatus.pending,
      ]);
      expect(child.courses.last.credits, isNull);
      final fullPlan = await compute(parseStudyPlan, (page: catalog, detail: '', full: true));
      final course = fullPlan.categories.single.courses.single;
      expect(
        (course.name, course.term, course.requiredCourse, course.department),
        ('代数', '1', true, '理学院'),
      );

      const rowspanHtml = '''<table>
        <tr><th>课程类别</th><th>课程代码</th><th>课程名称</th><th>学分</th><th>建议修读学期</th><th>是否必修</th><th>开课院系</th></tr>
        <tr><td rowspan="2">数学</td><td>MA100</td><td>代数</td><td>3</td><td>1</td><td>是</td><td>理学院</td></tr>
        <tr><td>MA101</td><td>分析</td><td>4</td><td>2</td><td>否</td><td>数学系</td></tr>
      </table>''';
      final spanned = await compute(parseStudyPlan, (page: rowspanHtml, detail: '', full: true));
      expect(spanned.categories.single.name, '数学');
      expect(spanned.categories.single.courses, hasLength(2));
      final second = spanned.categories.single.courses.last;
      expect(
        (second.code, second.name, second.credits, second.term, second.requiredCourse, second.department),
        ('MA101', '分析', 4.0, '2', false, '数学系'),
      );
    },
  );
  test(
    'lazy catalog and structured cache survive restart, reuse PDF form fields and clear cleanly',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final changes = ChangeNotifier();
      final fixture = CampusFixture('https://eams.shanghaitech.edu.cn', (request) {
        return switch (request.uri.path) {
          '/eams/myPlanCompl.action' => respond(progress),
          '/eams/myPlanCompl!compulsoryInfo.action' => respond(''),
          '/eams/myPlan.action' => respond(catalog),
          '/eams/myPlan!exportPdf.action' => respond(
              [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34],
            ),
          _ => throw StateError(request.uri.path),
        };
      });
      final eams = EamsClient(fixture.session, minInterval: Duration.zero);
      StudyPlanService open() => StudyPlanService(eams, storage, () => fixture.identity, changes);
      final first = open();
      await first.load();
      expect(fixture.requests.map((r) => r.uri.path), [
        '/eams/myPlanCompl.action',
        '/eams/myPlanCompl!compulsoryInfo.action',
      ]);
      expect(fixture.requests.last.data, {'group.id': '2'});
      await first.load(full: true);
      expect(fixture.requests.where((r) => r.uri.path == '/eams/myPlan.action'), hasLength(1));
      final pdf = await first.exportPdf();
      expect(pdf.take(5), [0x25, 0x50, 0x44, 0x46, 0x2d]);
      expect(fixture.requests.where((r) => r.uri.path == '/eams/myPlan.action'), hasLength(1));
      expect(fixture.requests.last.data, {'planId': '99'});
      first.dispose();
      final reopened = open();
      expect((await reopened.load(full: true)).categories.single.courses.single.code, 'MA100');
      expect(fixture.requests, hasLength(4));
      expect(prefs.getString('campus_cache_study_plan_catalog'), isNot(contains('<table>')));
      await storage.clearCampusCaches();
      expect(storage.studyPlanCache(false), isNull);
      expect(storage.studyPlanCache(true), isNull);
      await reopened.load(full: true);
      fixture.identity = (user: 'user', ids: 'second');
      changes.notifyListeners();
      expect(reopened.cached(full: false), isNull);
      expect(reopened.cached(full: true), isNull);
      expect(storage.studyPlanCache(false), isNull);
      expect(storage.studyPlanCache(true), isNull);
      reopened.dispose();
    },
  );
  test('corrupt persisted cache is ignored and cleared on startup', () async {
    SharedPreferences.setMockInitialValues({
      'campus_cache_study_plan_progress': '{not valid json',
      'campus_cache_study_plan_catalog': '{"owner":"[\\"user\\",\\"bound\\"]","snapshot":{"bad":1}}',
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) => respond(progress));
    final service = StudyPlanService(
      EamsClient(f.session, minInterval: Duration.zero),
      storage,
      () => f.identity,
      ChangeNotifier(),
    );
    expect(service.cached(full: false), isNull);
    expect(service.cached(full: true), isNull);
    expect(prefs.getString('campus_cache_study_plan_progress'), isNull);
    expect(prefs.getString('campus_cache_study_plan_catalog'), isNull);
    service.dispose();
  });
  testWidgets(
    'phone layout displays cached progress, filters course rows and switches to the catalog',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService(await SharedPreferences.getInstance());
      final f = CampusFixture(
        'https://eams.shanghaitech.edu.cn',
        (request) => throw StateError('offline'),
      );
      final owner = '["user","bound"]';
      for (final full in [false, true]) {
        final plan = parseStudyPlan((page: full ? catalog : progress, detail: '', full: full));
        await storage.saveStudyPlanCache(full, {'owner': owner, 'snapshot': plan.toJson()});
      }
      final service = StudyPlanService(
        EamsClient(f.session),
        storage,
        () => f.identity,
        ChangeNotifier(),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(home: StudyPlanPage(service: service)));
      await tester.pumpAndSettle();
      expect(find.text('已完成 3 / 12 学分'), findsOneWidget);
      await tester.tap(find.text('通识'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('数学'));
      await tester.pumpAndSettle();
      expect(find.text('代数'), findsOneWidget);
      await tester.tap(find.text('仅看未完成'));
      await tester.pumpAndSettle();
      expect(find.text('代数'), findsNothing);
      expect(find.text('分析'), findsOneWidget);
      await tester.tap(find.text('完整方案'));
      await tester.pumpAndSettle();
      expect(find.text('没有符合条件的课程或模块'), findsOneWidget);
      await tester.tap(find.text('仅看未完成'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'MA100');
      await tester.pumpAndSettle();
      expect(find.text('代数'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(f.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );
  test('unbound plan is an empty state and a non-PDF response fails export', () async {
    SharedPreferences.setMockInitialValues({});
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) => respond('<p>尚未绑定培养方案</p>'));
    final change = ChangeNotifier();
    final service = StudyPlanService(
      EamsClient(f.session, minInterval: Duration.zero),
      StorageService(await SharedPreferences.getInstance()),
      () => f.identity,
      change,
    );
    expect((await service.load()).categories, isEmpty);
    await expectLater(service.exportPdf(), throwsFormatException);
    expect(f.requests.last.method, 'POST');
    expect(f.requests.last.uri.path, '/eams/myPlan!exportPdf.action');
    service.dispose();
  });
}
