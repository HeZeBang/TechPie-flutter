import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/student_leave.dart';
import 'campus/campus_errors.dart';
import 'campus/emap_account_cache.dart';
import 'campus/emap_client.dart';
import 'storage_service.dart';

class StudentLeaveService extends EmapAccountCache {
  StudentLeaveService(this.client, StorageService storage, Listenable accounts)
      : super('student_leave', storage, client.session.identity, accounts);
  final EmapClient client;
  static const app = 'xsqjapp', appId = '4810794463325921';
  List<StudentLeave> get history => (values['history'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .map(StudentLeave.new)
      .toList();

  static const _mobile = 'ekdz/MobileServiceStudentApply';

  Future<dynamic> _mobileData(String name, int rev, {Map<String, String>? query}) async {
    check(rev);
    final result =
        await client.getAction(app: app, appId: appId, path: '$_mobile/$name.do', query: query);
    check(rev);
    final data = result['datas'];
    if (data is! List || data.isEmpty) throw CampusRequestException.invalid;
    return data.first;
  }

  Future<void> _prepareMobile(int rev) async {
    check(rev);
    await client.getAction(app: app, appId: appId, path: '$_mobile/getDefaultRole.do');
    check(rev);
  }

  Future<List<LeaveApprovalRecord>> approvalHistory(int rev) async {
    await _prepareMobile(rev);
    final rows = await _mobileData('getStudentLeaveRecords', rev);
    if (rows is! List) throw CampusRequestException.invalid;
    return rows.map((row) {
      if (row is! Map || row['leaveId'] == null || row['leaveId'].toString().trim().isEmpty) {
        throw CampusRequestException.invalid;
      }
      final title = [row['leaveProperty'], row['leaveType']]
          .whereType<String>()
          .where((v) => v.trim().isNotEmpty)
          .join(' · ');
      return LeaveApprovalRecord(
        row['leaveId'].toString(),
        title.isEmpty ? '请假申请' : title,
        row['leaveDays']?.toString() ?? '',
      );
    }).toList();
  }

  Future<LeaveApprovalDetail> approvalDetail(LeaveApprovalRecord record, int rev) async {
    final body =
        await _mobileData('getStudentLeaveRecordDetails', rev, query: {'leaveId': record.id});
    final detail = body is Map ? body['leaveInfo'] : null;
    if (detail is! Map) throw CampusRequestException.invalid;
    return LeaveApprovalDetail(
      detail['auditStateDisplay']?.toString() ?? '',
      detail['SHYJ']?.toString() ?? '',
      detail['leaveReason']?.toString() ?? '',
    );
  }

  Future<LeaveApplicationInfo> applicationInfo(int rev) async {
    await _prepareMobile(rev);
    final results = await Future.wait([
      _mobileData('getStudentAppliedDays', rev),
      _mobileData('checkWhetherStudentCanApply', rev),
      _mobileData('getDictionaryOfLeaveProperty', rev),
    ]);
    final days = results[0], gate = results[1], properties = results[2];
    if (days is! Map ||
        days['YQJTS'] == null ||
        gate is! Map ||
        gate['applicable'] is! bool ||
        properties is! List) {
      throw CampusRequestException.invalid;
    }
    final options = <String, String>{};
    for (final row in properties) {
      if (row is! Map || row['leavePropertyId'] == null || row['leaveProperty'] is! String) {
        throw CampusRequestException.invalid;
      }
      options[row['leavePropertyId'].toString()] = row['leaveProperty'] as String;
    }
    return LeaveApplicationInfo(
      daysUsed: days['YQJTS'].toString(),
      eligible: gate['applicable'] as bool,
      reason: gate['reason']?.toString() ?? '',
      properties: options,
    );
  }

  Future<List<LeaveKind>> leaveTypes(String property, int rev) async {
    check(rev);
    final result = await client.postAction(
      app: app,
      appId: appId,
      path: 'modules/leaveApply/getLeaveType.do',
      form: {
        'requestParamStr': jsonEncode({'YL1': property}),
      },
    );
    check(rev);
    final rows = result['data'];
    if (rows is! List) throw CampusRequestException.invalid;
    return rows.map((row) {
      if (row is! Map || row['LXDM'] == null || row['LXMC'] is! String) {
        throw CampusRequestException.invalid;
      }
      return LeaveKind(row['LXDM'].toString(), row['LXMC'] as String, row['YL2']?.toString() ?? '');
    }).toList();
  }

  Future<String> affectedCourses(DateTime start, DateTime end, int rev) async {
    check(rev);
    // UTC calendar days avoid dropping or repeating dates at a DST transition.
    final first = DateTime.utc(start.year, start.month, start.day);
    final last = DateTime.utc(end.year, end.month, end.day);
    if (last.isBefore(first)) throw ArgumentError.value(end, 'end');
    final dates = [
      for (var d = first; !d.isAfter(last); d = d.add(const Duration(days: 1)))
        d.toIso8601String().substring(0, 10),
    ];
    final result = await client.postAction(
      app: app,
      appId: appId,
      path: 'modules/leaveApply/getStuKcmc.do',
      form: {
        'requestParamStr': jsonEncode({
          'querySetting': jsonEncode([
            {
              'caption': '上课日期',
              'name': 'SKRQ',
              'value': dates.join(','),
              'builder': 'm_value_equal',
              'linkOpt': 'AND',
            }
          ]),
        }),
      },
    );
    check(rev);
    if (result['returnCode'] != '#E000000000000') {
      throw const CampusRequestException(CampusErrorKind.rejected, '学校未返回所选日期的课程');
    }
    final data = result['data'];
    if (data is! Map) throw CampusRequestException.invalid;
    final courses = data['KCMC'];
    if (courses is String || courses == null) return courses?.toString() ?? '';
    if (courses is List && courses.every((v) => v is String)) return courses.join('，');
    throw CampusRequestException.invalid;
  }

  Future<void> refresh() async {
    final rev = revision;
    final records = <Map<String, String>>[];
    for (var page = 1;; page++) {
      check(rev);
      final result = await client.queryModel(
        app: app,
        appId: appId,
        module: 'wdqj',
        model: 'wdqjbg',
        pageNumber: page,
        pageSize: 50,
        allowMissingTotalSize: true,
      );
      records.addAll(result.rows.map((r) => StudentLeave(r).summary));
      if (result.rows.length < 50 ||
          (result.totalSize >= 0 && records.length >= result.totalSize)) {
        break;
      }
    }
    await save(rev, 'history', records);
  }

  Future<StudentLeave> detail(StudentLeave summary, int expectedRevision) async {
    check(expectedRevision);
    if (summary.id.isEmpty) throw CampusRequestException.invalid;
    final result = await client.queryModel(
      app: app,
      appId: appId,
      module: 'wdqj',
      model: 'qjxqbd',
      extraForm: {'SQBH': summary.id},
      allowMissingTotalSize: true,
    );
    check(expectedRevision);
    for (final row in result.rows) {
      if (row['SQBH']?.toString() == summary.id ||
          (result.rows.length == 1 && row['SQBH'] == null)) {
        final merged = Map<String, dynamic>.of(summary.fields);
        final hasFreshStatus =
            (row['SHZT_DISPLAY']?.toString().trim().isNotEmpty ?? false) ||
                (row['SHZT_DISPALY']?.toString().trim().isNotEmpty ?? false);
        if (hasFreshStatus) {
          merged.remove('SHZT_DISPLAY');
          merged.remove('SHZT_DISPALY');
        }
        return StudentLeave({...merged, ...row});
      }
    }
    throw CampusRequestException.invalid;
  }
}
