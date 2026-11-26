import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/campus_identity.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus/eams_schedule_parser.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

import '../support/eams_transport.dart';
import '../support/fake_ids_client.dart';

void main() {
  test('reads selected semester, project and student table id from the entry', () {
    final entry = EamsScheduleParser.entry('''<input name="project.id" value="2">
      <select name="semester.id"><option value="21">秋</option><option value="22" selected>春</option></select>
      <script>bg.form.addInput(form,"ids","31");</script>''');
    expect(entry, (table: '31', project: '2', semester: '22'));
    final terms = EamsScheduleParser.semesters(
      entry,
      '<select><option value="21">2025-2026 秋季</option><option value="22">2025–2026 春季</option></select>',
    );
    expect(terms.semesters, {
      '2025-2026': {'秋': '21', '春': '22'},
    });
    expect(terms.defaultSemester, '22');
    expect(terms.tableId, '31');

    final jsonTerms = EamsScheduleParser.semesters(
      entry,
      '{"id":"263","schoolYear":"2025 – 2026","name":"秋"}',
    );
    expect(jsonTerms.semesters, {
      '2025-2026': {'秋': '263'},
    });
  });

  test('merges repeated slots and keeps alternate weeks, multiple teachers and missing rooms', () {
    final table = EamsScheduleParser.timetable(
      '''<table><tr><th><font>1<br>08:15 - 09:00</font></th></tr></table>
    <script>var teachers=[{id:1,name:"Teacher A"},{id:2,name:"Teacher B"}];
    var activity = new TaskActivity(teachers.join(","),teachers.join(","),"CS100","算法(CS100.01)","23","Room","010101","");
    index = 0*unitCount+1;index=0*unitCount+0;index=0*unitCount+1;
    var teachers=[];activity = new TaskActivity("","","CS100","算法(CS100.01)","","","001010","");
    index=4*unitCount+1;</script>''',
    );
    expect(table.periods.single.timeRange, '08:15-09:00');
    final odd = table.courses.first, even = table.courses.last;
    expect(odd.name, '算法(CS100.01)');
    expect(odd.activeWeeks, [1, 3, 5]);
    expect(odd.teachers, 'Teacher A,Teacher B');
    expect(odd.times, {
      1: [1, 2],
    });
    expect(even.activeWeeks, [2, 4]);
    expect(even.classroom, isEmpty);
    expect(even.times, {
      5: [2],
    });
  });

  test('handles null room ids, binary-looking room ids, ); strings and unrelated name fields', () {
    final table = EamsScheduleParser.timetable('''
    <table id="courseTable"></table>
    <script>
      var meta = {name: "IgnoreMe"};
      var teachers = [{id: 1, name: "Prof. Lin"}];
      var activity = new TaskActivity(
        teachers.join(","),
        teachers.join(","),
        "CS200",
        "编译原理(CS200.01);(实验)",
        null,
        "1010",
        "011100",
        ""
      );
      index = 1 * unitCount + 2;
      var otherMeta = {name: "AlsoIgnore"};
      var teachers = [];
      activity = new TaskActivity(
        null,
        null,
        "CS201",
        "图形学(CS201.01)",
        "1010",
        "H201",
        "011000",
        ""
      );
      index = 2 * unitCount + 0;
    </script>''');
    expect(table.courses, hasLength(2));
    final first = table.courses.first;
    expect(first.name, '编译原理(CS200.01);(实验)');
    expect(first.classroom, '1010');
    expect(first.teachers, 'Prof. Lin');
    expect(first.activeWeeks, [1, 2, 3]);
    expect(first.times, {
      2: [3],
    });
    final second = table.courses.last;
    expect(second.name, '图形学(CS201.01)');
    expect(second.classroom, 'H201');
    expect(second.teachers, isEmpty);
    expect(second.activeWeeks, [1, 2]);
  });

  test('selects named exam batches and excludes unscheduled records', () {
    expect(EamsScheduleParser.batches(emptyExamBatches), isEmpty);
    expect(EamsScheduleParser.batches('<p>无考试安排</p>'), isEmpty);
    expect(EamsScheduleParser.exams('<p>没有考试</p>', '263', '1', '期末'), isEmpty);
    expect(
      EamsScheduleParser.batches(
        examBatches.replaceFirst('</select>', '<option value="2">期末</option></select>'),
      ),
      {'1222': '期中考试', '2': '期末'},
    );
    final exams = EamsScheduleParser.exams(examTable, '263', '1222', '期中');
    expect(exams.single.due, DateTime(2026, 4, 23, 15));
    expect(exams.single.id, '263:1222:CS130.01:7987');
    expect(exams.single.course, contains('座位 12'));
    expect(
      EamsScheduleParser.exams(examTable.replaceAll('15:00~16:40', '待定'), '263', '1', '期末'),
      isEmpty,
    );

    const combinedHtml = '''<table class="gridtable">
      <tr><th>课程代码</th><th>课程名称</th><th>考试时间</th><th>考试地点</th><th>考试座位</th></tr>
      <tr><td>CS300</td><td>机器学习</td><td>2026/05/08 09:00-11:00</td><td>信息学院 1B</td><td>A18</td></tr>
    </table>''';
    final combined = EamsScheduleParser.exams(combinedHtml, '263', '3', '期末').single;
    expect(combined.due, DateTime(2026, 5, 8, 9));
    expect(combined.lateDue, DateTime(2026, 5, 8, 11));
    expect(combined.location, '信息学院 1B');
    expect(combined.course, contains('座位 A18'));
  });

  test('fetchSemesters posts entry.semester rather than a hardcoded calendar id', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    await storage.saveSession(
      UserSession(
        userId: 'user',
        userName: 'User',
        schoolName: 'School',
        createdAt: DateTime.utc(2026),
      ),
    );
    await storage.saveThirdPartyAccount(FakeIdsClient.account('20240001'));
    await storage.setScheduleSource('20240001|20240001', CampusScheduleSource.undergraduate);
    final forms = <String>[];
    final server = MockClient((request) async {
      if (request.url.path == '/personalInfo/personCenter/index.html') {
        return http.Response('<html>IDS</html>', 200);
      }
      if (request.url.path == '/personalInfo/common/getUserConf') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': '0',
              'datas': {'uid': '20240001', 'categoryName': '学生/本科生'},
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path == '/eams/courseTableForStd.action') {
        return http.Response.bytes(
          utf8.encode(
            '<div id="semesterBar12345"></div><input name="ids" value="42">'
            '<input name="project.id" value="1"><input name="semester.id" value="263">',
          ),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      if (request.url.path == '/eams/dataQuery.action') {
        forms.add(request.body);
        return http.Response.bytes(
          utf8.encode(semesterOptions('2025-2026', '263')),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      return http.Response('not found', 404);
    });
    final httpClient = LoggingHttpClient(DebugLogger(), inner: server);
    final auth = AuthService(storage, httpClient, UniAuthService());
    final tpAuth = ThirdPartyAuthService(storage, httpClient, idsClient: FakeIdsClient());
    await auth.loadSession();
    await tpAuth.initialize();
    final schedule = ScheduleService(
      storage,
      httpClient,
      auth,
      tpAuth,
      eamsTransport: eamsTransport(server),
      eamsInterval: Duration.zero,
    );
    addTearDown(schedule.dispose);

    await schedule.fetchSemesters();
    expect(forms.single, contains('tagId=semesterBar12345Semester'));
    expect(forms.single, contains('value=263'));
    expect(forms.single, isNot(contains('value=6')));
  });
}
