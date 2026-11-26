import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/campus_identity.dart';
import 'package:techpie/models/course.dart';
import 'package:techpie/models/course_table.dart';
import 'package:techpie/models/custom_course.dart';
import 'package:techpie/models/graduate_schedule.dart';
import 'package:techpie/models/ids_passkey.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/graduate_schedule_client.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/ics/ics_export_service.dart';
import 'package:techpie/services/ids/ids_client.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

import 'support/eams_transport.dart';
import 'support/fake_ids_client.dart';

Map<String, dynamic> fixture() => {
      'currentTerm': '20261',
      'currentTermName': '2026-2027学年秋季学期',
      'results': [
        {
          'XNXQDM': '20261',
          'XNXQMC': '2026-2027学年秋季学期',
          'BJDM': 'g1',
          'KCMC': '合成研究生课程',
          'XQ': 1,
          'KSJCDM': 1,
          'JSJCDM': 2,
          'ZCMC': '1-16周(单)',
          'JSXM': '示例教师',
          'JASMC': '示例教室',
          'JCFADM': 'A',
        },
        {
          'XNXQDM': '20261',
          'BJDM': 'g2',
          'KCMC': '合成研选本课程',
          'BYBZ': 0,
          'XQ': 3,
          'KSJCDM': 1,
          'JSJCDM': 2,
          'ZCMC': '2-16双周',
          'JCFADM': 'B',
        },
        {
          'XNXQDM': '20261',
          'BJDM': 'cancelled',
          'KCMC': '合成停开课程',
          'XQ': 2,
          'KSJCDM': 1,
          'JSJCDM': 2,
          'ZCMC': '1-16周',
          'JCFADM': 'A',
        },
      ],
      'skjcList': jsonEncode([
        for (final scheme in ['A', 'B']) ...[
          {
            'DM': 1,
            'MC': '第一节',
            'KSSJ': scheme == 'A' ? 815 : 900,
            'JSSJ': scheme == 'A' ? 900 : 945,
            'JCFADM': scheme,
          },
          {
            'DM': 2,
            'MC': '第二节',
            'KSSJ': scheme == 'A' ? 910 : 955,
            'JSSJ': scheme == 'A' ? 955 : 1040,
            'JCFADM': scheme,
          },
        ],
      ]),
      'xkjgList': [
        {'XNXQDM': '20261', 'BJDM': 'g1', 'KCMC': '合成研究生课程'},
        {'XNXQDM': '20261', 'BJDM': 'unarranged', 'KCMC': '合成未排课课程'},
      ],
      'ntkmdList': [
        {'XNXQDM': '20261', 'BJDM': 'cancelled', 'KCMC': '合成停开课程'},
      ],
      'mrjcfadm': 'A',
    };

const semester = 'graduate:20261';

Map<String, dynamic> fixtureWithStart() {
  final raw = fixture();
  final row = (raw['results'] as List).first as Map;
  row['ZCMC'] = '1周';
  row['RQ'] = '2026-09-07';
  return raw;
}

