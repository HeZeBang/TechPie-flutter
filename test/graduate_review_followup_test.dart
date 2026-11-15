import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course_table.dart';
import 'package:techpie/models/graduate_schedule.dart';
import 'package:techpie/models/ids_passkey.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/graduate_schedule_client.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';

import 'graduate_schedule_test.dart' as fixtures;
import 'support/fake_ids_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = '20260001|20260001';
  const semester = fixtures.semester;

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
            jsonEncode(fixtures.fixture()),
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
      final h = await fixtures.harness();
      addTearDown(h.schedule.dispose);
      await h.schedule.fetchAll();
      await h.schedule.setGraduateFirstMonday(DateTime(2026, 9, 7));
      await h.schedule.selectGraduateScheme('B');
      final prefs = await SharedPreferences.getInstance();
      final snapshot = GraduateSchedule.fromJson(fixtures.fixture());
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
    final h = await fixtures.harness();
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
    final h = await fixtures.harness();
    addTearDown(h.schedule.dispose);
    await h.schedule.fetchAll();
    void checkOwner() {
      expect(h.storage.loadCourseTable(semester, owner: owner), isNotNull);
      expect(h.storage.loadCourseTable(semester, owner: 'another-account'), isNull);
    }

    checkOwner();
    await h.tp.unbind(ThirdPartyPlatform.gradescope);
    checkOwner();
    await h.schedule.setGraduateFirstMonday(DateTime(2026, 9, 7));
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
    final h = await fixtures.harness();
    addTearDown(h.schedule.dispose);
    final prefs = await SharedPreferences.getInstance();
    final snapshot = GraduateSchedule.fromJson(fixtures.fixture());
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
      final h = await fixtures.harness();
      h.schedule.dispose();
      final storage = _PausedStorage(await SharedPreferences.getInstance());
      final schedule = ScheduleService(storage, h.httpClient, h.auth, h.tp);
      addTearDown(schedule.dispose);
      if (phase == 'calendar' || phase == 'scheme') await schedule.fetchAll();
      storage.phase = phase;
      storage.writes.clear();
      final pending = switch (phase) {
        'calendar' => schedule.setGraduateFirstMonday(DateTime(2026, 9, 7)),
        'scheme' => schedule.selectGraduateScheme('B'),
        _ => schedule.fetchAll(),
      };
      await storage.entered.future;
      await h.tp.unbind(ThirdPartyPlatform.ids);
      storage.release.complete();
      await pending;
      expect(schedule.courseTable, isNull);
      expect(storage.loadGraduateSchedule(), isNull);
      expect(storage.loadCourseTable(semester, owner: owner), isNull);
      expect(storage.writes, isNot(contains('table')));
      if (phase == 'snapshot') expect(storage.writes, isNot(contains('selection')));
    });
  }

  for (final nextAccount in ['20260002', '20260001']) {
    test('rebinding $nextAccount during snapshot save discards the old response', () async {
      final h = await fixtures.harness();
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
    final h = await fixtures.harness();
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
