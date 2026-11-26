import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../models/student_leave.dart';
import 'campus/campus_errors.dart';
import 'campus/campus_session.dart';
import 'student_leave_management.dart';
import 'student_leave_service.dart';

class LeaveForm {
  LeaveForm._(this.revision, this.studentId, this.undergraduate, this.values, this._original);

  final int revision;
  final String studentId;
  final bool undergraduate;
  final Map<String, String> values;
  final Map<String, dynamic> _original;
  bool _submitted = false;
}

class LeaveRegion {
  const LeaveRegion(this.code, this.label);
  final String code, label;
}

class LeaveSaveResult {
  const LeaveSaveResult(this.message);
  final String message;
}

class LeaveSaveUncertain implements Exception {
  const LeaveSaveUncertain();

  @override
  String toString() => '学校未返回明确的保存结果，请刷新请假记录核对后再操作';
}

const _formKeys = {
  'QJXZ_DISPLAY',
  'QJXZ',
  'QJLX_DISPLAY',
  'QJLX',
  'SQSM',
  'QJKSRQ',
  'QJJSRQ',
  'QJTS',
  'DZ_QJQX_DISPLAY',
  'DZ_QJQX',
  'DZ_XXDZ',
  'DZ_KCMC',
  'YL1',
  'YL2',
  'YL4',
  'YL5',
  'QJSY',
  'YL3',
  'YL6_DISPLAY',
  'YL6',
  'YL7',
  'ZMCL',
  'SQBH',
  'XSBH',
  'KSH',
  'QJRQ',
};
const _editableKeys = {
  'QJXZ_DISPLAY',
  'QJXZ',
  'QJLX_DISPLAY',
  'QJLX',
  'DZ_QJQX_DISPLAY',
  'DZ_QJQX',
  'DZ_XXDZ',
  'DZ_KCMC',
  'YL1',
  'YL2',
  'YL4',
  'YL5',
  'QJSY',
  'YL3',
  'YL6_DISPLAY',
  'YL6',
};
const _required = {
  'QJXZ': '请假性质',
  'QJLX': '请假类型',
  'DZ_QJQX': '请假去向',
  'DZ_XXDZ': '详细地址',
  'YL1': '联系电话',
  'YL2': '联系邮箱',
  'YL4': '紧急联系人',
  'YL5': '紧急联系方式',
  'QJSY': '请假事由',
  'YL3': '涉及课程或其他培养环节',
  'YL6': '是否涉及课程',
};
const _success = '#E000000000000';
final _saving = Expando<bool>();

Never _reject(String message) => throw CampusRequestException(CampusErrorKind.rejected, message);
String _text(dynamic value) => value?.toString().trim() ?? '';

extension StudentLeaveSubmission on StudentLeaveService {
  Future<dynamic> _read(String action, Map<String, dynamic> params, int rev) async {
    check(rev);
    final result = await client.postAction(
      app: StudentLeaveService.app,
      appId: StudentLeaveService.appId,
      path: 'modules/leaveApply/$action.do',
      form: {'requestParamStr': jsonEncode(params)},
    );
    check(rev);
    if (result['returnCode'] != _success) {
      _reject(_text(result['description']).isEmpty ? '学校未能检查请假条件' : _text(result['description']));
    }
    return result['data'];
  }

  Future<Map<String, dynamic>> _formRow(String name, Map<String, String> params, int rev) async {
    check(rev);
    final result = await client.postAction(
      app: StudentLeaveService.app,
      appId: StudentLeaveService.appId,
      path: 'modules/wdqj/$name.do',
      form: params,
    );
    check(rev);
    if ('${result['code']}' != '0') _reject('学校未返回申请表单');
    final datas = result['datas'];
    final table = datas is Map ? datas[name] : null;
    final rows = table is Map ? table['rows'] : null;
    if (rows is! List || rows.length != 1 || rows.single is! Map<String, dynamic>) {
      throw CampusRequestException.invalid;
    }
    return rows.single as Map<String, dynamic>;
  }

  Future<void> _requireEdit(String id, int rev) async {
    if (id.isEmpty) throw CampusRequestException.invalid;
    final actions = await availableActions(StudentLeave({'SQBH': id}), rev);
    if (!actions.contains(LeaveRecordAction.edit)) _reject('学校当前不允许编辑这条申请');
  }

