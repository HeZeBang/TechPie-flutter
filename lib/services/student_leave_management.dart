import 'dart:convert';

import '../models/student_leave.dart';
import 'campus/campus_errors.dart';
import 'student_leave_service.dart';

enum LeaveRecordAction { edit, withdraw, delete, print }

extension StudentLeaveManagement on StudentLeaveService {
  Future<Set<LeaveRecordAction>> availableActions(StudentLeave record, int rev) async {
    if (record.id.isEmpty) throw CampusRequestException.invalid;
    for (var page = 1;; page++) {
      check(rev);
      final result = await client.queryModel(
        app: StudentLeaveService.app,
        appId: StudentLeaveService.appId,
        module: 'wdqj',
        model: 'wdqjbg',
        pageNumber: page,
        pageSize: 50,
        allowMissingTotalSize: true,
      );
      check(rev);
      for (final row in result.rows) {
        if (row['SQBH']?.toString() != record.id) continue;
        if ('${row['THZT']}' == '1') return {LeaveRecordAction.edit};
        final state = int.tryParse('${row['SHZT']}');
        if (state == 0) return {LeaveRecordAction.edit, LeaveRecordAction.delete};
        if (state == 99) return {LeaveRecordAction.print};
        if (state == null || state < 1 || state > 99) return {};
        final reply = await client.postAction(
          app: StudentLeaveService.app,
          appId: StudentLeaveService.appId,
          path: 'modules/leaveApply/getNextState.do',
          form: {
            'requestParamStr': jsonEncode({'QJLX': row['QJLX'], 'QJTS': row['QJTS']}),
          },
        );
        check(rev);
        final next = reply['data'];
        if (reply['returnCode'] != '#E000000000000') {
          throw const CampusRequestException(CampusErrorKind.rejected, '无法确认当前能否撤回');
        }
        return next is Map && int.tryParse('${next['SHZT']}') == state
            ? {LeaveRecordAction.withdraw}
            : {};
      }
      if (result.rows.length < 50 || (result.totalSize >= 0 && page * 50 >= result.totalSize)) {
        throw const CampusRequestException(CampusErrorKind.notFound, '当前账号的请假记录中没有这条申请');
      }
    }
  }

  Future<void> changeLeaveState(StudentLeave record, LeaveRecordAction action, int rev) async {
    final path = switch (action) {
      LeaveRecordAction.delete => 'delleaveApply.do',
      LeaveRecordAction.withdraw => 'backleaveApply.do',
      _ => throw ArgumentError.value(action, 'action'),
    };
    if (!(await availableActions(record, rev)).contains(action)) {
      throw const CampusRequestException(CampusErrorKind.rejected, '申请状态已改变，请刷新记录');
    }
    check(rev);
    final result = await client.postAction(
      app: StudentLeaveService.app,
      appId: StudentLeaveService.appId,
      path: 'modules/leaveApply/$path',
      form: {
        'requestParamStr': jsonEncode({'SQBH': record.id}),
      },
      singleSubmission: true,
    );
    check(rev);
    if (result['returnCode'] != '#E000000000000') {
      throw const CampusRequestException(CampusErrorKind.rejected, '学校未确认此操作，请刷新记录核对');
    }
  }

  Future<Uri> officialPrintForm(StudentLeave record, int rev) async {
    if (!(await availableActions(record, rev)).contains(LeaveRecordAction.print)) {
      throw const CampusRequestException(CampusErrorKind.rejected, '学校仅对审批通过的请假单开放打印');
    }
    check(rev);
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(record.id)) throw CampusRequestException.invalid;
    return client.session.origin.resolve('/xsfw/sys/frReport2/show.do').replace(
      queryParameters: {
        'reportlet': 'com.fr.JZ',
        'cpt': 'xsqj/SHKJ_XSQJD.cpt',
        'sqbh': " '${record.id}' ",
      },
    );
  }
}
