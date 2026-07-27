import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_base_url.dart';
import 'auth_service.dart';
import 'session/session_tree.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

class EgateAppException implements Exception {
  final String message;
  EgateAppException(this.message);

  @override
  String toString() => message;
}

/// One row of the student's egate-app (xshdapp) sign-in history.
class EgateAppSignRecord {
  final String wid;
  final String activityName;
  final String typeDisplay;
  final String statusDisplay;
  final String? date;

  const EgateAppSignRecord({
    required this.wid,
    required this.activityName,
    required this.typeDisplay,
    required this.statusDisplay,
    this.date,
  });

  factory EgateAppSignRecord.fromJson(Map<String, dynamic> json) {
    return EgateAppSignRecord(
      wid: json['WID'] as String? ?? '',
      activityName: json['HDMC'] as String? ?? '',
      typeDisplay: json['HDLX_DISPLAY'] as String? ?? '',
      statusDisplay: json['HDZT_DISPLAY'] as String? ?? '',
      date: json['SQRQ'] as String?,
    );
  }
}

class EgateAppCheckinResult {
  final bool success;
  final String message;

  const EgateAppCheckinResult({required this.success, required this.message});
}

/// Native "校园签到" feature: queries the egate-app (xshdapp) sign-in
/// announcement + history, and submits a check-in for a scanned WID. Session
/// cookies (MOD_AUTH_CAS/_WEU) are derived from the cpdaily CASTGC via
/// [ThirdPartyAuthService.egateAppNode], the same pattern AssignmentService
/// uses for eams/elearning.
class EgateAppService extends ChangeNotifier {
  final AuthService _auth;
  final StorageService _storage;
  final ThirdPartyAuthService _tpAuth;
  final http.Client _client;

  EgateAppService(
    this._auth,
    this._storage,
    this._tpAuth, {
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get _baseUrl => apiBaseUrl(_storage);

  /// Guard for any egate-app call: requires a logged-in primary account AND
  /// a bound cpdaily account (the source of the CASTGC that egate-app's
  /// session is derived from).
  void _requireReady() {
    if (!_auth.isLoggedIn) {
      throw EgateAppException('请先登录 TechPie 主账号');
    }
    if (!_tpAuth.hasCpdailyBinding) {
      throw EgateAppException('校园签到需要绑定 eGate 账号，请在「第三方账号」中绑定');
    }
  }

  Future<String> fetchSignMessage() async {
    final data = await _postJson('egate-app/message', const {});
    return (data['data'] as Map?)?['message'] as String? ?? '';
  }

  Future<List<EgateAppSignRecord>> fetchSignHistory() async {
    final studentId = _tpAuth.cpdailyStudentId;
    if (studentId.isEmpty) {
      throw EgateAppException('当前 eGate 绑定缺少学号，请重新绑定 eGate');
    }
    final data = await _postJson('egate-app/history', {'studentId': studentId});
    final rows = (data['data'] as Map?)?['rows'] as List<dynamic>? ?? const [];
    return rows
        .map((row) => EgateAppSignRecord.fromJson((row as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<EgateAppCheckinResult> submitCheckin(String wid) async {
    if (wid.isEmpty) {
      throw EgateAppException('签到内容不能为空');
    }
    final data = await _postJson('egate-app/checkin', {'wid': wid});
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    // Upstream response shape isn't fully confirmed yet — surface whatever
    // text came back so the user can see the server's actual reply.
    final raw = payload['raw'] as String? ?? '';
    return EgateAppCheckinResult(
      success: raw.isNotEmpty,
      message: raw.isNotEmpty ? raw : '签到请求已提交',
    );
  }

  /// POST `$_baseUrl/[path]` with the egate-app derived cookie + [extra] body
  /// fields. On 401 the egateApp node (and, if its own tgc turns out stale,
  /// the parent cpdaily node) is renewed via [SessionTree.withCookie]'s
  /// two-level retry, then the request is retried once.
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> extra,
  ) async {
    _requireReady();
    final node = _tpAuth.egateAppNode;
    final response = await _tpAuth.sessionTree.withCookie<http.Response>(
      node,
      (cp) async {
        final body = {...extra, 'cookies': cp.cookies};
        final r = await _client
            .post(
              Uri.parse('$_baseUrl/$path'),
              headers: const {
                'Content-Type': 'application/json; charset=UTF-8',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));
        return CookieAction(r, expired: r.statusCode == 401);
      },
    );
    if (response == null) {
      throw EgateAppException('当前 eGate 登录态已失效，请重新绑定 eGate');
    }
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(response.body) as Map).cast<String, dynamic>();
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] == false) {
      throw EgateAppException(
        decoded['error'] as String? ?? '校园签到服务请求失败，请稍后重试',
      );
    }
    return decoded;
  }
}
