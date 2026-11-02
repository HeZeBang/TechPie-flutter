import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/campus_identity.dart';
import 'package:techpie/models/graduate_schedule.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/graduate_schedule_client.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

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
    expect(GraduateSchedule.fromJson(raw).firstMondayFor(semester), DateTime(2026, 9, 14));
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
    await h.schedule.setGraduateFirstMonday(DateTime(2026, 9, 7));
    await h.schedule.fetchAll();
    expect(h.schedule.termBegin, DateTime(2026, 9, 7));
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
    await h.schedule.setGraduateFirstMonday(DateTime(2026, 9, 7));
    expect(h.schedule.termBegin, DateTime(2026, 9, 7));
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

  test('IDS undergraduate identity uses original requests without opening the graduate system',
      () async {
    final h = await harness(graduate: false);
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    expect(h.schedule.error, isNull);
    expect(h.schedule.isGraduate, isFalse);
    expect(h.schedule.selectedSemesterId, 'undergrad-term');
    expect(h.requests.any((r) => r.url.host == GraduateScheduleClient.host), isFalse);
    expect(
        h.requests.where((r) => r.url.path.contains('/schedule/')).map((r) => r.url.path).toList(),
        [
          '/api/schedule/semesters',
          '/api/schedule/course_table',
          '/api/schedule/term_begin',
        ]);
  });

  test('a profile with a different student id never opts this account in', () async {
    final h = await harness(profileSid: 'OTHER');
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    expect(h.schedule.error, contains('IDS 当前账号与学校绑定学号不一致'));
    expect(h.schedule.isGraduate, isFalse);
    expect(h.requests.any((r) => r.url.path.endsWith('loadKbxx.do')), isFalse);
    expect(h.requests.any((r) => r.url.path.contains('/schedule/')), isFalse);
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
    expect(h.requests.any((r) => r.url.path.contains('/schedule/')), isFalse);
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

  test('selected scheme and local start date survive a cached restart', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    await h.schedule.setGraduateFirstMonday(DateTime(2026, 9, 7));
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

  test('an unbind discards a late graduate response instead of caching it', () async {
    final h = await harness();
    addTearDown(h.schedule.dispose);
    h.tableGate = Completer<void>();
    final pending = h.schedule.fetchAll();
    await h.tableEntered.future;
    await h.tp.unbind(ThirdPartyPlatform.cpdaily);
    h.tableGate!.complete();
    await pending;
    expect(h.schedule.courseTable, isNull);
    expect(h.schedule.semesterInfo, isNull);
    expect(h.storage.graduateScheduleOwner, isNull);
  });
}

class Harness {
  late ScheduleService schedule;
  late StorageService storage;
  late LoggingHttpClient httpClient;
  late AuthService auth;
  late ThirdPartyAuthService tp;
  Completer<void>? tableGate;
  final tableEntered = Completer<void>();
  final requests = <http.Request>[];
  final overrides = <String, http.Response>{};
  String category = '';
  bool fail = false;
}

Future<Harness> harness({bool graduate = true, String profileSid = '20260001'}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  await storage.saveThirdPartyAccount(
    ThirdPartyAccount(
      platform: ThirdPartyPlatform.cpdaily,
      account: '20260001',
      sid: '20260001',
      token: 'session',
      raw: const {'tgc': 'test-tgc'},
      boundAt: DateTime(2026),
    ),
  );
  final h = Harness()..category = graduate ? '学生/硕士生' : '学生/本科生';
  final client = LoggingHttpClient(
    DebugLogger(),
    inner: MockClient((request) async {
      h.requests.add(request);
      final override = h.overrides[request.url.path.split('/').last];
      if (override != null) return override;
      if (request.url.path.endsWith('loadKbxx.do') && h.tableGate != null) {
        h.tableEntered.complete();
        await h.tableGate!.future;
      }
      if (h.fail) throw const FormatException('synthetic offline');
      final Object data = switch (request.url.path.split('/').last) {
        'index.html' || 'course.html' || 'login' || 'index.do' => '<html>synthetic entry</html>',
        'getUserConf' => {
            'code': '0',
            'datas': {'uid': profileSid, 'categoryName': h.category},
          },
        'loadKbxx.do' => fixture(),
        'loadPublicInfo_course.do' => {
            'lcxxMap': {'XNXQDM': '20261', 'XNXQMC': '2026-2027学年秋季学期'},
          },
        'eams' => {
            'success': true,
            'data': {'token': 'school-session'},
          },
        'stdDetail.action' => '<html>姓名： </td><td>TEST</td></html>',
        'semesters' => {
            'success': true,
            'data': {
              'semesters': {
                '2026-2027': {'秋': 'undergrad-term'},
              },
              'defaultSemester': 'undergrad-term',
              'tableId': 't1',
            },
          },
        'course_table' => {
            'success': true,
            'data': {'periods': <Object>[], 'courses': <Object>[]},
          },
        'term_begin' => {
            'success': true,
            'data': {'termBegin': '2026-09-07', 'allTeachWeeks': 16, 'allTermWeeks': 20},
          },
        _ => throw StateError('Unexpected request ${request.url.path}'),
      };
      return http.Response(
        data is String ? data : jsonEncode(data),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  final auth = AuthService(storage, client, UniAuthService());
  final tp = ThirdPartyAuthService(storage, client);
  await tp.initialize();
  h.storage = storage;
  h.httpClient = client;
  h.auth = auth;
  h.tp = tp;
  h.schedule = ScheduleService(storage, client, auth, tp);
  return h;
}
