import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_leave_service.dart';

import 'campus/campus_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reads leave list, both approval label spellings and detail by SQBH; clears scoped cache',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      if (r.uri.path.contains('getAppConfig')) return respond({});
      final model = r.uri.pathSegments.last.split('.').first;
      if (model == 'qjxqbd') expect((r.data as Map)['SQBH'], 'a');
      final rows = model == 'wdqjbg'
          ? [
              {'SQBH': 'a', 'SHZT_DISPALY': '待审', 'PRIVATE': 'sentinel'},
            ]
          : [
              {'SQBH': 'a', 'SHZT_DISPLAY': '已通过', 'QJSY': '就医', 'PRIVATE': 'sentinel'},
            ];
      return respond({
        'code': 0,
        'datas': {
          model: {'rows': rows, 'totalSize': 1},
        },
      });
    });
    final service = StudentLeaveService(EmapClient(fixture.session), storage, account);
    final rev = service.revision;
    await service.refresh();
    expect(service.history.single.status, '待审');
    final detail = await service.detail(service.history.single, rev);
    expect(detail.status, '已通过');
    expect(detail['QJSY'], '就医');
    expect(detail.fields.containsKey('PRIVATE'), isFalse);
    expect(storage.readEmapCache('student_leave'), isNot(contains('sentinel')));
    expect(storage.readEmapCache('student_leave'), isNot(contains('就医')));
    fixture.identity = (user: null, ids: null);
    account.value++;
    expect(service.history, isEmpty);
    expect(storage.readEmapCache('student_leave'), isNull);
    await expectLater(service.detail(detail, rev), fails(CampusErrorKind.sessionExpired));
    service.dispose();
  });

  test('detail status overwrites stale SHZT_DISPLAY even when detail uses SHZT_DISPALY and omits totalSize',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      if (r.uri.path.contains('getAppConfig')) return respond({});
      final model = r.uri.pathSegments.last.split('.').first;
      if (model == 'wdqjbg') {
        return respond({
          'code': 0,
          'datas': {
            'wdqjbg': {
              'rows': [
                {'SQBH': 'a', 'SHZT_DISPLAY': '待审'},
              ],
            },
          },
        });
      }
      return respond({
        'code': 0,
        'datas': {
          'qjxqbd': {
            'rows': [
              {'SQBH': 'a', 'SHZT_DISPALY': '已通过', 'QJSY': '复查'},
            ],
          },
        },
      });
    });
    final service = StudentLeaveService(EmapClient(fixture.session), storage, account);
    await service.refresh();
    expect(service.history.single.status, '待审');
    final detail = await service.detail(service.history.single, service.revision);
    expect(detail.status, '已通过');
    service.dispose();
    account.dispose();
  });

  test('checks eligibility and resolves the selected type and courses with the school forms',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final owner = ValueNotifier(0);
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      final path = r.uri.pathSegments.last;
      switch (path) {
        case 'getDefaultRole.do':
          expect(r.method, 'GET');
          return respond({});
        case 'getStudentAppliedDays.do':
          return respond({
            'datas': [
              {'YQJTS': 2.5},
            ],
          });
        case 'checkWhetherStudentCanApply.do':
          return respond({
            'datas': [
              {'applicable': true},
            ],
          });
        case 'getDictionaryOfLeaveProperty.do':
          return respond({
            'datas': [
              [
                {'leavePropertyId': 'R', 'leaveProperty': '补假'},
              ]
            ],
          });
        case 'getLeaveType.do':
          expect(jsonDecode(r.data['requestParamStr'] as String), {'YL1': 'R'});
          return respond({
            'data': [
              {'LXDM': 'A', 'LXMC': '事假', 'YL2': '1'},
            ],
          });
        case 'getStuKcmc.do':
          final params = jsonDecode(r.data['requestParamStr'] as String) as Map;
          expect(jsonDecode(params['querySetting'] as String), [
            {
              'caption': '上课日期',
              'name': 'SKRQ',
              'value': '2028-02-28,2028-02-29,2028-03-01',
              'builder': 'm_value_equal',
              'linkOpt': 'AND',
            }
          ]);
          return respond({
            'returnCode': '#E000000000000',
            'data': {
              'KCMC': ['课程甲', '课程乙'],
            },
          });
        default:
          if (r.uri.path.contains('getAppConfig')) return respond({});
          throw StateError(path);
      }
    });
    final service = StudentLeaveService(EmapClient(fixture.session), storage, owner);
    final rev = service.revision;
    final info = await service.applicationInfo(rev);
    expect(info.daysUsed, '2.5');
    expect(info.eligible, isTrue);
    expect(info.properties, {'R': '补假'});
    final kind = (await service.leaveTypes('R', rev)).single;
    expect(kind.earliestStart(DateTime(2028, 3, 1)), DateTime(2028, 2, 23));
    expect(
      await service.affectedCourses(DateTime(2028, 2, 28), DateTime(2028, 3, 1), rev),
      '课程甲，课程乙',
    );
    expect(storage.readEmapCache('student_leave'), isNull);
    service.dispose();
    owner.dispose();
  });
  for (final next in [
    (user: 'other-user', ids: 'bound'),
    (user: 'user', ids: 'other-ids'),
    (user: 'user', ids: null),
  ]) {
    test(
        'changing owner to ${next.user}/${next.ids} clears stored leave history and rejects a late response',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final account = ValueNotifier(0);
      final requested = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (r) async {
        if (r.uri.path.contains('getAppConfig')) return respond({});
        if (++calls == 2) {
          requested.complete();
          await release.future;
        }
        return respond({
          'code': 0,
          'datas': {
            'wdqjbg': {
              'totalSize': 1,
              'rows': [
                {'SQBH': 'previous-account-record'},
              ],
            },
          },
        });
      });
      final service = StudentLeaveService(EmapClient(fixture.session), storage, account);
      await service.refresh();
      expect(storage.readEmapCache('student_leave'), contains('previous-account-record'));
      final refreshing = service.refresh();
      await requested.future;
      fixture.identity = next;
      account.value++;
      expect(service.history, isEmpty);
      release.complete();
      await expectLater(
        refreshing,
        fails(next.ids == null ? CampusErrorKind.idsNotBound : CampusErrorKind.sessionExpired),
      );
      await prefs.reload();
      expect(storage.readEmapCache('student_leave'), isNull);
      service.dispose();
      account.dispose();
    });
  }
}
