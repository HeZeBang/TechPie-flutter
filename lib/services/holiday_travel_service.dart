import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/holiday_travel.dart';
import 'campus/campus_errors.dart';
import 'campus/emap_account_cache.dart';
import 'campus/emap_client.dart';
import 'storage_service.dart';

class HolidayTravelService extends EmapAccountCache {
  HolidayTravelService(this.client, StorageService storage, Listenable accounts)
      : super('holiday_travel', storage, client.session.identity, accounts);
  final EmapClient client;
  static const app = 'jjrlfxapp', appId = '4646764215281018';
  List<HolidayTravel> get history => (values['history'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .map(HolidayTravel.new)
      .toList();

  static String _formatDay(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static bool _isRejected(Map<String, dynamic> result) =>
      '${result['code']}' == '-1' ||
      '${result['msg']}'.toLowerCase() == 'false' ||
      result['success'] == false;

  Future<void> refresh() async {
    final rev = revision;
    final records = <Map<String, String>>[];
    for (var page = 1;; page++) {
      check(rev);
      final result = await client.queryModel(
        app: app,
        appId: appId,
        module: 'register',
        model: 'xsdjlsjlbg',
        pageNumber: page,
        pageSize: 50,
        allowMissingTotalSize: true,
      );
      for (final row in result.rows) {
        final selected = HolidayTravel(row).fields;
        selected.remove('JJLXRDH');
        records.add(selected);
      }
      if (result.rows.length < 50 ||
          (result.totalSize >= 0 && records.length >= result.totalSize)) {
        break;
      }
    }
    await save(rev, 'history', records);
  }

  Future<HolidayTravel> loadDestination(HolidayTravel previous, int expectedRevision) async {
    check(expectedRevision);
    final recordId = previous['WID'];
    if (recordId.isEmpty) return previous;
    final batch = previous['DJWID'];
    for (var page = 1;; page++) {
      check(expectedRevision);
      final result = await client.queryModel(
        app: app,
        appId: appId,
        module: 'register',
        model: 'xsbgdjbd',
        pageNumber: page,
        pageSize: 50,
        extraForm: {
          'WID': recordId,
          if (batch.isNotEmpty) 'DJWID': batch,
        },
        allowMissingTotalSize: true,
      );
      check(expectedRevision);
      for (final row in result.rows) {
        final form = HolidayTravel(row);
        // A shared DJWID alone does not establish which personal form was selected.
        if (form['WID'] == recordId &&
            (batch.isEmpty || form['DJWID'].isEmpty || form['DJWID'] == batch)) {
          return HolidayTravel({...previous.fields, ...form.fields});
        }
      }
      if (result.rows.length < 50 || (result.totalSize >= 0 && page * 50 >= result.totalSize)) {
        return previous;
      }
    }
  }

  /// Submits a holiday departure registration once with date and contact validation.
  Future<void> submitDeparture({
    required String holidayCode,
    String academicYear = '',
    String batchId = '',
    String reasonCode = '',
    required DateTime departure,
    required DateTime expectedReturn,
    required String province,
    required String city,
    required String district,
    required String address,
    required String emergencyPhone,
    bool abroad = false,
    required int expectedRevision,
  }) async {
    check(expectedRevision);
    if (!HolidayTravel.validDates(departure, expectedReturn)) {
      throw const FormatException('离校日期不能晚于预计返校日期');
    }
    if (address.trim().isEmpty) {
      throw const FormatException('请填写详细去向地址');
    }
    if (emergencyPhone.trim().isEmpty) {
      throw const FormatException('请填写紧急联系人电话');
    }
    final payload = <String, String>{
      if (holidayCode.trim().isNotEmpty) 'JJRDM': holidayCode.trim(),
      if (academicYear.trim().isNotEmpty) 'DJXN': academicYear.trim(),
      if (batchId.trim().isNotEmpty) 'DJWID': batchId.trim(),
      if (reasonCode.trim().isNotEmpty) 'LXYYDM': reasonCode.trim(),
      'LXRQ': _formatDay(departure),
      'YJFXRQ': _formatDay(expectedReturn),
      'QXSF': province.trim(),
      'QXCS': city.trim(),
      'QXQX': district.trim(),
      'QXDZ': address.trim(),
      'YL5': province.trim(),
      'YL6': city.trim(),
      'YL7': district.trim(),
      'YL4': address.trim(),
      'YL8': abroad ? '1' : '0',
      'JJLXRDH': emergencyPhone.trim(),
    };
    final result = await client.postAction(
      app: app,
      appId: appId,
      path: 'modules/holiday/SaveRegister.do',
      form: {'data': jsonEncode(payload)},
      singleSubmission: true,
    );
    check(expectedRevision);
    if (_isRejected(result)) {
      throw const CampusRequestException(
        CampusErrorKind.rejected,
        '学校未接受离返校登记，请核对表单或前往网页提交',
      );
    }
  }

  /// Submits a return confirmation for an existing registration record once.
  Future<void> submitReturn({
    required String recordId,
    required DateTime returnDate,
    String note = '',
    required int expectedRevision,
  }) async {
    check(expectedRevision);
    if (recordId.trim().isEmpty) {
      throw const FormatException('缺少登记记录编号');
    }
    final rows = [
      <String, String>{
        'WID': recordId.trim(),
        'FXRQ': _formatDay(returnDate),
        if (note.trim().isNotEmpty) 'BZ': note.trim(),
      },
    ];
    final result = await client.postAction(
      app: app,
      appId: appId,
      path: 'modules/return/T_JJR_FXDJ_SAVE.do',
      form: {'T_JJR_FXDJ_SAVE': jsonEncode(rows)},
      singleSubmission: true,
    );
    check(expectedRevision);
    if (_isRejected(result)) {
      throw const CampusRequestException(
        CampusErrorKind.rejected,
        '返校登记未成功，请前往校园网页核对',
      );
    }
  }
}
