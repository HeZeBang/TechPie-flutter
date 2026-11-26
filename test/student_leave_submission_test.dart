import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/student_leave.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_leave_service.dart';
import 'package:techpie/services/student_leave_submission.dart';

import 'campus/campus_fixture.dart';

const _ok = '#E000000000000';
const fields = {
  'QJXZ': 'property',
  'QJXZ_DISPLAY': '请假',
  'QJLX': 'kind',
  'QJLX_DISPLAY': '示例假别',
  'DZ_QJQX': 'district',
  'DZ_QJQX_DISPLAY': '示例省/示例区',
  'DZ_XXDZ': '示例地址',
  'QJSY': '示例事由',
  'YL1': '00000000000',
  'YL2': 'student@example.org',
  'YL3': '无',
  'YL4': '联系人',
  'YL5': '00000000001',
  'YL6': '0',
  'YL6_DISPLAY': '不涉及课程',
  'QJKSRQ': '2030-04-08',
  'QJJSRQ': '2030-04-09',
};

class _School {
  late CampusFixture campus;
  late StudentLeaveService service;
  late ValueNotifier<int> accounts;
  final List<Map<String, dynamic>> saved = [];
  final List<String> calls = [];
  final List<Map<String, dynamic>> ranges = [];
  Map<String, dynamic> overlap = {'returnCode': _ok, 'data': <String, dynamic>{}};
  Map<String, dynamic> saveReply = {'returnCode': _ok};
  Map<String, dynamic> editFields = {
    ...fields,
    'XSBH': 'student',
    'SQBH': 'request-key',
    'KSH': 'school-id',
    'QJTS': 2,
    'ZMCL': 'proof-token',
    'YL7': 'course-token',
  };
  List<Map<String, dynamic>> editDates = [
    {'QJRQ': '2030-04-08'},
    {'QJRQ': '2030-04-09'},
  ];
  bool failNotification = false;
  bool needsProof = false;

  Future<void> init() async {
    SharedPreferences.setMockInitialValues({});
    accounts = ValueNotifier(0);
    campus = CampusFixture('https://egate.shanghaitech.edu.cn', reply);
    service = StudentLeaveService(
      EmapClient(campus.session),
      StorageService(await SharedPreferences.getInstance()),
      accounts,
    );
    addTearDown(service.dispose);
    addTearDown(accounts.dispose);
  }