  Future<LeaveForm> openLeaveForm(int rev, {StudentLeave? editing}) async {
    check(rev);
    final category = await _read('getStuxslbdm', {}, rev);
    final basic = await _formRow('qjsqbd_jbxx', {}, rev);
    final studentId = _text(basic['XSBH']);
    if (category is! Map || _text(category['XSLBDM']).isEmpty || studentId.isEmpty) {
      throw CampusRequestException.invalid;
    }
    final wire = <String, dynamic>{for (final key in _formKeys) key: ''};
    final formDates = <String>[];
    if (editing != null) {
      await _requireEdit(editing.id, rev);
      final params = {'SQBH': editing.id};
      final saved = await _formRow('qjsqbd_qjxx', params, rev);
      if (editing.id.isEmpty ||
          _text(saved['SQBH']) != editing.id ||
          (_text(saved['XSBH']).isNotEmpty && _text(saved['XSBH']) != studentId)) {
        throw CampusRequestException.invalid;
      }
      for (final key in _formKeys) {
        if (saved[key] != null) wire[key] = saved[key];
      }
      final rows = await _read('getLeaveDates', params, rev);
      if (rows is! List && rows != null) throw CampusRequestException.invalid;
      final candidates = <String>{};
      for (final row in rows is List ? rows : const <Object?>[]) {
        if (row is Map) {
          final date = _text(row['QJRQ']);
          if (date.isNotEmpty && _validDay(date.split(RegExp(r'[ T]')).first)) {
            candidates.add(date.split(RegExp(r'[ T]')).first);
          }
        }
      }
      final count = num.tryParse(_text(saved['QJTS']));
      if (candidates.isNotEmpty && candidates.length == count) {
        formDates.addAll(candidates.toList()..sort());
      } else {
        final start = _text(saved['QJKSRQ']).split(RegExp(r'[ T]')).first;
        final end = _text(saved['QJJSRQ']).split(RegExp(r'[ T]')).first;
        if (_validDay(start) &&
            _validDay(end) &&
            _parseDay(end).difference(_parseDay(start)).inDays + 1 == count) {
          formDates.addAll(_range(start, end));
        }
      }
      wire['QJRQ'] = formDates.join(',');
    }
    final values = {for (final e in wire.entries) e.key: _text(e.value)};
    values['QJKSRQ'] = formDates.firstOrNull ?? '';
    values['QJJSRQ'] = formDates.lastOrNull ?? '';
    return LeaveForm._(
      rev,
      studentId,
      _text(category['XSLBDM']) == '3',
      Map.unmodifiable(values),
      wire,
    );
  }

  Future<({bool proofRequired, String instructions})> leaveTypeRequirements(
    String typeId,
    int rev,
  ) async {
    final data = await _read('getLeaveType', {'LXDM': typeId}, rev);
    if (data is! List || data.length != 1 || data.single is! Map) {
      throw CampusRequestException.invalid;
    }
    final row = data.single as Map;
    return (
      proofRequired: _text(row['SFSCCL']) == '1',
      instructions: html.parseFragment(_text(row['SQSM'])).text?.trim() ?? '',
    );
  }

  Future<bool> leaveProofRequired(String typeId, int rev) async =>
      (await leaveTypeRequirements(typeId, rev)).proofRequired;

  Future<List<LeaveRegion>> leaveRegions(String keyword, int rev) async {
    check(rev);
    final search = keyword.trim();
    if (search.isEmpty) return [];
    final response = await client.session.run(
      (wire) => wire.request(
        '/xsfw/code/80f9d8aa-d053-4312-b725-016642b74e3e.do',
        method: 'POST',
        headers: formHeaders,
        data: {'*tree': '1', 'searchValue': search, 'checkParent': 'true'},
      ),
    );
    check(rev);
    final payload = jsonObject(response)['datas'];
    final code = payload is Map ? payload['code'] : null;
    final rows = code is Map ? code['rows'] : null;
    if (rows is! List || !rows.every((row) => row is Map<String, dynamic>)) {
      throw CampusRequestException.invalid;
    }
    final byId = {for (final row in rows.cast<Map<String, dynamic>>()) _text(row['id']): row};
    final regions = <LeaveRegion>[];
    for (final row in byId.values) {
      final id = _text(row['id']), name = _text(row['name']);
      if (id.isEmpty || !name.contains(search)) continue;
      final labels = [name], visited = {id};
      var parent = _text(row['pId']);
      while (byId.containsKey(parent) && visited.add(parent)) {
        labels.add(_text(byId[parent]!['name']));
        parent = _text(byId[parent]!['pId']);
      }
      regions.add(LeaveRegion(id, labels.reversed.join('/')));
    }
    return regions;
  }

