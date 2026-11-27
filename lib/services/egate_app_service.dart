import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'campus/campus_clients.dart';
import 'campus/campus_errors.dart';
import 'campus/emap_account_cache.dart';
import 'campus/emap_client.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

Map<String, String> _select(Map<String, dynamic> row, List<String> keys) => {
      for (final key in keys)
        if (row[key] is String || row[key] is num || row[key] is bool) key: row[key].toString(),
    };

class EgateActivity {
  EgateActivity(Map<String, dynamic> row)
      : fields = _select(row, const [
          'WID',
          'HDBH',
          'HDMC',
          'HDLX',
          'HDLX_DISPLAY',
          'HDSJ',
          'HDDD',
          'HDJS',
          'CJRS',
          'HDRS',
          'SFBM',
          'SFBM_DISPLAY',
          'BMZT',
          'BMZT_DISPLAY',
          'HDJB',
          'HDJB_DISPLAY',
        ]);
  final Map<String, String> fields;
  String operator [](String k) => fields[k] ?? '';
  String get id => this['HDBH'].isNotEmpty ? this['HDBH'] : this['WID'];
  String get name => this['HDMC'];
  String get status => [
        this['BMZT_DISPLAY'],
        this['SFBM_DISPLAY'],
        this['BMZT'],
        this['SFBM'],
      ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
  bool get canRegister =>
      id.isNotEmpty &&
      !registered &&
      const {'可报名', '允许报名', '可以报名', '未报名', '报名中', '立即报名', '进行中'}.contains(status);
  bool get registered => status == '已报名' || this['SFBM_DISPLAY'] == '已报名' || this['SFBM'] == '已报名';
}

class EgateAppSignRecord {
  EgateAppSignRecord.fromJson(Map<String, dynamic> row)
      : fields = _select(row, const [
          'WID',
          'HDBH',
          'HDMC',
          'HDLX_DISPLAY',
          'HDZT_DISPLAY',
          'SQRQ',
          'RCQD',
          'LCQD',
          'RCQD_DISPLAY',
          'LCQD_DISPLAY',
        ]);
  final Map<String, String> fields;
  String get activityName => fields['HDMC'] ?? '';
  String get typeDisplay => fields['HDLX_DISPLAY'] ?? '';
  String get statusDisplay => fields['HDZT_DISPLAY'] ?? '';
  String? get date => fields['SQRQ'];
  String get entrance => fields['RCQD_DISPLAY'] ?? fields['RCQD'] ?? '';
  String get exit => fields['LCQD_DISPLAY'] ?? fields['LCQD'] ?? '';
}

class EgateAppService extends EmapAccountCache {
  // Independent embedders can still construct an activity service from their
  // account services. The application injects its shared EMAP client below.
  factory EgateAppService(
    AuthService auth,
    StorageService storage,
    ThirdPartyAuthService bindings,
  ) {
    final clients = CampusClients(auth, bindings);
    return EgateAppService.withClient(
      clients.emap,
      storage,
      Listenable.merge([auth, bindings]),
      () => bindings.idsStudentId,
    ).._ownedClients = clients;
  }
  EgateAppService.withClient(
    this.client,
    StorageService storage,
    Listenable accounts,
    this.studentId,
  ) : super('student_activities', storage, client.session.identity, accounts);
  CampusClients? _ownedClients;
  final EmapClient client;
  final String Function() studentId;
  static const _app = 'xshdapp', _id = '4770201649822494';
  List<Map<String, dynamic>> _cached(String key) =>
      (values[key] as List? ?? []).whereType<Map<String, dynamic>>().toList();
  List<EgateActivity> get recent => _cached('recent').map(EgateActivity.new).toList();
  List<EgateActivity> get all => _cached('all').map(EgateActivity.new).toList();
  List<EgateAppSignRecord> get history =>
      _cached('history').map(EgateAppSignRecord.fromJson).toList();

