import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/student_leave.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_leave_management.dart';
import 'package:techpie/services/student_leave_service.dart';

import 'campus/campus_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const origin = 'https://egate.shanghaitech.edu.cn';
  const id = 'application-A_1';
  const success = '#E000000000000';
  final record = StudentLeave({'SQBH': id, 'SHZT': 0});
  late CampusFixture fixture;
  late StudentLeaveService service;
  late ValueNotifier<int> account;
  late List<Map<String, Object?>> rows;
  late Reply mutate;
  late Map<String, Object?> nextState;
  late int revision;
  List<RequestOptions> writes() => fixture.requests
      .where((r) => ['backleaveApply.do', 'delleaveApply.do'].contains(r.uri.pathSegments.last))
      .toList();

  setUp(() async {
    rows = [];
    nextState = {
      'returnCode': success,
      'data': {'SHZT': 2},
    };
    mutate = (_) => respond({'returnCode': success});
    fixture = CampusFixture(origin, (r) {
      if (r.uri.path.contains('getAppConfig')) return respond({});
      switch (r.uri.pathSegments.last) {
        case 'wdqjbg.do':
          expect(r.uri.path, '/xsfw/sys/xsqjapp/modules/wdqj/wdqjbg.do');
          final page = int.parse(r.data['pageNumber'] as String);
          final size = int.parse(r.data['pageSize'] as String);
          return respond({
            'code': 0,
            'datas': {
              'wdqjbg': {
                'rows': rows.skip((page - 1) * size).take(size).toList(),
                'totalSize': rows.length,
              },
            },
          });
        case 'getNextState.do':
          expect(r.uri.path, '/xsfw/sys/xsqjapp/modules/leaveApply/getNextState.do');
          expect(
            jsonDecode(r.data['requestParamStr'] as String),
            {'QJLX': 'type-from-server', 'QJTS': 2},
          );
          return respond(nextState);
        case 'backleaveApply.do':
        case 'delleaveApply.do':
          return mutate(r);
        default:
          throw StateError('Unexpected request: ${r.uri.path}');
      }
    });
    SharedPreferences.setMockInitialValues({});
    account = ValueNotifier(0);
    service = StudentLeaveService(
      EmapClient(fixture.session),
      StorageService(await SharedPreferences.getInstance()),
      account,
    );
    revision = service.revision;
  });

  tearDown(() {
    service.dispose();
    account.dispose();
  });

  Map<String, Object?> row(Object state, {int returned = 0}) => {
        'SQBH': id,
        'SHZT': state,
        'THZT': returned,
        'QJLX': 'type-from-server',
        'QJTS': 2,
      };

  test('edit, delete and print eligibility follows fresh approval state and return precedence',
      () async {
    final cases = [
      (row('0'), {LeaveRecordAction.edit, LeaveRecordAction.delete}),
      (row(0, returned: 1), {LeaveRecordAction.edit}),
      (row(2, returned: 1), {LeaveRecordAction.edit}),
      (row(99, returned: 1), {LeaveRecordAction.edit}),
      (row('99'), {LeaveRecordAction.print}),
      (row(-1), <LeaveRecordAction>{}),
      (row(100), <LeaveRecordAction>{}),
      (row('unknown'), <LeaveRecordAction>{}),
    ];
    for (final (serverRow, actions) in cases) {
      rows = [serverRow];
      expect(await service.availableActions(record, revision), actions);
    }
    expect(fixture.requests.where((r) => r.uri.path.endsWith('getNextState.do')), isEmpty);
    expect(writes(), isEmpty);
  });

  test('pending application can be withdrawn only at the current first approval step', () async {
    rows = [row('2')];
    expect(await service.availableActions(record, revision), {LeaveRecordAction.withdraw});
    nextState = {
      'returnCode': success,
      'data': {'SHZT': '3'},
    };
    expect(await service.availableActions(record, revision), isEmpty);
    nextState = {'returnCode': success, 'data': null};
    expect(await service.availableActions(record, revision), isEmpty);
    nextState = {
      'returnCode': 'rejected',
      'data': {'SHZT': '2'},
    };
    await expectLater(service.availableActions(record, revision), fails(CampusErrorKind.rejected));
    expect(writes(), isEmpty);
  });

  test('looks up the exact application on later pages; an absent row cannot be modified', () async {
    rows = [
      for (var i = 0; i < 50; i++) {'SQBH': 'other-$i', 'SHZT': 99},
      row(0),
    ];
    expect(await service.availableActions(record, revision), contains(LeaveRecordAction.edit));
    final listCalls = fixture.requests.where((r) => r.uri.path.endsWith('wdqjbg.do'));
    expect(listCalls.map((r) => r.data['pageNumber']), ['1', '2']);
    rows.removeLast();
    await expectLater(
      service.changeLeaveState(record, LeaveRecordAction.delete, revision),
      fails(CampusErrorKind.notFound),
    );
    expect(writes(), isEmpty);
  });

  test('account change or change of approval state before confirmation prevents any write',
      () async {
    rows = [row(2)];
    expect(await service.availableActions(record, revision), {LeaveRecordAction.withdraw});
    rows = [row(99)];
    await expectLater(
      service.changeLeaveState(record, LeaveRecordAction.withdraw, revision),
      fails(CampusErrorKind.rejected),
    );
    rows = [row(0)];
    fixture.identity = (user: 'second-account', ids: 'second-binding');
    account.value++;
    final count = fixture.requests.length;
    await expectLater(
      service.changeLeaveState(record, LeaveRecordAction.delete, revision),
      fails(CampusErrorKind.sessionExpired),
    );
    expect(fixture.requests.length, count);
    expect(writes(), isEmpty);
  });

  test('withdraws and deletes a draft with the exact desktop POST form, once per action', () async {
    rows = [row(2)];
    mutate = (r) {
      expect(r.method, 'POST');
      expect(r.uri.path, startsWith('/xsfw/sys/xsqjapp/modules/leaveApply/'));
      expect(r.data, {
        'requestParamStr': jsonEncode({'SQBH': id}),
      });
      if (r.uri.path.endsWith('/backleaveApply.do')) {
        rows = [row(0)];
      } else {
        rows.clear();
      }
      return respond({'returnCode': success, 'description': 'OK'});
    };
    await service.changeLeaveState(record, LeaveRecordAction.withdraw, revision);
    expect(await service.availableActions(record, revision), contains(LeaveRecordAction.edit));
    await service.changeLeaveState(record, LeaveRecordAction.delete, revision);
    await expectLater(service.availableActions(record, revision), fails(CampusErrorKind.notFound));
    expect(writes().map((r) => r.uri.pathSegments.last), ['backleaveApply.do', 'delleaveApply.do']);
  });

  test('honors a rejected business receipt and never replays a timed-out or expired write',
      () async {
    rows = [row(0)];
    Future<void> remove() => service.changeLeaveState(record, LeaveRecordAction.delete, revision);
    mutate = (_) => respond({'returnCode': 'denied', 'description': 'failure'});
    await expectLater(remove(), fails(CampusErrorKind.rejected));
    expect(writes(), hasLength(1));
    mutate = (r) => throw DioException(requestOptions: r, type: DioExceptionType.receiveTimeout);
    await expectLater(remove(), fails(CampusErrorKind.network));
    expect(writes(), hasLength(2));
    mutate = (_) => respond('', status: 401);
    await expectLater(remove(), throwsA(isA<CampusRequestException>()));
    expect(writes(), hasLength(3));
  });

  test('offers the official school print view only after approval', () async {
    rows = [row(0)];
    await expectLater(service.officialPrintForm(record, revision), fails(CampusErrorKind.rejected));
    rows = [row(99)];
    final url = await service.officialPrintForm(record, revision);
    expect(url.origin, origin);
    expect(url.path, '/xsfw/sys/frReport2/show.do');
    expect(
      url.queryParameters,
      {'reportlet': 'com.fr.JZ', 'cpt': 'xsqj/SHKJ_XSQJD.cpt', 'sqbh': " '$id' "},
    );
    expect(fixture.requests.any((r) => r.uri.path.endsWith('show.do')), isFalse);
    expect(writes(), isEmpty);
  });
}