  Future<LeaveSaveResult> saveLeaveForm(
    LeaveForm form,
    Map<String, String> changes, {
    Future<Map<String, String>> Function()? uploadAttachments,
  }) async {
    final rev = form.revision;
    check(rev);
    if (form._submitted) throw const LeaveSaveUncertain();
    if (_saving[this] == true) _reject('正在提交请假申请');
    _saving[this] = true;
    try {
      final data = {
        ...form._original,
        for (final e in changes.entries)
          if (_editableKeys.contains(e.key)) e.key: e.value.trim(),
      };
      for (final item in _required.entries) {
        if (_text(data[item.key]).isEmpty) _reject('请填写${item.value}');
      }
      final editing = _text(data['SQBH']).isNotEmpty;
      if (editing) await _requireEdit(_text(data['SQBH']), rev);
      final dates = _leaveDates(form, changes);
      if (editing) {
        data['QJKSRQ'] = dates.first;
        data['QJJSRQ'] = dates.last;
      }
      data['QJRQ'] = dates.join(',');
      data['QJTS'] = dates.length;
      final who = {'XSBH': form.studentId};
      final days = await _read('getAppliedDays', who, rev);
      if (days is! Map) _reject('学校未开放请假时间');
      final total = num.tryParse(_text(days['ZDQJTS']));
      final remaining = num.tryParse(_text(days['KQJTS']));
      if (total == null || !total.isFinite || total < 0) throw CampusRequestException.invalid;
      if (total != 0) {
        if (remaining == null || !remaining.isFinite) throw CampusRequestException.invalid;
        if (remaining < dates.length) _reject('所选天数超过本学期剩余请假天数');
      }
      if (await _read('getNoRemoveLeave', who, rev) != null) _reject('存在未销假的请假记录');
      final route = {'QJLX': data['QJLX'], 'QJTS': dates.length};
      final approval = await _read('getCaseByType', route, rev);
      if (approval == null ||
          approval == false ||
          approval == '' ||
          (approval is Map && approval.isEmpty) ||
          (approval is List && approval.isEmpty)) {
        _reject('学校未配置该假种和天数的审批流程');
      }
      final clash = await _read('checkLeaveDate', {...who, 'QJRQ': data['QJRQ']}, rev);
      if (clash != null && clash != '' && clash is! Map && !(clash is List && clash.isEmpty)) {
        throw CampusRequestException.invalid;
      }
      if (clash is Map && _text(clash['XSBH']).isNotEmpty) _reject('所选日期与已有请假重叠');
      final needsProof = await leaveProofRequired(_text(data['QJLX']), rev);
      if (uploadAttachments != null) {
        final tokens = await uploadAttachments();
        check(rev);
        for (final key in ['YL7', 'ZMCL']) {
          if (tokens.containsKey(key)) data[key] = tokens[key];
        }
      }
      if (needsProof && _text(data['ZMCL']).isEmpty) _reject('请上传证明材料');
      if (form.undergraduate && data['YL6'] == '1' && _text(data['YL7']).isEmpty) {
        _reject('请上传任课教师知情材料');
      }
      final action = editing ? 'editLeaveApply' : 'addLeaveApply';
      check(rev);
      form._submitted = true;
      late final Map<String, dynamic> reply;
      try {
        reply = await client.postAction(
          app: StudentLeaveService.app,
          appId: StudentLeaveService.appId,
          path: 'modules/leaveApply/$action.do',
          form: {'INDATA': jsonEncode(data)},
          singleSubmission: true,
        );
      } on CampusRequestException {
        throw const LeaveSaveUncertain();
      }
      if (reply['returnCode'] == null) throw const LeaveSaveUncertain();
      if (reply['returnCode'] != _success) {
        form._submitted = false;
        _reject(_text(reply['description']).isEmpty ? '学校未接受请假申请' : _text(reply['description']));
      }
      check(rev);
      try {
        final notified = await client.postAction(
          app: StudentLeaveService.app,
          appId: StudentLeaveService.appId,
          path: 'modules/swmsmail/SentMassage.do',
          form: {'requestParamStr': jsonEncode(route)},
          singleSubmission: true,
        );
        check(rev);
        if (notified['returnCode'] == _success) return const LeaveSaveResult('请假申请已保存');
      } on CampusRequestException {
        check(rev);
      }
      return const LeaveSaveResult('请假申请已保存，学校通知结果未确认');
    } finally {
      _saving[this] = false;
    }
  }
}

bool _validDay(String value) {
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  return parsed != null && parsed.toIso8601String().split('T').first == value;
}

DateTime _parseDay(String value) {
  final date = DateTime.tryParse('${value}T00:00:00Z');
  if (date == null || date.toIso8601String().split('T').first != value) {
    _reject('请选择有效的请假日期');
  }
  return date;
}

List<String> _leaveDates(LeaveForm form, Map<String, String> changes) {
  final csv = changes['QJRQ'] ??
      (!changes.containsKey('QJKSRQ') && !changes.containsKey('QJJSRQ')
          ? form.values['QJRQ']
          : null);
  if (csv != null && csv.isNotEmpty) {
    final days = csv.split(',')..sort();
    for (var i = 0; i < days.length; i++) {
      final day = _parseDay(days[i]);
      if (i > 0 && day.difference(_parseDay(days[i - 1])).inDays != 1) _reject('请假日期必须连续');
    }
    return days;
  }
  return _range(
    changes['QJKSRQ'] ?? form.values['QJKSRQ'] ?? '',
    changes['QJJSRQ'] ?? form.values['QJJSRQ'] ?? '',
  );
}

List<String> _range(String first, String last) {
  final start = _parseDay(first);
  final end = _parseDay(last);
  if (end.isBefore(start)) _reject('结束日期不能早于开始日期');
  return [
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1)))
      d.toIso8601String().substring(0, 10),
  ];
}