  Future<String> fetchSignMessage() async {
    final data =
        (await client.getAction(app: _app, appId: _id, path: 'xshdApply/dqnxxqgrhz.do'))['data'];
    if (data is! List) throw CampusRequestException.invalid;
    return data
        .whereType<Map<String, dynamic>>()
        .map((r) => r['BT'])
        .whereType<String>()
        .join('\n');
  }

  Future<List<EgateAppSignRecord>> fetchSignHistory() async {
    final rev = revision;
    final student = studentId();
    if (student.isEmpty) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请重新绑定含学号的 IDS 账号');
    }
    // The old controller guarantees rows but does not require totalSize in
    // its response. Preserve compatibility with both model shapes.
    final records = <EgateAppSignRecord>[];
    for (var page = 1; page <= 20; page++) {
      check(rev);
      final result = await client.queryModel(
        app: _app,
        appId: _id,
        module: 'hdll',
        model: 'cxhdsqxx',
        pageSize: 50,
        pageNumber: page,
        extraForm: {'XSBH': student},
        allowMissingTotalSize: true,
      );
      records.addAll(result.rows.map(EgateAppSignRecord.fromJson));
      final hasExplicitTotal = result.totalSize != result.rows.length;
      if (result.rows.length < 50 || (hasExplicitTotal && records.length >= result.totalSize)) {
        break;
      }
    }
    await save(rev, 'history', records.map((r) => r.fields).toList());
    return records;
  }

  Future<List<EgateActivity>> fetchRecentActivities() async {
    final rev = revision;
    final result = await client.queryModel(
      app: _app,
      appId: _id,
      module: 'hdll',
      model: 'cxjqjxhd',
      pageSize: 50,
      allowMissingTotalSize: true,
    );
    final list = result.rows.map(EgateActivity.new).toList();
    await save(rev, 'recent', list.map((r) => r.fields).toList());
    return list;
  }

  Future<({List<EgateActivity> rows, bool hasNext})> fetchAllActivities(int page) async {
    final rev = revision;
    const size = 20;
    final result = await client.queryModel(
      app: _app,
      appId: _id,
      module: 'hdll',
      model: 'hdllxxcx',
      pageSize: size,
      pageNumber: page,
      allowMissingTotalSize: true,
    );
    final list = result.rows.map(EgateActivity.new).toList();
    if (page == 1) {
      await save(rev, 'all', list.map((r) => r.fields).toList());
    }
    return (
      rows: list,
      hasNext: (result.totalSize < 0 ||
              (result.totalSize == result.rows.length && result.rows.length == size))
          ? list.length == size
          : page * size < result.totalSize,
    );
  }

  Future<String> registerActivity(EgateActivity activity) async {
    if (!activity.canRegister) {
      throw const CampusRequestException(CampusErrorKind.rejected, '请在网页版确认报名资格');
    }
    final reply = await client.postAction(
      app: _app,
      appId: _id,
      path: 'MobileXshdController/xshdbm.do',
      form: {'HDBH': activity.id, 'FKPZ': ''},
      singleSubmission: true,
    );
    final data = reply['datas'];
    if (data is Map && data['MSG'] is String && (data['MSG'] as String).trim().isNotEmpty) {
      return data['MSG'] as String;
    }
    throw CampusRequestException.invalid;
  }

  Future<String> submitCheckin(String wid) async {
    if (wid.trim().isEmpty) {
      throw const CampusRequestException(CampusErrorKind.rejected, '签到内容不能为空');
    }
    final raw = (await client.submitTextOnce(
      app: _app,
      appId: _id,
      path: 'MobileXshdController/xsqd.do',
      form: {'WID': wid.trim()},
    ))
        .trim();
    if (raw.isEmpty) return '学校已接收请求，请刷新签到记录确认结果';
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map && parsed['datas'] is Map && (parsed['datas'] as Map)['MSG'] is String) {
        return (parsed['datas'] as Map)['MSG'] as String;
      }
    } on FormatException {
      return raw;
    }
    return raw;
  }

  @override
  void dispose() {
    super.dispose();
    _ownedClients?.dispose();
  }
}
