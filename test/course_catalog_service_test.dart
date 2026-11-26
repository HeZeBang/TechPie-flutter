import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/pages/course_catalog_search_page.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/eams_client.dart';
import 'package:techpie/services/course_catalog_service.dart';
import 'package:techpie/services/storage_service.dart';

import 'campus/campus_fixture.dart';

const filters =
    '<select name="course.department.id"><option value="">全部</option><option value="3">数学</option></select>'
    '<select name="course.courseType.id"><option value="5">必修</option></select>';
const result =
    '<table class="gridtable"><thead><tr><th>学分</th><th>课程代码</th><th>课程名称</th><th>教师</th></tr></thead>'
    '<tbody><tr><td>3</td><td>CS101</td><td>Data &amp; Models</td><td>Demo</td></tr></tbody></table>';

String pageOfCourses(int count, {int start = 1}) {
  final rows = [
    for (var i = 0; i < count; i++)
      '<tr><td>CS${start + i}</td><td>Course ${start + i}</td><td>3</td><td>Demo</td></tr>',
  ].join();
  return '<table class="gridtable"><thead><tr><th>课程代码</th><th>课程名称</th><th>学分</th><th>教师</th></tr></thead>'
      '<tbody>$rows</tbody></table>';
}

void main() {
  test(
      'loads named dictionaries once, sends literal form values, paginates and clears history when switching accounts',
      () async {
    final f = CampusFixture(
      'https://eams.shanghaitech.edu.cn',
      (r) => respond(r.method == 'GET' ? filters : result),
    );
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final identity = ValueNotifier(0);
    final c = CourseCatalogService(
      EamsClient(f.session, minInterval: Duration.zero),
      storage,
      identity,
      ValueNotifier(0),
    );
    addTearDown(c.dispose);
    expect((await c.options())['course.department.id'], {'3': '数学'});
    expect((await c.options())['course.courseType.id'], {'5': '必修'});
    expect(f.requests.length, 1);
    final query = {'course.name': '数据 & 模型', 'course.department.id': '3'};
    final first = await c.search(query, 1);
    expect(first.single.name, 'Data & Models');
    expect(first.single.credits, '3');
    expect(first.single.teacher, 'Demo');
    await c.search(query, 2);
    expect(f.requests.last.data, {...query, 'pageNo': '2', 'pageSize': '20'});
    expect(c.history, ['数据 & 模型']);
    final previous = c.owner!;
    expect(jsonDecode(previous), ['user', 'bound']);
    await storage.clearCampusCaches();
    expect(c.history, isEmpty);
    await c.search(query, 1);
    expect(c.history, ['数据 & 模型']);
    f.identity = (user: 'next', ids: 'next');
    identity.value++;
    expect(c.history, isEmpty);
    expect(storage.catalogHistory(previous), isEmpty);
    await c.options();
    expect(f.requests.where((r) => r.method == 'GET'), hasLength(2));
  });

  test('parses short EAMS column aliases and separates empty vs unrecognized responses', () {
    const shortHeaders =
        '<table class="gridtable"><thead><tr><th>代码</th><th>名称</th><th>开课部门</th><th>类别</th><th>学分</th><th>课时</th><th>主讲教师</th></tr></thead>'
        '<tbody><tr><td>CS110</td><td>计算机体系结构</td><td>信息学院</td><td>专业必修</td><td>4</td><td>64</td><td>Prof. Wu</td></tr></tbody></table>';
    final parsed = CourseCatalogService.parseResults(shortHeaders).single;
    expect(parsed.code, 'CS110');
    expect(parsed.name, '计算机体系结构');
    expect(parsed.department, '信息学院');
    expect(parsed.type, '专业必修');
    expect(parsed.hours, '64');
    expect(parsed.teacher, 'Prof. Wu');
    expect(CourseCatalogService.parseResults('<div>暂无记录</div>'), isEmpty);
    expect(
      () => CourseCatalogService.parseResults('Unexpected error'),
      throwsA(isA<CampusRequestException>()),
    );
  });

  testWidgets('preserves filter controls across collapse and stops pagination on repeated page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) {
      if (r.method == 'GET') return respond(filters);
      return respond(pageOfCourses(CourseCatalogService.pageSize));
    });
    final service = CourseCatalogService(
      EamsClient(f.session, minInterval: Duration.zero, retryDelay: Duration.zero),
      storage,
      ChangeNotifier(),
      ChangeNotifier(),
    );
    addTearDown(service.dispose);

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: CourseCatalogSearchPage(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('筛选条件'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '学分'), '4');
    await tester.tap(find.text('不限').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('数学').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '学分'), findsOneWidget);

    // Collapse and re-expand the ExpansionTile without losing entered/selected filters.
    await tester.tap(find.text('筛选条件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('筛选条件'));
    await tester.pumpAndSettle();

    final creditField = tester.widget<TextField>(find.widgetWithText(TextField, '学分'));
    expect(creditField.controller?.text, '4');
    expect(find.text('数学'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Course 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('加载更多'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('加载更多'), findsOneWidget);

    // Tapping load more when EAMS repeats page 1 hides "加载更多" without duplicating rows.
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('加载更多'), findsNothing);
  });
}
