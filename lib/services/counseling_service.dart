import 'dart:convert';

import '../models/counseling_reservation.dart';
import 'campus/campus_errors.dart';
import 'campus/emap_client.dart';

/// Owned by one page and one account. Discard responses that finish after exit.
class CounselingService {
  CounselingService(this.client, this.studentId) : _owner = client.session.identity();
  final EmapClient client;
  final String studentId;
  final ({String? user, String? ids}) _owner;
  static const app = 'xljkapp', appId = '4689100415623139';
  static const module = 'mh_reservation_xs';
  static const webUrl = 'https://egate.shanghaitech.edu.cn/xsfw/sys/xljkapp/*default/index.do';
  static final _phonePattern = RegExp(r'^1\d{10}$');
  List<CounselingReservation> reservations = const [];
  bool _disposed = false;

  void _check() {
    if (_disposed || _owner != client.session.identity()) {
      dispose();
      throw CampusRequestException.expired;
    }
    if (_owner.user == null || (_owner.ids ?? '').trim().isEmpty) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请先登录并绑定 IDS');
    }
  }

  Future<List<Map<String, dynamic>>> _rows(String model, [Map<String, String>? form]) async {
    _check();
    final rows = <Map<String, dynamic>>[];
    for (var page = 1;; page++) {
      final result = await client.queryModel(
        app: app,
        appId: appId,
        module: module,
        model: model,
        pageNumber: page,
        pageSize: 100,
        extraForm: form,
        allowMissingTotalSize: true,
      );
      _check();
      rows.addAll(result.rows);
      if (result.rows.isEmpty ||
          (result.totalSize >= 0 ? rows.length >= result.totalSize : result.rows.length < 100)) {
        return rows;
      }
    }
  }

  Future<List<CounselingReservation>> myReservations() async {
    _check();
    if (studentId.isEmpty) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请绑定含学号的 IDS 账号');
    }
    final rows = await _rows('wdyyxx', {'userid': studentId});
    _check();
    return reservations = rows
        .where((row) => row['XSBH'] == null || '${row['XSBH']}' == studentId)
        .map(CounselingReservation.fromJson)
        .toList();
  }

  static bool validDate(String input) {
    final date = DateTime.tryParse(input);
    return date != null && date.toIso8601String().split('T').first == input;
  }

  static bool validPhone(String input) => _phonePattern.hasMatch(input.trim());

  Future<List<String>> dates() async {
    _check();
    final body = await client.postAction(
      app: app,
      appId: appId,
      path: 'modules/$module/getResDate.do',
      form: const {'pageNumber': '1', 'pageSize': '100'},
    );
    _check();
    if (body['code'] != null && '${body['code']}' != '0') {
      throw const CampusRequestException(CampusErrorKind.rejected, '学工系统未接受查询');
    }
    final datas = body['datas'];
    final Object? raw = switch (datas) {
      Map<Object?, Object?> m when m['getResDate'] is Map<Object?, Object?> =>
        (m['getResDate'] as Map<Object?, Object?>)['rows'],
      Map<Object?, Object?> m when m['getResDate'] is List<Object?> => m['getResDate'],
      List<Object?> l => l,
      _ => body['data'] ?? body['rows'],
    };
    if (raw is! List<Object?>) throw CampusRequestException.invalid;
    final found = <String>{};
    for (final entry in raw) {
      final candidate = switch (entry) {
        Map<Object?, Object?> m => m['YYRQ']?.toString().trim() ?? '',
        String s => s.trim(),
        _ => '',
      };
      if (validDate(candidate)) found.add(candidate);
    }
    return found.toList()..sort();
  }

  Future<List<CounselingSlot>> slots(String date) async {
    if (!validDate(date)) throw const FormatException('请选择有效日期');
    final rows = await _rows('zxsbd', {'YYRQ': date});
    return [for (final row in rows) CounselingSlot.fromJson(row)];
  }

  /// Books a counseling slot once for the current account visit without persistence.
  Future<void> bookSlot({
    required String date,
    required CounselingSlot slot,
    required String phone,
    String note = '',
  }) async {
    _check();
    if (studentId.isEmpty) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请绑定含学号的 IDS 账号');
    }
    if (!validDate(date)) throw const FormatException('请选择有效日期');
    if (!slot.isBookable) {
      throw const CampusRequestException(CampusErrorKind.rejected, '该时段暂不可预约');
    }
    if (!validPhone(phone)) throw const FormatException('请输入 11 位中国大陆手机号');

    final payload = <String, String>{
      'XSBH': studentId,
      'ZGH': slot.counselorId,
      'YYRQ': date,
      if (slot.campusCode.isNotEmpty) 'XQDM': slot.campusCode,
      if (slot.periodCode.isNotEmpty) 'SDDM': slot.periodCode,
      if (slot.periodLabel.isNotEmpty) 'SDMC': slot.periodLabel,
      'ZXSJ': slot.time.isNotEmpty ? slot.time : '$date ${slot.periodLabel}'.trim(),
      if (slot.place.isNotEmpty) 'YYDD': slot.place,
      'SJH': phone.trim(),
      if (note.trim().isNotEmpty) 'ZXWT': note.trim(),
    };
    final reply = await client.postAction(
      app: app,
      appId: appId,
      path: 'modules/$module/T_XG_ZXYY_ZXYY_ADD.do',
      form: {'T_XG_ZXYY_ZXYY_ADD': jsonEncode(payload)},
      singleSubmission: true,
    );
    _check();
    if ((reply['code'] != null && '${reply['code']}' != '0') ||
        reply['success'] == false ||
        (reply['returnCode'] != null && reply['returnCode'] != '#E000000000000')) {
      throw const CampusRequestException(CampusErrorKind.rejected, '预约未能提交，请在校园网页核对');
    }
  }

  void dispose() {
    _disposed = true;
    reservations = const [];
  }
}