  ResponseBody reply(RequestOptions request) {
    if (request.uri.path.contains('getAppConfig')) return respond({});
    final key = request.uri.pathSegments.last;
    calls.add(key);
    final form = request.data as Map;
    Map<String, dynamic> table(String name, Map<String, dynamic> row) => {
          'code': 0,
          'datas': {
            name: {
              'rows': [row],
              'totalSize': 1,
            },
          },
        };
    switch (key) {
      case 'qjsqbd_jbxx.do':
        return respond(table('qjsqbd_jbxx', {'XSBH': 'student'}));
      case 'qjsqbd_qjxx.do':
        expect(form['SQBH'], 'request-key');
        return respond(table('qjsqbd_qjxx', editFields));
      case 'wdqjbg.do':
        return respond(table('wdqjbg', {'SQBH': 'request-key', 'SHZT': '0'}));
      case 'getStuxslbdm.do':
        return respond({
          'returnCode': _ok,
          'data': {'XSLBDM': '3'},
        });
      case 'getLeaveDates.do':
        return respond({'returnCode': _ok, 'data': editDates});
      case 'getAppliedDays.do':
        return respond({
          'returnCode': _ok,
          'data': {'ZDQJTS': 45, 'KQJTS': 30},
        });
      case 'getNoRemoveLeave.do':
        return respond({'returnCode': _ok});
      case 'getCaseByType.do':
        return respond({
          'returnCode': _ok,
          'data': {'QJLX': 'kind'},
        });
      case 'checkLeaveDate.do':
        ranges.add(jsonDecode(form['requestParamStr'] as String) as Map<String, dynamic>);
        return respond(overlap);
      case 'getLeaveType.do':
        return respond({
          'returnCode': _ok,
          'data': [
            {'LXDM': 'kind', 'SFSCCL': needsProof ? '1' : '0'},
          ],
        });
      case 'editLeaveApply.do':
      case 'addLeaveApply.do':
        saved.add(jsonDecode(form['INDATA'] as String) as Map<String, dynamic>);
        return respond(saveReply);
      case 'SentMassage.do':
        return respond({'returnCode': failNotification ? 'rejected' : _ok});
      default:
        if (request.uri.path.startsWith('/xsfw/code/')) {
          expect(form['searchValue'], '示例区');
          return respond({
            'datas': {
              'code': {
                'rows': [
                  {'id': 'county', 'name': '示例区', 'pId': 'city', 'isParent': 0},
                  {'id': 'province', 'name': '示例省', 'pId': '', 'isParent': 1},
                  {'id': 'city', 'name': '示例市', 'pId': 'province', 'isParent': 1},
                ],
              },
            },
          });
        }
        throw StateError(key);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'preflights a new application, commits proof, saves once and acknowledges notification separately',
      () async {
    final s = _School()..needsProof = true;
    await s.init();
    final f = await s.service.openLeaveForm(s.service.revision);
    final result = await s.service.saveLeaveForm(
      f,
      fields,
      uploadAttachments: () async {
        expect(s.calls, contains('checkLeaveDate.do'));
        expect(s.saved, isEmpty);
        return {'ZMCL': 'new-proof'};
      },
    );
    expect(result.message, contains('已保存'));
    expect(s.saved.single, containsPair('QJRQ', '2030-04-08,2030-04-09'));
    expect(s.saved.single, containsPair('QJTS', 2));
    expect(s.saved.single, containsPair('SQBH', ''));
    expect(s.saved.single, containsPair('XSBH', ''));
    expect(s.saved.single, containsPair('QJKSRQ', ''));
    expect(s.saved.single, containsPair('ZMCL', 'new-proof'));
    expect(s.ranges.single, {'QJRQ': '2030-04-08,2030-04-09', 'XSBH': 'student'});
    expect(s.calls.last, 'SentMassage.do');
    await expectLater(s.service.saveLeaveForm(f, fields), throwsA(isA<LeaveSaveUncertain>()));
    expect(s.saved, hasLength(1));
  });
  test(
      'editing rehydrates contact, dates and attachment tokens and preserves school record identity',
      () async {
    final s = _School()..failNotification = true;
    await s.init();
    final f = await s.service.openLeaveForm(
      s.service.revision,
      editing: StudentLeave({'SQBH': 'request-key', 'SHZT': '0'}),
    );
    expect(f.values['QJRQ'], '2030-04-08,2030-04-09');
    expect(f.values['QJKSRQ'], '2030-04-08');
    final result =
        await s.service.saveLeaveForm(f, {'QJSY': '修订说明', 'SQBH': 'wrong', 'KSH': 'ignore'});
    expect(s.calls, contains('editLeaveApply.do'));
    expect(s.saved.single, containsPair('SQBH', 'request-key'));
    expect(s.saved.single, containsPair('KSH', 'school-id'));
    expect(s.saved.single, containsPair('QJSY', '修订说明'));
    expect(s.saved.single, containsPair('ZMCL', 'proof-token'));
    expect(s.saved.single, containsPair('YL7', 'course-token'));
    expect(result.message, contains('通知结果未确认'));
    expect(s.service.storage.readEmapCache('student_leave'), isNull);
  });
  test('uses a consistent date range from the saved row when the edit calendar is incomplete',
      () async {
    final school = _School()..editDates = [];
    await school.init();
    final record = StudentLeave({'SQBH': 'request-key'});
    final form = await school.service.openLeaveForm(school.service.revision, editing: record);
    expect(form.values['QJRQ'], '2030-04-08,2030-04-09');
    school.editFields['QJTS'] = 3;
    final missing = await school.service.openLeaveForm(school.service.revision, editing: record);
    expect(missing.values['QJRQ'], isEmpty);
    await expectLater(school.service.saveLeaveForm(missing, {}), fails(CampusErrorKind.rejected));
    expect(school.saved, isEmpty);
  });

  test('stops on an ambiguous date check and a reported overlap before uploading files', () async {
    final s = _School()..overlap = {'returnCode': 'overlap-check-error'};
    await s.init();
    final f = await s.service.openLeaveForm(s.service.revision);
    var uploads = 0;
    Future<Map<String, String>> upload() async {
      uploads++;
      return {};
    }

    await expectLater(
      s.service.saveLeaveForm(f, fields, uploadAttachments: upload),
      fails(CampusErrorKind.rejected),
    );
    s.overlap = {
      'returnCode': _ok,
      'data': {'XSBH': 'student'},
    };
    await expectLater(
      s.service.saveLeaveForm(f, fields, uploadAttachments: upload),
      fails(CampusErrorKind.rejected),
    );
    expect(uploads, 0);
    expect(s.saved, isEmpty);
  });
  test('accepts an empty school result from the date overlap check', () async {
    for (final empty in [null, '', <Object?>[]]) {
      final school = _School()..overlap = {'returnCode': _ok, 'data': empty};
      await school.init();
      final form = await school.service.openLeaveForm(school.service.revision);
      await school.service.saveLeaveForm(form, fields);
      expect(school.saved, hasLength(1));
    }
  });

  test('blocks concurrent submission and repeat after uncertain response', () async {
    final s = _School()..saveReply = {};
    await s.init();
    final f = await s.service.openLeaveForm(s.service.revision);
    final uploading = Completer<void>(), release = Completer<void>();
    final pending = s.service.saveLeaveForm(
      f,
      fields,
      uploadAttachments: () async {
        uploading.complete();
        await release.future;
        return {};
      },
    );
    await uploading.future;
    await expectLater(s.service.saveLeaveForm(f, fields), fails(CampusErrorKind.rejected));
    release.complete();
    await expectLater(pending, throwsA(isA<LeaveSaveUncertain>()));
    await expectLater(s.service.saveLeaveForm(f, fields), throwsA(isA<LeaveSaveUncertain>()));
    expect(s.saved, hasLength(1));
    expect(s.calls, isNot(contains('SentMassage.do')));
  });
  test('district results resolve parent labels using the school dictionary', () async {
    final s = _School();
    await s.init();
    final regions = await s.service.leaveRegions('示例区', s.service.revision);
    expect(regions.single.code, 'county');
    expect(regions.single.label, '示例省/示例市/示例区');
  });
}
