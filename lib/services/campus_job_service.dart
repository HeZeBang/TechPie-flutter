import 'dart:convert';

import '../models/campus_job.dart';
import 'campus/campus_errors.dart';
import 'campus/campus_session.dart';
import 'campus/emap_client.dart';

/// One visit owns all records. No storage or logger receives these results.
class CampusJobService {
  CampusJobService(this.client, this.studentId) : _owner = client.session.identity();
  final EmapClient client;
  final String studentId;
  final CampusIdentity _owner;
  bool _active = true;
  final _requirements = <CampusJobProgram, List<CampusJobOpening>>{};

  void dispose() {
    _active = false;
    _requirements.clear();
  }

  void _check() {
    if (!_active || client.session.identity() != _owner) throw CampusRequestException.expired;
  }

  static String _today([DateTime? now]) {
    final d = now ?? DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static bool _isRejectedReply(Map<String, dynamic> reply) =>
      (reply['code'] != null && '${reply['code']}' != '0') ||
      reply['success'] == false ||
      (reply['returnCode'] != null && reply['returnCode'] != '#E000000000000');

  Future<List<Map<String, dynamic>>> _rows(
    CampusJobProgram program,
    String module,
    String model, {
    bool personal = false,
  }) async {
    if (personal && studentId.isEmpty) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请绑定含学号的 IDS 账号');
    }
    final rows = <Map<String, dynamic>>[];
    const size = 50;
    var received = 0;
    for (var page = 1;; page++) {
      _check();
      final batch = await client.queryModel(
        app: program.app,
        appId: program.appId,
        module: module,
        model: model,
        extraForm: personal ? {'XSBH': studentId} : null,
        pageNumber: page,
        pageSize: size,
        allowMissingTotalSize: true,
      );
      _check();
      rows.addAll(
        batch.rows
            .where((row) => !personal || row['XSBH'] == null || '${row['XSBH']}' == studentId),
      );
      received += batch.rows.length;
      if (batch.rows.isEmpty ||
          (batch.totalSize < 0 ? batch.rows.length < size : received >= batch.totalSize)) {
        return rows;
      }
    }
  }

  Future<({List<Map<String, dynamic>> rows, CampusRequestException? error})> _tryRows(
    CampusJobProgram program,
    String module,
    String model, {
    bool personal = false,
  }) async {
    try {
      final rows = await _rows(program, module, model, personal: personal);
      return (rows: rows, error: null);
    } on CampusRequestException catch (e) {
      return (rows: const <Map<String, dynamic>>[], error: e);
    } catch (_) {
      return (
        rows: const <Map<String, dynamic>>[],
        error: const CampusRequestException(CampusErrorKind.network, '部分数据读取失败'),
      );
    }
  }

  Future<List<CampusJobOpening>> openings(CampusJobProgram program) async =>
      (await _rows(program, 'ksqgw', 'ksqdgwcx')).map(CampusJobOpening.fromJson).toList();

  Future<CampusJobOpening?> detail(CampusJobProgram program, CampusJobOpening opening) async {
    _check();
    var requirements = _requirements[program];
    if (requirements == null) {
      final rows = await _rows(program, 'ksqgw', 'gwxqtable');
      _check();
      requirements = rows.map(CampusJobOpening.fromJson).toList();
      _requirements[program] = requirements;
    }
    final matches = requirements.where(opening.samePosition).toList();
    return matches.length == 1 ? matches.single : null;
  }

  Future<List<CampusJobRecord>> applications(CampusJobProgram program) async =>
      (await _rows(program, 'record', 'cxsgsqxx', personal: true))
          .map(CampusJobRecord.fromJson)
          .toList()
        ..sort((a, b) => b.applied.compareTo(a.applied));