Map<String, dynamic> datedFixture() {
  final raw = fixture();
  final original = raw['results'] as List;
  raw['results'] = [
    {...original[0] as Map, 'ZCMC': '1-4周'},
    {...original[1] as Map, 'JCFADM': 'A', 'ZCMC': '1-4周'},
  ];
  raw['ntkmdList'] = <Object>[];
  raw['rqpkjgallList'] = [
    for (final date in ['2026-09-14', '2026-10-05'])
      {'bjdm': 'g1', 'kssj': '0815', 'jssj': '0955', 'rq': date},
    for (final date in ['2026-09-16', '2026-10-07'])
      {'bjdm': 'g2', 'kssj': '0815', 'jssj': '0955', 'rq': date},
  ];
  return raw;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = '20260001|20260001';

  test('graduate terms are namespaced; schemes retain their actual clock times', () {
    final schedule = GraduateSchedule.fromJson(fixture());
    expect(schedule.semesterInfo.defaultSemester, semester);
    expect(schedule.semesterInfo.semesters['2026-2027']!['秋'], semester);
    final a = schedule.tableFor(semester, 'A');
    final b = schedule.tableFor(semester, 'B');
    expect(a.periods.first.timeRange, '08:15-09:00');
    expect(b.periods.first.timeRange, '09:00-09:45');
    expect(a.courses.single.name, '合成研究生课程');
    expect(a.courses.single.isActiveInWeek(1), isTrue);
    expect(a.courses.single.isActiveInWeek(2), isFalse);
    expect(b.courses.single.name, '合成研选本课程');
    expect(b.courses.single.isActiveInWeek(2), isTrue);
    expect(schedule.unarrangedFor(semester).single['BJDM'], 'unarranged');
    expect(schedule.cancelledFor(semester).single['BJDM'], 'cancelled');
  });

  test('week parser handles Chinese separators and rejects partial parses', () {
    expect(graduateWeeks('第1～8周（单），10、12周'), [1, 3, 5, 7, 10, 12]);
    for (final value in ['', '1-16周,未知', '0-3周', '1-100周']) {
      expect(() => graduateWeeks(value), throwsFormatException);
    }
  });

  test('malformed responses and mismatched periods cannot become empty success', () {
    expect(() => GraduateSchedule.fromJson({'results': <Object>[]}), throwsFormatException);
    final raw = fixture();
    (raw['results'] as List).first['JSJCDM'] = 9;
    expect(() => GraduateSchedule.fromJson(raw).tableFor(semester, 'A'), throwsFormatException);
  });

  test('a current empty semester is retained and credentials are never cached', () {
    final raw = fixture()
      ..['results'] = <Object>[]
      ..['xkjgList'] = <Object>[]
      ..['ntkmdList'] = <Object>[];
    raw['csrfToken'] = 'must-not-persist';
    raw['xs'] = {'XH': 'private'};
    final snapshot = GraduateSchedule.fromJson(raw);
    expect(snapshot.semesterInfo.defaultSemester, semester);
    expect(snapshot.tableFor(semester, 'A').courses, isEmpty);
    expect(jsonEncode(snapshot.toJson()), isNot(contains('must-not-persist')));
    expect(snapshot.toJson().containsKey('xs'), isFalse);
  });

  test('term Monday is inferred only from unambiguous server dates', () {
    final raw = fixture();
    final row = (raw['results'] as List).first as Map;
    row['RQ'] = '2026-09-07';
    expect(GraduateSchedule.fromJson(raw).firstMondayFor(semester), isNull);
    row['ZCMC'] = '1周';
    expect(GraduateSchedule.fromJson(raw).firstMondayFor(semester), DateTime(2026, 9, 7));
  });

  test('explicit dates from cancelled classes do not determine the term start', () {
    final raw = fixture();
    final rows = raw['results'] as List;
    rows.last
      ..['ZCMC'] = '1周'
      ..['RQ'] = '2026-09-22';
    expect(GraduateSchedule.fromJson(raw).firstMondayFor(semester), isNull);

    rows.first
      ..['ZCMC'] = '1周'
      ..['RQ'] = '2026-09-07';
    expect(GraduateSchedule.fromJson(raw).firstMondayFor(semester), DateTime(2026, 9, 7));
  });

  test('explicit server dates override recurring weeks and preserve rescheduling', () {
    final raw = fixture();
    final row = (raw['results'] as List).first as Map;
    row['rqs'] = ['2026-09-07', '2026-09-22'];
    final schedule = GraduateSchedule.fromJson(raw);
    expect(schedule.firstMondayFor(semester), isNull);
    final table = schedule.tableFor(semester, 'A', firstMonday: DateTime(2026, 9, 7));
    expect(table.courses.length, 2);
    final monday = table.courses.singleWhere((c) => c.times.containsKey(1));
    final tuesday = table.courses.singleWhere((c) => c.times.containsKey(2));
    expect(monday.isActiveInWeek(1), isTrue);
    expect(monday.isActiveInWeek(3), isFalse);
    expect(tuesday.isActiveInWeek(3), isTrue);
    expect(
      () => schedule.tableFor(semester, 'A', firstMonday: DateTime(2026, 10, 5)),
      throwsFormatException,
    );
  });

  test('date-level records match only an unambiguous class and clock interval', () {
    final raw = fixture();
    raw['rqpkjgallList'] = [
      {
        'bjdm': 'g1',
        'kssj': '08:15',
        'jssj': '09:55',
        'rqs': ['2026-09-07', '2026-09-21'],
      },
    ];
    final table =
        GraduateSchedule.fromJson(raw).tableFor(semester, 'A', firstMonday: DateTime(2026, 9, 7));
    expect(table.courses.single.isActiveInWeek(1), isTrue);
    expect(table.courses.single.isActiveInWeek(3), isTrue);
    expect(table.courses.single.isActiveInWeek(5), isFalse);
  });

  test('real rq records establish one Monday despite missing holiday sessions', () {
    final snapshot = GraduateSchedule.fromJson(datedFixture());
    expect(snapshot.firstMondayFor(semester), DateTime(2026, 9, 14));
    final restored = GraduateSchedule.fromJson(snapshot.toJson());
    expect(restored.firstMondayFor(semester), DateTime(2026, 9, 14));
    final table = restored.tableFor(semester, 'A');
    expect(table.courses, hasLength(2));
    for (final course in table.courses) {
      expect(course.isActiveInWeek(1), isTrue);
      expect(course.isActiveInWeek(2), isFalse);
      expect(course.isActiveInWeek(3), isFalse);
      expect(course.isActiveInWeek(4), isTrue);
    }
  });

  test('partial, conflicting or single-class rq dates cannot silently set a Monday', () {
    final partial = datedFixture();
    partial['rqpkjgallList'] = [
      for (final date in ['2026-09-21', '2026-09-28'])
        {'bjdm': 'g1', 'kssj': '0815', 'jssj': '0955', 'rq': date},
      for (final date in ['2026-09-23', '2026-09-30'])
        {'bjdm': 'g2', 'kssj': '0815', 'jssj': '0955', 'rq': date},
    ];
    expect(GraduateSchedule.fromJson(partial).firstMondayFor(semester), isNull);
    final conflicting = datedFixture();
    (conflicting['rqpkjgallList'] as List)[3]['rq'] = '2026-10-14';
    expect(GraduateSchedule.fromJson(conflicting).firstMondayFor(semester), isNull);
    final single = datedFixture();
    (single['rqpkjgallList'] as List).removeWhere((r) => r['bjdm'] == 'g2');
    expect(GraduateSchedule.fromJson(single).firstMondayFor(semester), isNull);
  });

  test('split rows share date constraints and shifted weekdays do not shift the term', () {
    final raw = datedFixture();
    final rows = raw['results'] as List;
    final split = {...rows[0] as Map, 'ZCMC': '3-4周', 'JASMC': '后半学期教室'};
    rows[0]['ZCMC'] = '1-2周';
    rows.add(split);
    (raw['rqpkjgallList'] as List).add({
      'bjdm': 'g1',
      'kssj': '0815',
      'jssj': '0955',
      'rq': '2026-09-22',
    });
    final snapshot = GraduateSchedule.fromJson(raw);
    expect(snapshot.firstMondayFor(semester), DateTime(2026, 9, 14));
    final table = snapshot.tableFor(semester, 'A');
    final meetings = [
      for (final course in table.courses.where((c) => c.name == '合成研究生课程'))
        for (var week = 1; week <= 4; week++)
          if (course.isActiveInWeek(week)) (week, course.times.keys.single, course.classroom),
    ];
    expect(meetings, unorderedEquals([(1, 1, '示例教室'), (2, 2, '示例教室'), (4, 1, '后半学期教室')]));

    // All sessions of the second segment were cancelled in the dated calendar.
    (raw['rqpkjgallList'] as List)
        .removeWhere((r) => r['bjdm'] == 'g1' && r['rq'] == '2026-10-05');
    final partial = GraduateSchedule.fromJson(raw)
        .tableFor(semester, 'A', firstMonday: DateTime(2026, 9, 14));
    expect(partial.courses.map((course) => course.classroom), isNot(contains('后半学期教室')));
  });

  test('an ambiguous move preserves other dated meetings and cancelled weeks', () {
    final raw = datedFixture();
    final rows = raw['results'] as List;
    rows.add({...rows[0] as Map, 'XQ': 3, 'JASMC': '周三教室'});
    (raw['rqpkjgallList'] as List<Map<String, String>>).addAll([
      for (final date in ['2026-09-16', '2026-09-22', '2026-10-07'])
        {'bjdm': 'g1', 'kssj': '0815', 'jssj': '0955', 'rq': date},
    ]);

    final snapshot = GraduateSchedule.fromJson(raw);
    expect(snapshot.firstMondayFor(semester), DateTime(2026, 9, 14));
    final table = snapshot.tableFor(semester, 'A');
    final meetings = [
      for (final course in table.courses.where((c) => c.name == '合成研究生课程'))
        for (final week in course.activeWeeks) (week, course.times.keys.single, course.classroom),
    ];
    expect(
      meetings,
      unorderedEquals([
        (1, 1, '示例教室'),
        (1, 3, '周三教室'),
        (2, 2, ''),
        (4, 1, '示例教室'),
        (4, 3, '周三教室'),
      ]),
    );
  });

  test('explicit and date-level meetings coexist in either row order', () {
    final raw = fixture();
    final row = (raw['results'] as List<Map<String, dynamic>>).first;
    final explicit = {...row, 'RQ': '2026-09-07', 'JASMC': '周一教室'};
    final recurring = {...row, 'JASMC': '调课教室'};
    raw['rqpkjgallList'] = [
      {'bjdm': 'g1', 'kssj': '0815', 'jssj': '0955', 'rqs': ['2026-09-07', '2026-09-08']},
    ];
    for (final rows in [[explicit, recurring], [recurring, explicit]]) {
      final courses = GraduateSchedule.fromJson({...raw, 'results': rows})
          .tableFor(semester, 'A', firstMonday: DateTime(2026, 9, 7))
          .courses;
      expect(
        courses.map((course) => (course.dates!.single, course.classroom)),
        unorderedEquals([
          (DateTime.utc(2026, 9, 7), '周一教室'),
          (DateTime.utc(2026, 9, 8), '调课教室'),
        ]),
      );
    }
  });

  test('today and calendar export include dated courses from both period schemes', () async {
    final raw = fixture();
    for (final row in (raw['results'] as List).take(2)) {
      row['ZCMC'] = '';
      row['RQ'] = '2026-09-22';
    }
    final h = await harness(timetable: raw);
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    expect(h.schedule.termBegin, isNull);
    final exporter = IcsExportService();
    for (final scheme in ['A', 'B']) {
      await h.schedule.selectGraduateScheme(scheme);
      expect(h.schedule.courseTable!.courses, hasLength(1));
      final table = h.schedule.fullCourseTable!;
      final today = eamsToDisplayCourses(
        table.courses,
        0,
        timetablePeriods: table.periods.map((p) => p.toPeriod()).toList(),
        onDate: DateTime(2026, 9, 22),
      );
      expect(
        today.map((c) => (c.name, c.startTime, c.endTime)),
        unorderedEquals([
          ('合成研究生课程', '08:15', '09:55'),
          ('合成研选本课程', '09:00', '10:40'),
        ]),
      );
      final calendar = exporter.buildCalendar(table: table, termBegin: null);
      expect(calendar, contains('DTSTART;TZID=Asia/Shanghai:20260922T081500'));
      expect(calendar, contains('DTEND;TZID=Asia/Shanghai:20260922T104000'));
      final payloads = await exporter.buildCalendarEventPayloads(table: table, termBegin: null);
      expect(
        payloads.map((e) => (e['title'], e['startMillis'])),
        unorderedEquals([
          ('合成研究生课程', DateTime(2026, 9, 22, 8, 15).millisecondsSinceEpoch),
          ('合成研选本课程', DateTime(2026, 9, 22, 9).millisecondsSinceEpoch),
        ]),
      );
    }
  });

  test('graduate refresh automatically stores the inferred start without an EAMS request',
      () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    h.overrides['loadKbxx.do'] = http.Response(jsonEncode(datedFixture()), 200,
        headers: {'content-type': 'application/json; charset=utf-8'},);
    await h.schedule.fetchAll();
    expect(h.schedule.error, isNull);
    expect(h.schedule.termBegin, DateTime(2026, 9, 14));
    expect(h.storage.loadTermCalendar(semester)!.termBegin, DateTime(2026, 9, 14));
    expect(h.requests.any((r) => r.url.path.contains('/api/')), isFalse);
    expect(h.requests.any((r) => r.url.host == 'eams.shanghaitech.edu.cn'), isFalse);
    await h.storage.saveTermCalendar(
      semester,
      TermCalendar.fromJson({
        ...h.storage.loadTermCalendar(semester)!.toJson(),
        'termBegin': '2026-11-02',
      }),
    );
    await h.schedule.fetchAll();
    expect(h.schedule.error, isNull);
    expect(h.schedule.termBegin, DateTime(2026, 9, 14));
    expect(h.storage.loadTermCalendar(semester)!.termBegin, DateTime(2026, 9, 14));
  });

  test('the official protected entry establishes graduate cookies before API reads', () async {
    final requests = <http.Request>[];
    var authenticated = false;
    final logger = DebugLogger()..enabled = true;
    final client = GraduateScheduleClient(
      LoggingHttpClient(
        logger,
        inner: MockClient((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          expect(request.followRedirects, isFalse);
          if (request.url.host == GraduateScheduleClient.idsHost) {
            expect(request.headers['cookie'], contains('CASTGC=test-tgc'));
            return http.Response(
              '',
              302,
              headers: {
                'set-cookie': 'CASTGC=rotated-tgc; Domain=shanghaitech.edu.cn; Path=/; Secure',
                'location':
                    'https://${GraduateScheduleClient.host}${GraduateScheduleClient.base}*default/index.do?ticket=private-ticket',
              },
            );
          }
          expect(request.headers['cookie'] ?? '', isNot(contains('CASTGC')));
          if (request.url.path.endsWith('*default/index.do') &&
              request.url.queryParameters.containsKey('ticket')) {
            authenticated = true;
            return http.Response(
              '',
              302,
              headers: {
                'set-cookie': 'GS_SESSIONID=private-session; Path=/yjsxkapp; Secure',
                'location': '${GraduateScheduleClient.base}*default/index.do',
              },
            );
          }
          if (request.url.path.endsWith('*default/index.do') && !authenticated) {
            return http.Response(
              '',
              302,
              headers: {
                'location':
                    'https://${GraduateScheduleClient.idsHost}/authserver/login?service=test',
              },
            );
          }
          if (request.url.path.endsWith('*default/index.do')) {
            expect(request.headers['cookie'], contains('GS_SESSIONID=private-session'));
            return http.Response(
              '<html></html>',
              200,
              headers: {
                'set-cookie': '_WEU=private-weu; Path=/yjsxkapp; Secure',
              },
            );
          }
          expect(request.headers['cookie'], contains('GS_SESSIONID=private-session'));
          expect(request.headers['cookie'], contains('_WEU=private-weu'));
          expect(request.url.path, endsWith('loadKbxx.do'));
          expect(request.url.queryParameters, contains('_'));
          expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
          return http.Response(
            jsonEncode({
              'code': '1',
              'xs': {'XH': 'TEST'},
            }),
            200,
          );
        }),
      ),
      'test-tgc',
    );
    expect((await client.timetable())['code'], '1');
    expect(requests.length, 5);
    expect(logger.entries.map((e) => e.url).join(), isNot(contains('private-ticket')));
    final logs = logger.entries.map((e) => '${e.url} ${e.responseBody} ${e.error}').join();
    for (final private in [
      'private-ticket',
      'test-tgc',
      'rotated-tgc',
      'private-session',
      'private-weu',
      'TEST',
      'XH',
    ]) {
      expect(logs, isNot(contains(private)));
    }
    expect(jsonDecode(logger.entries.last.responseBody!)['format'], 'JSON');
  });

  test('redirects to write endpoints or other hosts are rejected before sending', () async {
    for (final target in [
      'https://unrelated.example/collect',
      'https://${GraduateScheduleClient.host}${GraduateScheduleClient.base}xsxkCourse/choiceCourse.do',
      'http://${GraduateScheduleClient.idsHost}/authserver/login',
    ]) {
      var sent = 0;
      final client = GraduateScheduleClient(
        LoggingHttpClient(
          DebugLogger(),
          inner: MockClient((request) async {
            sent++;
            return http.Response('', 302, headers: {'location': target});
          }),
        ),
        'test-tgc',
      );
      await expectLater(client.timetable(), throwsFormatException);
      expect(sent, 1);
    }
  });

  test('a matching graduate profile fetches no undergraduate schedule endpoints', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    expect(h.schedule.error, isNull);
    expect(h.schedule.isGraduate, isTrue);
    expect(h.schedule.courseTable!.courses.single.name, '合成研究生课程');
    expect(
      h.requests
          .where((r) => r.url.host == GraduateScheduleClient.host)
          .every((r) => r.method == 'GET'),
      isTrue,
    );
    expect(h.requests.any((r) => r.url.path.contains('/api/')), isFalse);
    expect(h.schedule.totalWeeks, greaterThanOrEqualTo(16));
    await h.schedule.selectGraduateScheme('B');
    expect(h.schedule.courseTable!.courses.single.name, '合成研选本课程');
    // A failed refresh must leave a usable previous result in hand.
    h.fail = true;
    await h.schedule.fetchAll();
    expect(h.schedule.error, isNotNull);
    expect(h.schedule.isGraduate, isTrue);
    expect(h.schedule.courseTable!.courses.single.name, '合成研选本课程');
    expect(h.requests.any((r) => r.url.path.contains('/api/')), isFalse);
  });

  test('an EMAP JSON loginURL is followed once before reading data, without writes', () async {
    var infoCalls = 0;
    var casCalls = 0;
    final client = GraduateScheduleClient(
      LoggingHttpClient(
        DebugLogger(),
        inner: MockClient((request) async {
          expect(request.method, 'GET');
          if (request.url.path.endsWith('*default/index.do')) {
            return http.Response('<html>entry</html>', 200);
          }
          if (request.url.host == GraduateScheduleClient.idsHost) {
            casCalls++;
            return http.Response(
              '',
              302,
              headers: {
                'location': 'https://${GraduateScheduleClient.host}/yjsxkapp/login?ticket=private',
              },
            );
          }
          if (request.url.path == '/yjsxkapp/login') {
            return http.Response(
              '<html>entry</html>',
              200,
              headers: {
                if (request.url.queryParameters.containsKey('ticket'))
                  'set-cookie': 'session=valid; Path=/yjsxkapp; Secure',
              },
            );
          }
          expect(request.url.path, endsWith('loadPublicInfo_course.do'));
          infoCalls++;
          return http.Response(
            jsonEncode(
              infoCalls == 1
                  ? {
                      'loginURL':
                          'https://${GraduateScheduleClient.idsHost}/authserver/login?service=graduate',
                    }
                  : {
                      'lcxxMap': {'XNXQDM': '20261'},
                    },
            ),
            200,
          );
        }),
      ),
      'test-tgc',
    );
    expect((await client.publicInfo())['lcxxMap'], {'XNXQDM': '20261'});
    expect(infoCalls, 2);
    expect(casCalls, 1);
  });

  test('a plain timetable 401 is not retried as though it were an API redirect', () async {
    var apiCalls = 0;
    final client = GraduateScheduleClient(
      LoggingHttpClient(
        DebugLogger(),
        inner: MockClient((request) async {
          if (request.url.path.endsWith('*default/index.do')) {
            return http.Response('<html>entry</html>', 200);
          }
          apiCalls++;
          return http.Response('{}', 401);
        }),
      ),
      'test-tgc',
    );
    await expectLater(
      client.timetable(),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('未认证'))),
    );
    expect(apiCalls, 1);
  });

  test('a failed authentication entry is shared across metadata and timetable reads', () async {
    var entryCalls = 0;
    final client = GraduateScheduleClient(
      LoggingHttpClient(
        DebugLogger(),
        inner: MockClient((request) async {
          expect(request.url.path, endsWith('*default/index.do'));
          entryCalls++;
          return http.Response('unavailable', 404);
        }),
      ),
      'test-tgc',
    );
    await expectLater(client.publicInfo(), throwsFormatException);
    await expectLater(client.timetable(), throwsFormatException);
    expect(entryCalls, 1);
  });

  test(
    'IDS undergraduate identity uses original requests without opening the graduate system',
    () async {
      final h = await harness(graduate: false);
      addTearDown(h.schedule.dispose);
      await h.schedule.fetchAll();
      expect(h.schedule.error, isNull);
      expect(h.schedule.isGraduate, isFalse);
      expect(h.schedule.selectedSemesterId, 'undergrad-term');
      expect(h.requests.any((r) => r.url.host == GraduateScheduleClient.host), isFalse);
      expect(h.requests.where((r) => _timetablePath(r.url.path)).map((r) => r.url.path).toList(), [
        '/eams/courseTableForStd.action',
        '/eams/dataQuery.action',
        '/eams/courseTableForStd!courseTable.action',
      ]);
      expect(
        h.requests.where((r) => r.url.path.endsWith('getSchoolCalendar.do')).map((r) => r.url.host),
        ['egate.shanghaitech.edu.cn'],
      );
    },
  );

  test('a profile with a different student id never opts this account in', () async {
    final h = await harness(profileSid: 'OTHER');
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    expect(h.schedule.error, contains('IDS 当前账号与学校绑定学号不一致'));
    expect(h.schedule.isGraduate, isFalse);
    expect(h.requests.any((r) => r.url.path.endsWith('loadKbxx.do')), isFalse);
    expect(h.requests.any((r) => _timetablePath(r.url.path)), isFalse);
  });

  test('IDS failure never silently falls back to undergraduate requests', () async {
    for (final response in [
      http.Response('missing', 404),
      http.Response('<html>login</html>', 200),
    ]) {
      final h = await harness();
      addTearDown(h.schedule.dispose);
      h.overrides['getUserConf'] = response;
      await h.schedule.fetchAll();
      expect(h.schedule.error, contains('身份识别失败'));
      expect(h.requests.every((r) => r.url.host == GraduateScheduleClient.idsHost), isTrue);
      expect(h.requests.where((r) => r.url.path.endsWith('getUserConf')), hasLength(1));
    }
  });

  test('unknown IDS categories require a source choice, not a guess', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    h.category = '教职工/教师';
    await h.schedule.fetchAll();
    expect(h.schedule.error, contains('手动选择课表来源'));
    expect(h.requests.every((r) => r.url.host == GraduateScheduleClient.idsHost), isTrue);
  });

  test('a broken optional semester endpoint does not discard a valid timetable', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    h.overrides['loadPublicInfo_course.do'] = http.Response('missing', 404);
    await h.schedule.fetchAll();
    expect(h.schedule.error, isNull);
    expect(h.schedule.courseTable!.courses.single.name, '合成研究生课程');
    expect(h.schedule.identityWarning, contains('loadPublicInfo_course.do'));
    expect(h.schedule.identityWarning, contains('404'));
    expect(h.requests.where((r) => r.url.path.endsWith('loadPublicInfo_course.do')), hasLength(1));
    h.overrides.remove('loadPublicInfo_course.do');
    await h.schedule.fetchAll();
    expect(h.schedule.error, isNull);
    expect(h.schedule.identityWarning, isNull);
  });

  test('a timetable 404 is reported once and preserves the last usable table', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    h.requests.clear();
    h.overrides['loadKbxx.do'] = http.Response('<html>not found</html>', 404);
    await h.schedule.fetchAll();
    expect(h.schedule.error, contains('loadKbxx.do'));
    expect(h.schedule.error, contains('404'));
    expect(h.schedule.courseTable!.courses.single.name, '合成研究生课程');
    expect(h.requests.where((r) => r.url.path.endsWith('loadKbxx.do')), hasLength(1));
    expect(h.requests.any((r) => _timetablePath(r.url.path)), isFalse);
    expect(h.requests.any((r) => r.url.path.endsWith('loadStdInfo.do')), isFalse);
  });

  test('local manual source choices bypass IDS and keep undergraduate routing intact', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    h.overrides['getUserConf'] = http.Response('missing', 404);
    await h.schedule.selectScheduleSource(CampusScheduleSource.graduate);
    expect(h.schedule.error, isNull);
    expect(h.schedule.isGraduate, isTrue);
    expect(h.requests.every((r) => r.url.host == GraduateScheduleClient.host), isTrue);
    h.requests.clear();
    await h.schedule.selectScheduleSource(CampusScheduleSource.undergraduate);
    expect(h.schedule.error, isNull);
    expect(h.schedule.isGraduate, isFalse);
    expect(h.schedule.selectedSemesterId, 'undergrad-term');
    expect(
      h.requests.any(
        (r) => [GraduateScheduleClient.idsHost, GraduateScheduleClient.host].contains(r.url.host),
      ),
      isFalse,
    );
    expect(h.storage.scheduleSourceFor('different-account'), CampusScheduleSource.automatic);
    expect(h.storage.selectedSemester, 'undergrad-term');
    final restarted = ScheduleService(h.storage, h.httpClient, h.auth, h.tp);
    addTearDown(restarted.dispose);
    await restarted.loadCachedData();
    expect(restarted.selectedSemesterId, 'undergrad-term');
    expect(restarted.courseTable!.courses, isEmpty);

    // Repair stale selections written by an older version at cache hydration.
    await h.storage.setSelectedSemester(semester);
    await restarted.loadCachedData();
    expect(restarted.isGraduate, isFalse);
    expect(restarted.selectedSemesterId, 'undergrad-term');
    expect(h.storage.selectedSemester, 'undergrad-term');
    expect(restarted.courseTable!.courses, isEmpty);
  });

  test('a failed source switch shows only the target timetable during and after refresh', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    await h.schedule.selectScheduleSource(CampusScheduleSource.graduate);
    h.overrides['courseTableForStd.action'] = http.Response('offline', 503);
    final switching = h.schedule.selectScheduleSource(CampusScheduleSource.undergraduate);
    expect(h.schedule.semesterInfo, isNull);
    expect(h.schedule.courseTable, isNull);
    expect(h.schedule.termCalendar, isNull);
    await switching;
    expect(h.schedule.error, isNotNull);
    expect(h.schedule.courseTable, isNull);
    final restarted = ScheduleService(h.storage, h.httpClient, h.auth, h.tp);
    addTearDown(restarted.dispose);
    await restarted.loadCachedData();
    expect(restarted.courseTable, isNull);

    h.overrides.remove('courseTableForStd.action');
    await h.schedule.fetchAll();
    await h.schedule.selectScheduleSource(CampusScheduleSource.graduate);
    h.overrides['courseTableForStd.action'] = http.Response('offline', 503);
    final cachedSwitch = h.schedule.selectScheduleSource(CampusScheduleSource.undergraduate);
    expect(h.schedule.selectedSemesterId, 'undergrad-term');
    expect(h.schedule.courseTable!.courses, isEmpty);
    await cachedSwitch;
    expect(h.schedule.error, isNotNull);
    expect(h.schedule.selectedSemesterId, 'undergrad-term');
    expect(h.schedule.courseTable!.courses, isEmpty);

    // A semester ID can be shared by two undergraduate accounts.
    await h.storage.saveCourseTable('undergrad-term', h.schedule.courseTable!, owner: 'other-user');
    await restarted.loadCachedData();
    expect(restarted.courseTable, isNull);
  });

  test('cached IDS identity belongs to one account and survives only availability failures',
      () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    expect(h.storage.loadCampusIdentity('different-account'), isNull);
    h.overrides['getUserConf'] = http.Response('missing', 404);
    final restored = ScheduleService(h.storage, h.httpClient, h.auth, h.tp);
    addTearDown(restored.dispose);
    await restored.fetchAll();
    expect(restored.error, isNull);
    expect(restored.isGraduate, isTrue);
    expect(restored.identityWarning, contains('沿用此账号已确认的身份'));
    h.overrides['getUserConf'] = http.Response(
      jsonEncode({
        'code': '0',
        'datas': {'uid': '20260002', 'categoryName': '学生/硕士生'},
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    final mismatched = ScheduleService(h.storage, h.httpClient, h.auth, h.tp);
    addTearDown(mismatched.dispose);
    h.requests.clear();
    await mismatched.fetchAll();
    expect(mismatched.error, contains('学号不一致'));
    expect(h.requests.every((r) => r.url.host == GraduateScheduleClient.idsHost), isTrue);
  });

  test('selected scheme and inferred start date survive a cached restart', () async {
    final h = await harness(timetable: fixtureWithStart());
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    await h.schedule.selectGraduateScheme('B');
    final restored = ScheduleService(h.storage, h.httpClient, h.auth, h.tp);
    addTearDown(restored.dispose);
    final before = h.requests.length;
    await restored.loadCachedData();
    expect(h.requests.length, before);
    expect(restored.graduateScheme, 'B');
    expect(restored.termBegin, DateTime(2026, 9, 7));
    expect(restored.courseTable!.courses.single.name, '合成研选本课程');
  });

  test('saved and legacy custom courses keep their times across graduate period schemes',
      () async {
    final h = await harness(timetable: fixtureWithStart());
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    const selectedByPeriod = CustomCourse(
      id: 'recitation',
      name: '习题课',
      weekdays: [1],
      weeks: [1],
      time: PeriodCourseTime(startPeriod: 1, endPeriod: 1),
    );
    const legacy = CustomCourse(
      id: 'legacy',
      name: '已有课程',
      weekdays: [1],
      weeks: [1],
      time: PeriodCourseTime(startPeriod: 2, endPeriod: 2),
    );
    await h.storage.saveCustomCourses(semester, [legacy], owner: owner);
    await h.schedule.saveCustomCourse(semester, selectedByPeriod);

    final exporter = IcsExportService();
    for (final scheme in ['A', 'B']) {
      await h.schedule.selectGraduateScheme(scheme);
      final table = h.schedule.fullCourseTable!;
      final periods = table.periods.map((p) => p.toPeriod()).toList();
      final courses = h.schedule.customCourses;
      expect(
        withCustomCourses([], courses, 1, h.schedule.termBegin, periods: periods)
            .map((course) => (course.name, course.startTime, course.endTime)),
        unorderedEquals([('习题课', '08:15', '09:00'), ('已有课程', '09:10', '09:55')]),
      );
      final events = await exporter.buildCalendarEventPayloads(
        table: CourseTable(periods: table.periods, courses: []),
        termBegin: h.schedule.termBegin,
        customCourses: courses,
      );
      expect(
        events.map((event) => event['startMillis']),
        unorderedEquals([
          DateTime(2026, 9, 7, 8, 15).millisecondsSinceEpoch,
          DateTime(2026, 9, 7, 9, 10).millisecondsSinceEpoch,
        ]),
      );
    }
  });

  test('graduate custom courses stay with their IDS accounts across rebinds', () async {
    final h = await harness(timetable: fixtureWithStart());
    addTearDown(h.schedule.dispose);
    const course = CustomCourse(
      id: 'recitation',
      name: '习题课',
      weekdays: [1],
      weeks: [1],
      time: PeriodCourseTime(startPeriod: 1, endPeriod: 1),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schedule_custom_courses_$semester', jsonEncode([course.toJson()]));
    await h.schedule.fetchAll();
    expect(h.schedule.selectedSemesterId, semester);
    expect(h.schedule.customCourses, isEmpty);
    await h.schedule.saveCustomCourse(semester, course);

    await h.storage.setScheduleSource('20260002|20260002', CampusScheduleSource.graduate);
    await h.tp.bindIds(
      account: '20260002',
      password: 'synthetic',
      promptCaptcha: (_, __, {required refresh}) async => null,
    );
    await h.schedule.fetchAll();
    expect(h.schedule.selectedSemesterId, semester);
    expect(h.schedule.customCourses, isEmpty);
    await h.schedule.saveCustomCourse(semester, course);
    await h.schedule.deleteCustomCourse(semester, course.id);
    expect(h.schedule.customCourses, isEmpty);

    await h.tp.bindIds(
      account: '20260001',
      password: 'synthetic',
      promptCaptcha: (_, __, {required refresh}) async => null,
    );
    await h.schedule.fetchAll();
    expect(h.schedule.customCourses.single.id, course.id);
  });

  test('published graduate calendars store the teaching and exam weeks for both terms',
      () async {
    const terms = ['20251', '20252'];
    final raw = fixture();
    raw['results'] = <Map<String, dynamic>>[];
    raw['xkjgList'] = [
      for (var i = 0; i < terms.length; i++)
        {
          'XNXQDM': terms[i],
          'XNXQMC': '2025-2026学年 第${i == 0 ? '一' : '二'}学期',
          'BJDM': 'history-$i',
          'PKSJDD': '1-16周 星期一[1节]历史教室',
        },
    ];
    final h = await harness(timetable: raw);
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    for (final term in terms) {
      final id = 'graduate:$term';
      await h.schedule.selectSemester(id);
      expect(h.schedule.termCalendar?.allTeachWeeks, 16);
      expect(h.schedule.totalWeeks, 18);
      expect(h.storage.loadTermCalendar(id)?.allTermWeeks, 18);
    }
  });

  test('a cached graduate term never reaches EAMS even before identity hydration', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    await h.storage.setSelectedSemester(semester);
    final assignments = AssignmentService(h.storage, h.httpClient, h.auth, h.tp, h.schedule);
    addTearDown(assignments.dispose);
    await assignments.fetchPlatform('exam');
    expect(h.requests, isEmpty);
  });

  test('a confirmed graduate never queries EAMS exams even when its first timetable fails',
      () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    await h.storage.setSelectedSemester('undergrad-term');
    h.overrides['loadKbxx.do'] = http.Response('missing', 404);
    await h.schedule.fetchAll();
    expect(h.schedule.hasGraduateIdentity, isTrue);
    final assignments = AssignmentService(h.storage, h.httpClient, h.auth, h.tp, h.schedule);
    addTearDown(assignments.dispose);
    h.requests.clear();
    await assignments.fetchPlatform('exam');
    expect(h.requests, isEmpty);
  });

  test('a restored Passkey obtains an IDS session before reading graduate identity', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    await h.tp.updateRaw(ThirdPartyPlatform.ids, {'cookies': ''});
    expect(h.tp.idsNode.rawFields['tgc'], isNull);
    await h.schedule.fetchAll();
    expect(h.schedule.error, isNull);
    expect(h.schedule.isGraduate, isTrue);
    expect(h.tp.idsNode.rawFields['tgc'], 'tgc-value');
    expect(h.requests.any((r) => r.url.path.endsWith('getUserConf')), isTrue);
    expect(h.requests.any((r) => r.url.path.endsWith('loadKbxx.do')), isTrue);
  });

  for (final graduate in [true, false]) {
    test('startup exam fetching waits for IDS classification (graduate=$graduate)', () async {
      final h = await harness(graduate: graduate);
      addTearDown(h.schedule.dispose);
      await h.storage.setSelectedSemester('undergrad-term');
      h.identityGate = Completer<void>();
      h.overrides['stdExamTable.action'] = http.Response(emptyExamBatches, 200);
      final assignments = AssignmentService(h.storage, h.httpClient, h.auth, h.tp, h.schedule);
      addTearDown(assignments.dispose);
      h.schedule.requestFetch(force: true);
      final exams = assignments.fetchPlatform('exam');
      await h.identityEntered.future.timeout(const Duration(seconds: 3));
      final earlyExams = h.requests
          .where((r) => r.url.path.endsWith('/stdExamTable.action'))
          .toList();
      final scheduleDone = Completer<void>();
      h.schedule.addListener(() {
        if (!h.schedule.loading && !scheduleDone.isCompleted) scheduleDone.complete();
      });
      h.identityGate!.complete();
      await Future.wait([exams, scheduleDone.future]);
      expect(earlyExams, isEmpty);
      expect(
        h.requests.where((r) => r.url.path.endsWith('/stdExamTable.action')),
        hasLength(graduate ? 0 : 1),
      );
      expect(h.requests.where((r) => r.url.path.endsWith('/getUserConf')), hasLength(1));
      expect(assignments.platformErrors, isEmpty);
    });
  }

  test('an unresolved identity never sends a cached undergraduate semester to EAMS', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    await h.storage.setSelectedSemester('undergrad-term');
    h.overrides['getUserConf'] = http.Response('offline', 503);
    final assignments = AssignmentService(h.storage, h.httpClient, h.auth, h.tp, h.schedule);
    addTearDown(assignments.dispose);
    await assignments.fetchPlatform('exam');
    expect(h.requests.any((r) => r.url.path.endsWith('/stdExamTable.action')), isFalse);
    expect(h.requests.any((r) => r.url.path.endsWith('/eams')), isFalse);
  });

  test('confirmed cached undergraduate identity permits exams when IDS is unavailable', () async {
    final h = await harness(graduate: false);
    addTearDown(h.schedule.dispose);
    await h.storage.saveCampusIdentity(
      '20260001|20260001', CampusIdentity.fromCategory('学生/本科生'),
    );
    h.overrides['getUserConf'] = http.Response('offline', 503);
    h.overrides['stdExamTable.action'] = http.Response(emptyExamBatches, 200);
    final assignments = AssignmentService(h.storage, h.httpClient, h.auth, h.tp, h.schedule);
    addTearDown(assignments.dispose);
    await assignments.fetchPlatform('exam');
    expect(h.requests.where((r) => r.url.path.endsWith('/stdExamTable.action')), hasLength(1));
    expect(assignments.platformErrors, isEmpty);
    h.overrides['getUserConf'] = http.Response(
      jsonEncode({'code': '0', 'datas': {'uid': 'different-account', 'categoryName': '学生/本科生'}}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    await h.schedule.fetchAll();
    h.requests.clear();
    await assignments.fetchPlatform('exam');
    expect(h.requests.any((r) => r.url.path.endsWith('/stdExamTable.action')), isFalse);
  });

  test('a new campus account fetches once after the previous account finishes', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    h.tableGate = Completer<void>();
    final oldFetch = h.schedule.fetchAll();
    await h.tableEntered.future;

    const owner = '20260002|20260002';
    await h.storage.setScheduleSource(owner, CampusScheduleSource.graduate);
    await h.tp.bindIds(
      account: '20260002', password: 'synthetic',
      promptCaptcha: (_, __, {required refresh}) async => null,
    );
    // Let B's debounce expire while A is still waiting for the timetable.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final refreshed = Completer<void>();
    h.schedule.addListener(() {
      if (!h.schedule.loading && h.storage.graduateScheduleOwner == owner && !refreshed.isCompleted) {
        refreshed.complete();
      }
    });
    h.tableGate!.complete();
    h.tableGate = null;
    await oldFetch;
    await refreshed.future.timeout(const Duration(seconds: 3));
    h.schedule.requestFetch(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(h.requests.where((r) => r.url.path.endsWith('/loadKbxx.do')), hasLength(2));
    expect(h.schedule.error, isNull);
  });

  test('an unbind discards a late graduate response instead of caching it', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    h.tableGate = Completer<void>();
    final pending = h.schedule.fetchAll();
    await h.tableEntered.future;
    await h.tp.unbind(ThirdPartyPlatform.ids);
    h.tableGate!.complete();
    await pending;
    expect(h.schedule.courseTable, isNull);
    expect(h.schedule.semesterInfo, isNull);
    expect(h.storage.graduateScheduleOwner, isNull);
  });

  test('parent-domain cookies stay within the origin that issued them', () async {
    final log = LoggingHttpClient(
      DebugLogger(),
      inner: MockClient((request) async {
        final cookie = request.headers['cookie'] ?? '';
        if (request.url.host == GraduateScheduleClient.idsHost) {
          expect(cookie, isNot(contains('graduate-secret')));
          if (request.url.path.endsWith('index.html')) {
            return http.Response(
              '<html>IDS</html>',
              200,
              headers: {
                'set-cookie': 'SESSION=ids-secret; Domain=shanghaitech.edu.cn; Path=/; Secure',
              },
            );
          }
          expect(cookie, contains('SESSION=ids-secret'));
          return http.Response(
            jsonEncode({
              'code': '0',
              'datas': {'uid': '20260001', 'categoryName': '学生/硕士生'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        expect(cookie, isNot(contains('ids-secret')));
        if (request.url.path.endsWith('loadKbxx.do')) {
          expect(cookie, contains('SESSION=graduate-secret'));
          return http.Response(jsonEncode(fixture()), 200,
              headers: {'content-type': 'application/json; charset=utf-8'},);
        }
        return http.Response(
          '<html>graduate</html>',
          200,
          headers: {
            'set-cookie': 'SESSION=graduate-secret; Domain=shanghaitech.edu.cn; Path=/; Secure',
          },
        );
      }),
    );
    addTearDown(log.close);
    final client = GraduateScheduleClient(log, 'bound');
    await client.identity('20260001');
    await client.timetable();
    await client.identity('20260001');
  });

  for (final rawTgc in [null, 'stale-raw']) {
    test('the authoritative IDS cookie supplies CASTGC when raw tgc is $rawTgc', () async {
      final h = await harness();
      addTearDown(h.schedule.dispose);
      await h.tp.updateRaw(ThirdPartyPlatform.ids, {
        'cookies': 'SESSION=reference; CASTGC=header-session',
        if (rawTgc != null) 'tgc': rawTgc,
      });
      await h.schedule.fetchAll();
      expect(h.schedule.error, isNull);
      expect(h.schedule.isGraduate, isTrue);
      final requests = h.requests.where((r) => r.url.host == GraduateScheduleClient.idsHost);
      expect(requests, isNotEmpty);
      for (final request in requests) {
        expect(request.headers['cookie'], contains('CASTGC=header-session'));
        expect(request.headers['cookie'], isNot(contains('stale-raw')));
      }
    });
  }

  for (final graduate in [false, true]) {
    test('a changed IDS session revalidates the principal (graduate=$graduate)', () async {
      final h = await harness(graduate: graduate);
      addTearDown(h.schedule.dispose);
      await h.schedule.fetchAll();
      final previous = h.schedule.courseTable;
      h.overrides['getUserConf'] = http.Response(
        jsonEncode({'code': '0', 'datas': {'uid': '20260002', 'categoryName': '学生/硕士生'}}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      h.overrides['stdExamTable.action'] = http.Response(emptyExamBatches, 200);
      await h.tp.updateRaw(ThirdPartyPlatform.ids, {'tgc': 'rotated-session'});
      expect(h.schedule.courseTable, same(previous));
      h.requests.clear();
      final assignments = AssignmentService(h.storage, h.httpClient, h.auth, h.tp, h.schedule);
      addTearDown(assignments.dispose);
      if (graduate) {
        await h.schedule.fetchAll();
      } else {
        await assignments.fetchPlatform('exam');
      }
      expect(h.schedule.error, contains('学号不一致'));
      expect(h.requests.where((r) => r.url.path.endsWith('getUserConf')), hasLength(1));
      expect(h.requests.any((r) => r.url.path.endsWith('stdExamTable.action')), isFalse);
      expect(h.requests.any((r) => r.url.host == GraduateScheduleClient.host), isFalse);
      expect(h.storage.loadCampusIdentity(owner), isNull);
      h.overrides['getUserConf'] = http.Response('offline', 503);
      h.requests.clear();
      await assignments.fetchPlatform('exam');
      expect(h.requests.any((r) => r.url.path.endsWith('stdExamTable.action')), isFalse);
    });
  }

  test('a renewed IDS session is revalidated before the EAMS exam request', () async {
    final h = await harness(graduate: false);
    addTearDown(h.schedule.dispose);
    await h.tp.updateRaw(ThirdPartyPlatform.ids, {'tgc': 'old-session'});
    await h.schedule.fetchAll();
    h.overrides['getUserConf'] = http.Response(
      jsonEncode({'code': '0', 'datas': {'uid': '20260002', 'categoryName': '学生/硕士生'}}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    h.overrides['stdExamTable.action'] = http.Response(emptyExamBatches, 200);
    h.tp.idsNode.seedNextRenewTimestamp(DateTime(2020));
    h.requests.clear();
    final assignments = AssignmentService(h.storage, h.httpClient, h.auth, h.tp, h.schedule);
    addTearDown(assignments.dispose);
    await assignments.fetchPlatform('exam');
    expect(h.tp.idsNode.rawFields['tgc'], 'tgc-value');
    expect(h.schedule.error, contains('学号不一致'));
    expect(h.requests.any((r) => r.url.path.endsWith('stdExamTable.action')), isFalse);
  });

  test('a failed IDS renewal does not queue another timetable login', () async {
    final ids = _FailingIdsClient();
    final h = await harness(graduate: false, idsClient: ids);
    addTearDown(h.schedule.dispose);
    await h.tp.updateRaw(ThirdPartyPlatform.ids, {});
    h.tp.onBindingsChanged = ({force = false}) async {
      h.schedule.requestFetch();
    };
    final failed = Completer<void>();
    h.schedule.addListener(() {
      if (!h.schedule.loading && h.schedule.error != null && !failed.isCompleted) {
        failed.complete();
      }
    });
    h.schedule.requestFetch(force: true);
    await failed.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 750));
    expect(ids.loginAttempts, 1);
    await h.schedule.fetchAll();
    expect(ids.loginAttempts, 2);
  });

  for (final endpoint in ['courseTableForStd.action', 'courseTableForStd!courseTable.action']) {
    test('rotating IDS during $endpoint discards the old undergraduate response', () async {
      final h = await harness(graduate: false);
      addTearDown(h.schedule.dispose);
      await h.schedule.fetchAll();
      final cachedTable = h.schedule.courseTable;
      final cachedSemesters = h.schedule.semesterInfo;
      h.requests.clear();

      h.pausedEamsEndpoint = endpoint;
      final pending = h.schedule.fetchAll();
      await h.eamsEntered.future;
      await h.tp.updateRaw(ThirdPartyPlatform.ids, {'tgc': 'rotated-session'});
      h.resumeEams.complete();
      await pending;

      expect(h.schedule.error, contains('IDS 会话'));
      expect(h.schedule.courseTable, same(cachedTable));
      if (endpoint == 'courseTableForStd.action') {
        expect(h.schedule.semesterInfo, same(cachedSemesters));
        expect(
          h.requests.where((r) => _timetablePath(r.url.path)).map((r) => r.url.pathSegments.last),
          ['courseTableForStd.action'],
        );
      }

      h.requests.clear();
      h.overrides['getUserConf'] = http.Response(
        jsonEncode({
          'code': '0',
          'datas': {'uid': '20260002', 'categoryName': '学生/本科生'},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      await h.schedule.fetchAll();
      expect(h.schedule.error, contains('学号不一致'));
      expect(h.requests.any((r) => _timetablePath(r.url.path)), isFalse);
    });
  }

  test('manual source preferences are independent and recognize the legacy owner', () async {
    SharedPreferences.setMockInitialValues({
      'schedule_source_preference': jsonEncode({'owner': 'a', 'source': 'graduate'}),
    });
    final storage = StorageService(await SharedPreferences.getInstance());
    await storage.setScheduleSource('b', CampusScheduleSource.undergraduate);
    expect(storage.scheduleSourceFor('a'), CampusScheduleSource.graduate);
    expect(storage.scheduleSourceFor('b'), CampusScheduleSource.undergraduate);
    await storage.setScheduleSource('a', CampusScheduleSource.automatic);
    expect(storage.scheduleSourceFor('a'), CampusScheduleSource.automatic);
    expect(storage.scheduleSourceFor('b'), CampusScheduleSource.undergraduate);
  });

  test('a changed IDS session discards an in-flight identity response', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    h.identityGate = Completer<void>();
    final pending = h.schedule.fetchAll();
    await h.identityEntered.future;
    await h.tp.updateRaw(ThirdPartyPlatform.ids, {'tgc': 'rotated-session'});
    h.identityGate!.complete();
    await pending;
    expect(h.schedule.courseTable, isNull);
    expect(h.storage.loadGraduateSchedule(), isNull);
    expect(h.storage.loadCampusIdentity(owner), isNull);
    expect(h.requests.any((r) => r.url.host == GraduateScheduleClient.host), isFalse);
  });

  test('IDS response cookies rotate within the client and stay off the graduate host', () async {
    const ids = GraduateScheduleClient.idsHost;
    const graduate = GraduateScheduleClient.host;
    var idsVisits = 0;
    final log = LoggingHttpClient(
      DebugLogger(),
      inner: MockClient((request) async {
        final uri = request.url;
        if (uri.host == ids) {
          expect(
            request.headers['cookie'],
            contains('CASTGC=${idsVisits == 0 ? 'bound' : 'rotated'}'),
          );
          idsVisits++;
          if (uri.path.endsWith('index.html')) {
            return http.Response(
              '<html>IDS</html>',
              200,
              headers: {'set-cookie': 'CASTGC=rotated; Path=/; Secure'},
            );
          }
          if (uri.path.endsWith('getUserConf')) {
            return http.Response(
              jsonEncode({
                'code': '0',
                'datas': {'uid': '20260001', 'categoryName': '学生/硕士生'},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://$graduate${GraduateScheduleClient.base}*default/index.do?ticket=test',
            },
          );
        }
        expect(uri.host, graduate);
        expect(request.headers['cookie'] ?? '', isNot(contains('CASTGC')));
        if (uri.path.endsWith('loadKbxx.do')) {
          return http.Response(
            jsonEncode(fixture()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (uri.hasQuery) {
          return http.Response(
            '<html>course</html>',
            200,
            headers: {'set-cookie': 'CASTGC=foreign; Path=/; Secure'},
          );
        }
        return http.Response('', 302, headers: {'location': 'https://$ids/authserver/login'});
      }),
    );
    addTearDown(log.close);
    final client = GraduateScheduleClient(log, 'bound');
    await client.identity('20260001');
    await client.timetable();
    expect(idsVisits, 3);
    expect(client.tgc, 'bound');
  });

  for (final removal in [
    'unbind',
    'clearAll',
    'replaceAll',
    'syncRemove',
    'replaceAccount',
    'syncAccount',
    'rebindSameAccount',
  ]) {
    test('$removal removes graduate caches before the same account is rebound', () async {
      final h = await harness(timetable: fixtureWithStart());
      addTearDown(h.schedule.dispose);
      await h.schedule.fetchAll();
      await h.schedule.selectGraduateScheme('B');
      final prefs = await SharedPreferences.getInstance();
      final snapshot = GraduateSchedule.fromJson(fixture());
      await prefs.setString('graduate_schedule', jsonEncode(snapshot.toJson()));
      await prefs.setString('graduate_schedule_owner', owner);
      await h.storage.saveSemesters(snapshot.semesterInfo, owner: owner);
      await h.storage
          .saveCourseTable('undergrad-term', const CourseTable(periods: [], courses: []));
      switch (removal) {
        case 'unbind':
          await h.tp.unbind(ThirdPartyPlatform.ids);
        case 'clearAll':
          await h.tp.clearAll();
        case 'replaceAll':
          await h.tp.replaceAll([]);
        case 'syncRemove':
          await h.tp.applyIdsSyncBinding(
            IdsSyncBinding(credential: null, updatedAt: DateTime.now(), deviceId: 'fixture'),
          );
        case 'replaceAccount':
          await h.tp.bindIds(
            account: '20260002',
            password: 'synthetic',
            promptCaptcha: (_, __, {required refresh}) async => null,
          );
        case 'syncAccount':
          await h.tp.applyIdsSyncBinding(
            IdsSyncBinding(
              credential: FakeIdsClient.key('20260002'),
              updatedAt: DateTime.now(),
              deviceId: 'fixture',
            ),
          );
        case 'rebindSameAccount':
          await h.tp.bindIds(
            account: '20260001',
            password: 'synthetic',
            promptCaptcha: (_, __, {required refresh}) async => null,
          );
      }
      await h.schedule.loadCachedData();
      expect(h.schedule.courseTable, isNull);
      expect(h.schedule.courseTableFor(semester), isNull);
      expect(h.storage.graduateScheduleOwner, isNull);
      expect(h.storage.loadGraduateSchedule(), isNull);
      expect(prefs.getString('graduate_schedule_owner'), isNull);
      expect(h.storage.loadCourseTable(semester, owner: owner), isNull);
      expect(h.storage.loadTermCalendar(semester), isNull);
      expect(h.storage.graduateSchemeFor(semester), isNull);
      expect(h.storage.selectedSemester, isNull);
      expect(h.storage.loadSemesters(), isNull);
      expect(h.storage.loadCourseTable('undergrad-term'), isNotNull);
      await h.tp.bindIds(
        account: '20260001',
        password: 'synthetic',
        promptCaptcha: (_, __, {required refresh}) async => null,
      );
      await h.schedule.loadCachedData();
      expect(h.schedule.courseTable, isNull);
      h.requests.clear();
      await h.schedule.fetchAll();
      expect(h.schedule.courseTable!.courses, isNotEmpty);
      expect(h.requests.any((r) => r.url.path.endsWith('loadKbxx.do')), isTrue);
    });
  }

  test('startup clears graduate caches left by an older unbound installation', () async {
    final h = await harness();
    await h.schedule.fetchAll();
    h.schedule.dispose();
    await h.storage.clearThirdPartyAccount(ThirdPartyPlatform.ids);
    final tp = ThirdPartyAuthService(h.storage, h.httpClient);
    await tp.initialize();
    addTearDown(tp.dispose);
    final schedule = ScheduleService(h.storage, h.httpClient, h.auth, tp);
    addTearDown(schedule.dispose);
    await schedule.loadCachedData();
    expect(h.storage.loadGraduateSchedule(), isNull);
    expect(h.storage.loadCourseTable(semester, owner: owner), isNull);
    expect(h.storage.selectedSemester, isNull);
    expect(schedule.courseTable, isNull);
  });

  test('all graduate table writes carry ownership, including non-selected semesters', () async {
    final h = await harness(timetable: fixtureWithStart());
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    void checkOwner() {
      expect(h.storage.loadCourseTable(semester, owner: owner), isNotNull);
      expect(h.storage.loadCourseTable(semester, owner: 'another-account'), isNull);
    }

    checkOwner();
    await h.tp.unbind(ThirdPartyPlatform.gradescope);
    checkOwner();
    await h.schedule.selectGraduateScheme('B');
    checkOwner();
    await h.schedule.fetchCourseTable(semester);
    checkOwner();
    const otherSemester = 'graduate:20262';
    await h.storage.saveCourseTable(otherSemester, h.schedule.courseTable!, owner: owner);
    expect(h.schedule.courseTableFor(otherSemester), isNotNull);
    await h.tp.unbind(ThirdPartyPlatform.ids);
    expect(h.schedule.courseTableFor(semester), isNull);
    expect(h.schedule.courseTableFor(otherSemester), isNull);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'schedule_course_table_$semester',
      jsonEncode(
        const CourseTable(
          periods: [],
          courses: [],
        ).toJson(),
      ),
    );
    expect(h.storage.loadCourseTable(semester, owner: owner), isNull);
    await prefs.setString(
      'schedule_course_table_legacy-undergrad',
      jsonEncode(const CourseTable(periods: [], courses: []).toJson()),
    );
    expect(h.storage.loadCourseTable('legacy-undergrad', owner: owner), isNotNull);
  });

  test('graduate snapshots read legacy owners and save owner and response together', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    final prefs = await SharedPreferences.getInstance();
    final snapshot = GraduateSchedule.fromJson(fixture());
    await prefs.setString('graduate_schedule', jsonEncode(snapshot.toJson()));
    await prefs.setString('graduate_schedule_owner', owner);
    expect(h.storage.graduateScheduleOwner, owner);
    await h.storage.saveGraduateSchedule('new-owner', snapshot);
    expect(jsonDecode(prefs.getString('graduate_schedule_v2')!)['owner'], 'new-owner');
    expect(prefs.getString('graduate_schedule_owner'), owner);
    expect(jsonDecode(prefs.getString('graduate_schedule')!), snapshot.toJson());
    expect(h.storage.graduateScheduleOwner, 'new-owner');
    expect(h.storage.loadGraduateSchedule()!.rows, isNotEmpty);
  });

  for (final phase in ['snapshot', 'selection', 'calendar', 'scheme']) {
    test('an unbind during $phase persistence stops the remaining graduate writes', () async {
      final h = await harness(timetable: fixtureWithStart());
      h.schedule.dispose();
      final storage = _PausedStorage(await SharedPreferences.getInstance());
      final schedule = ScheduleService(storage, h.httpClient, h.auth, h.tp);
      addTearDown(schedule.dispose);
      if (phase == 'scheme') await schedule.fetchAll();
      storage.phase = phase;
      storage.writes.clear();
      final pending = switch (phase) {
        'scheme' => schedule.selectGraduateScheme('B'),
        _ => schedule.fetchAll(),
      };
      await storage.entered.future;
      final tableWrites = storage.writes.where((name) => name == 'table').length;
      await h.tp.unbind(ThirdPartyPlatform.ids);
      storage.release.complete();
      await pending;
      expect(schedule.courseTable, isNull);
      expect(storage.loadGraduateSchedule(), isNull);
      expect(storage.loadCourseTable(semester, owner: owner), isNull);
      expect(storage.writes.where((name) => name == 'table'), hasLength(tableWrites));
      if (phase == 'snapshot') expect(storage.writes, isNot(contains('selection')));
    });
  }

  for (final nextAccount in ['20260002', '20260001']) {
    test('rebinding $nextAccount during snapshot save discards the old response', () async {
      final h = await harness();
      h.schedule.dispose();
      final storage = _PausedStorage(await SharedPreferences.getInstance())..phase = 'snapshot';
      final schedule = ScheduleService(storage, h.httpClient, h.auth, h.tp);
      addTearDown(schedule.dispose);
      final pending = schedule.fetchAll();
      await storage.entered.future;
      await h.tp.bindIds(
        account: nextAccount,
        password: 'synthetic',
        promptCaptcha: (_, __, {required refresh}) async => null,
      );
      expect(schedule.courseTable, isNull);
      expect(storage.loadGraduateSchedule(), isNull);
      storage.release.complete();
      await pending;
      expect(schedule.courseTable, isNull);
      expect(storage.loadGraduateSchedule(), isNull);
      expect(storage.selectedSemester, isNull);
      await h.tp.bindIds(
        account: '20260001',
        password: 'synthetic',
        promptCaptcha: (_, __, {required refresh}) async => null,
      );
      await schedule.loadCachedData();
      expect(schedule.courseTable, isNull);
      expect(storage.graduateScheduleOwner, isNull);
    });
  }

  test('unsupported graduate exams remove old exams while retaining assignments', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    await h.storage.saveCachedAssignments([
      ExamAssignment(
        id: 'old-exam',
        title: '本科考试',
        course: '旧课程',
        due: DateTime(2026),
        semesterId: 'undergrad-term',
        location: '',
        batchName: '',
      ).toJson(),
      Assignment(
        id: 'homework',
        platform: 'blackboard',
        title: '作业',
        course: '课程',
        due: DateTime(2026),
      ).toJson(),
    ]);
    final assignments = AssignmentService(h.storage, h.httpClient, h.auth, h.tp, h.schedule);
    addTearDown(assignments.dispose);
    assignments.loadCached();
    h.requests.clear();
    await assignments.fetchPlatform('exam');
    expect(assignments.assignments.map((a) => a.id), ['homework']);
    expect(h.storage.loadCachedAssignments().map((a) => a['id']), ['homework']);
    expect(assignments.platformErrors, isEmpty);
    expect(h.requests, isEmpty);
  });

  for (final pausedEndpoint in ['stdExamTable.action', 'blackboard']) {
    test('switching to graduate discards old exams while $pausedEndpoint is pending', () async {
      final h = await harness(graduate: false);
      addTearDown(h.schedule.dispose);
      await h.schedule.fetchAll();
      h.overrides['stdExamTable.action'] = http.Response(
        examBatches,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final assignments = AssignmentService(
        h.storage,
        h.httpClient,
        h.auth,
        h.tp,
        h.schedule,
        blackboardDeadlines: () async {
          if (pausedEndpoint == 'blackboard') {
            if (!h.eamsEntered.isCompleted) h.eamsEntered.complete();
            await h.resumeEams.future;
          }
          return [];
        },
      )
        ..loadCached()
        ..enableAutoRefetch();
      addTearDown(assignments.dispose);
      h.pausedEamsEndpoint = pausedEndpoint;
      final pending = pausedEndpoint == 'stdExamTable.action'
          ? assignments.fetchPlatform('exam')
          : assignments.fetchAssignments();
      await h.eamsEntered.future;
      if (pausedEndpoint == 'blackboard') {
        await h.examAnswered.future;
        await Future<void>.delayed(Duration.zero);
      }
      await h.schedule.selectScheduleSource(CampusScheduleSource.graduate);
      expect(h.schedule.isGraduate, isTrue);
      h.resumeEams.complete();
      await pending;
      expect(assignments.assignments.whereType<ExamAssignment>(), isEmpty);
      expect(h.storage.loadCachedAssignments().where((a) => a['platform'] == 'exam'), isEmpty);
    });
  }

  test('assignments wait for the undergraduate source switch before fetching exams', () async {
    final h = await harness(graduate: false);
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    final assignments = AssignmentService(h.storage, h.httpClient, h.auth, h.tp, h.schedule)
      ..loadCached()
      ..enableAutoRefetch();
    addTearDown(assignments.dispose);
    h.overrides['stdExamTable.action'] = http.Response(emptyExamBatches, 200);
    h.overrides['blackboard'] = http.Response('{"success":true,"data":[]}', 200);
    h.pausedEamsEndpoint = 'courseTableForStd!courseTable.action';
    final switching = h.schedule.selectScheduleSource(CampusScheduleSource.undergraduate);
    await h.eamsEntered.future;
    await Future<void>.delayed(Duration.zero);
    expect(h.examAnswered.isCompleted, isFalse);
    h.resumeEams.complete();
    await switching;
    await h.examAnswered.future.timeout(const Duration(seconds: 3));
    expect(
      h.requests.where((request) => request.url.path.endsWith('/stdExamTable.action')),
      hasLength(1),
    );
  });
}

class Harness {
  late ScheduleService schedule;
  late StorageService storage;
  late LoggingHttpClient httpClient;
  late AuthService auth;
  late ThirdPartyAuthService tp;
  Completer<void>? tableGate;
  Completer<void>? identityGate;
  final identityEntered = Completer<void>();
  final tableEntered = Completer<void>();
  String? pausedEamsEndpoint;
  final eamsEntered = Completer<void>();
  final resumeEams = Completer<void>();
  final examAnswered = Completer<void>();
  final requests = <http.Request>[];
  final overrides = <String, http.Response>{};
  String category = '';
  bool fail = false;
}

Future<Harness> harness({
  bool graduate = true,
  String profileSid = '20260001',
  Map<String, dynamic>? timetable,
  IdsClient? idsClient,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  await storage.saveThirdPartyAccount(
    FakeIdsClient.account('20260001'),
  );
  final h = Harness()..category = graduate ? '学生/硕士生' : '学生/本科生';
  final server = MockClient((request) async {
    h.requests.add(request);
    final endpoint = request.url.pathSegments.last;
    if (endpoint == h.pausedEamsEndpoint) {
      h.pausedEamsEndpoint = null;
      h.eamsEntered.complete();
      await h.resumeEams.future;
    }
    final override = h.overrides[endpoint];
    if (endpoint == 'stdExamTable.action' && !h.examAnswered.isCompleted) h.examAnswered.complete();
    if (override != null) return override;
    if (request.url.path.endsWith('getUserConf') && h.identityGate != null) {
      h.identityEntered.complete();
      await h.identityGate!.future;
    }
    if (request.url.path.endsWith('loadKbxx.do') && h.tableGate != null) {
      h.tableEntered.complete();
      await h.tableGate!.future;
    }
    if (h.fail) throw const FormatException('synthetic offline');
    final Object data = switch (endpoint) {
      'index.html' || 'course.html' || 'login' || 'index.do' => '<html>synthetic entry</html>',
      'getUserConf' => {
        'code': '0',
        'datas': {'uid': profileSid, 'categoryName': h.category},
      },
      'loadKbxx.do' => timetable ?? fixture(),
      'loadPublicInfo_course.do' => {
        'lcxxMap': {'XNXQDM': '20261', 'XNXQMC': '2026-2027学年秋季学期'},
      },
      'eams' => {
        'success': true,
        'data': {'token': 'school-session'},
      },
      'stdDetail.action' => '<html>姓名： </td><td>TEST</td></html>',
      'courseTableForStd.action' => scheduleEntry('undergrad-term'),
      'dataQuery.action' => semesterOptions('2026-2027', 'undergrad-term'),
      'courseTableForStd!courseTable.action' => emptyTimetable,
      'stdExamTable!examTable.action' => examTable,
      'getSchoolCalendar.do' => {
        'code': 200,
        'schoolYearTerm': '2026-2027-1',
        'termBegin': '2026-09-07',
        'allTeachWeeks': 16,
        'allTermWeeks': 20,
      },
      _ => throw StateError('Unexpected request ${request.url.path}'),
    };
    return http.Response(
      data is String ? data : jsonEncode(data),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  final client = LoggingHttpClient(DebugLogger(), inner: server);
  final auth = AuthService(storage, client, UniAuthService());
  final tp = ThirdPartyAuthService(storage, client, idsClient: idsClient ?? FakeIdsClient());
  await tp.initialize();
  h.storage = storage;
  h.httpClient = client;
  h.auth = auth;
  h.tp = tp;
  h.schedule = ScheduleService(
    storage,
    client,
    auth,
    tp,
    eamsTransport: eamsTransport(server),
    eamsInterval: Duration.zero,
  );
  return h;
}

class _FailingIdsClient extends FakeIdsClient {
  int loginAttempts = 0;

  @override
  Future<IdsSession> login(IdsPasskey secret, {bool backedUp = false}) async {
    loginAttempts++;
    throw const FormatException('synthetic Passkey failure');
  }
}

class _PausedStorage extends StorageService {
  _PausedStorage(super.prefs);

  String? phase;
  final entered = Completer<void>();
  final release = Completer<void>();
  final writes = <String>[];

  Future<void> _pause(String name) async {
    writes.add(name);
    if (name == phase) {
      entered.complete();
      await release.future;
    }
  }

  @override
  Future<void> saveGraduateSchedule(String owner, GraduateSchedule schedule) async {
    final pending = super.saveGraduateSchedule(owner, schedule);
    await _pause('snapshot');
    await pending;
  }

  @override
  Future<void> setSelectedSemester(String id) async {
    await super.setSelectedSemester(id);
    await _pause('selection');
  }

  @override
  Future<void> saveTermCalendar(String key, TermCalendar info) async {
    await super.saveTermCalendar(key, info);
    await _pause('calendar');
  }

  @override
  Future<void> setGraduateScheme(String semesterId, String scheme) async {
    await super.setGraduateScheme(semesterId, scheme);
    await _pause('scheme');
  }

  @override
  Future<void> saveCourseTable(String semesterId, CourseTable table, {String? owner}) async {
    await super.saveCourseTable(semesterId, table, owner: owner);
    await _pause('table');
  }
}

bool _timetablePath(String path) =>
    path.startsWith('/eams/courseTableForStd') || path == '/eams/dataQuery.action';