  Future<CampusJobEmployment> employment() async {
    _check();
    if (studentId.isEmpty) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请绑定含学号的 IDS 账号');
    }
    const program = CampusJobProgram.workStudy;
    final (posRes, totRes, payRes) = await (
      _tryRows(program, 'job', 'cxgwxx', personal: true),
      _tryRows(program, 'job', 'tjje', personal: true),
      _tryRows(program, 'job', 'xzmx', personal: true),
    ).wait;
    _check();
    final errors =
        [posRes.error, totRes.error, payRes.error].whereType<CampusRequestException>().toList();
    for (final err in errors) {
      if (err.kind == CampusErrorKind.sessionExpired ||
          err.kind == CampusErrorKind.idsNotBound ||
          err.kind == CampusErrorKind.rateLimited) {
        throw err;
      }
    }
    if (errors.length == 3) throw errors.first;
    return (
      positions: posRes.rows.map(CampusJobRecord.fromJson).toList(),
      total: totRes.rows.length == 1 ? totRes.rows.single['JE']?.toString() ?? '' : '',
      payments: payRes.rows.map(CampusJobPay.fromJson).toList()
        ..sort((a, b) => b.month.compareTo(a.month)),
      positionsError: posRes.error?.message,
      totalError: totRes.error?.message,
      paymentsError: payRes.error?.message,
    );
  }

  /// Submits a teaching assistant application once after validating reason length.
  Future<String> applyTeachingAssistant({
    required CampusJobOpening job,
    required String reason,
    String intro = '',
    String? date,
  }) async {
    _check();
    if (studentId.isEmpty) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请绑定含学号的 IDS 账号');
    }
    if (reason.trim().length < 20) {
      throw const FormatException('申请理由不少于 20 字');
    }
    if (job.code.isEmpty && job.id.isEmpty) {
      throw const FormatException('岗位信息不完整，请前往网页申请');
    }
    final payload = <String, dynamic>{
      'LGLBDM': '0',
      'XSBH': studentId,
      'SQBH': '',
      'SQRQ': date ?? _today(),
      'SQLY': reason.trim(),
      'BZ1': intro.trim(),
      'BZ5': 0,
      'XN': job.year,
      'XQ': job.term,
      'WID': job.id,
      'DWDM': job.unitCode,
      'GWDM': job.code,
      'SHZT': '0',
    };
    final reply = await client.postAction(
      app: CampusJobProgram.teachingAssistant.app,
      appId: CampusJobProgram.teachingAssistant.appId,
      path: 'modules/ksqgw/T_ZJGL_SQXX_SAVE.do',
      form: {'T_ZJGL_SQXX_SAVE': jsonEncode(payload)},
      singleSubmission: true,
    );
    _check();
    if (_isRejectedReply(reply)) {
      throw const CampusRequestException(CampusErrorKind.rejected, '助教申请未通过学校校验，请在网页核对');
    }
    try {
      await client.postAction(
        app: CampusJobProgram.teachingAssistant.app,
        appId: CampusJobProgram.teachingAssistant.appId,
        path: 'modules/swmsmail/StuSqSentMassage.do',
        form: {'T_ZJGL_SQXX_SAVE': jsonEncode(payload)},
        singleSubmission: true,
      );
    } on CampusRequestException catch (e) {
      if (e.kind == CampusErrorKind.sessionExpired || e.kind == CampusErrorKind.idsNotBound) {
        rethrow;
      }
    } catch (_) {}
    _check();
    return '助教申请已提交';
  }

  /// Submits a work-study application once following the EGATE DATAMODEL + action flow.
  Future<String> applyWorkStudy({
    required CampusJobOpening job,
    required String reason,
    required String phone,
    bool acceptAdjustment = true,
    String intro = '',
    String? date,
  }) async {
    _check();
    if (studentId.isEmpty) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请绑定含学号的 IDS 账号');
    }
    if (reason.trim().isEmpty) {
      throw const FormatException('请填写申请理由');
    }
    if (phone.trim().isEmpty) {
      throw const FormatException('请填写联系电话');
    }
    if (job.code.isEmpty || job.id.isEmpty) {
      throw const FormatException('岗位信息不完整，请前往网页申请');
    }
    final applyDate = date ?? _today();
    final sqdata = <String, dynamic>{
      'XSBH': studentId,
      'WID': job.id,
      'GWDM': job.code,
      'DWDM': job.unitCode,
      'XN': job.year,
      'XQ': job.term,
      'SQRQ': applyDate,
      'SQLY': reason.trim(),
      'LXFS': phone.trim(),
      'SFFCTJ': acceptAdjustment ? '1' : '0',
      'YL2': intro.trim(),
    };
    final sgxxData = <String, dynamic>{
      'XSBH': studentId,
      'GWDM': job.code,
      'DWDM': job.unitCode,
      'XN': job.year,
      'XQ': job.term,
      'SQRQ': applyDate,
      'SHZT': '0',
    };
    await client.commonCall(
      app: CampusJobProgram.workStudy.app,
      appId: CampusJobProgram.workStudy.appId,
      actionName: 'T_QGZX_SGSQSD',
      actionType: 'DATAMODEL',
      dataModelAction: 'SAVE',
      batch: true,
      singleSubmission: true,
      requestParams: [sqdata],
    );
    _check();
    final reply = await client.postAction(
      app: CampusJobProgram.workStudy.app,
      appId: CampusJobProgram.workStudy.appId,
      path: 'modules/ksqgw/xzxssgdz.do',
      form: {
        '0da20ab7_bf71_43c9_a3f2_3ec9166bac84': jsonEncode(sqdata),
        '7222ea39_d3b5_4750_a9a8_b3c15c0aa09d': jsonEncode(sgxxData),
      },
      singleSubmission: true,
    );
    _check();
    if (_isRejectedReply(reply)) {
      throw const CampusRequestException(CampusErrorKind.rejected, '勤工助学申请未通过学校校验，请在网页核对');
    }
    try {
      await client.postAction(
        app: CampusJobProgram.workStudy.app,
        appId: CampusJobProgram.workStudy.appId,
        path: 'modules/sendmail/GwsqSentMassage.do',
        singleSubmission: true,
      );
    } on CampusRequestException catch (e) {
      if (e.kind == CampusErrorKind.sessionExpired || e.kind == CampusErrorKind.idsNotBound) {
        rethrow;
      }
    } catch (_) {}
    _check();
    return '勤工助学申请已提交';
  }
}
