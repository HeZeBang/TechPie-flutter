import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/course_table.dart';
import 'api_base_url.dart';
import 'auth_service.dart';
import 'http_client.dart';
import 'session/cookie_provider.dart';
import 'session/session_tree.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

class ScheduleService extends ChangeNotifier {
  final StorageService _storage;
  final LoggingHttpClient _http;
  final ThirdPartyAuthService _tpAuth;

  SemesterInfo? _semesterInfo;
  CourseTable? _courseTable;
  DateTime? _termBegin;
  String? _selectedSemesterId;
  bool _loading = false;
  String? _error;

  String get _baseUrl => apiBaseUrl(_storage);

  SemesterInfo? get semesterInfo => _semesterInfo;
  CourseTable? get courseTable => _courseTable;
  DateTime? get termBegin => _termBegin;
  String? get selectedSemesterId => _selectedSemesterId;
  bool get loading => _loading;
  String? get error => _error;

  ScheduleService(this._storage, this._http, AuthService _, this._tpAuth);

  int currentWeek() {
    if (_termBegin == null) return 1;
    final diff = DateTime.now().difference(_termBegin!).inDays;
    if (diff < 0) return 1;
    return ((diff ~/ 7) + 1).clamp(1, 25).toInt();
  }

  Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json; charset=UTF-8',
      };

  /// Auth payload built from a [CookieProvider] snapshot captured at request
  /// time. The epoch captured alongside is what makes the renew-retry
  /// storm-safe (see [_postWithRetry]).
  Map<String, dynamic> _authBody(CookieProvider cp) => {
        'studentId': cp.studentId,
        'cookies': cp.cookies,
      };

  bool get _hasEgateBinding => _tpAuth.egateNode.isAvailable;

  Future<void> loadCachedData() async {
    _semesterInfo = _storage.loadSemesters();
    _selectedSemesterId =
        _storage.selectedSemester ?? _semesterInfo?.defaultSemester;
    if (_selectedSemesterId != null) {
      _courseTable = _storage.loadCourseTable(_selectedSemesterId!);
    }
    _termBegin = _storage.loadTermBegin(_selectedSemesterId ?? '');
    notifyListeners();
  }

  Future<void> fetchAll() async {
    if (_loading) return; // 避免启动时并发重复调用
    if (!_hasEgateBinding) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await fetchSemesters();
      _selectedSemesterId ??= _semesterInfo?.defaultSemester;
      if (_selectedSemesterId != null) {
        await Future.wait([
          fetchCourseTable(_selectedSemesterId!),
          _fetchTermBeginForSemester(_selectedSemesterId!),
        ]);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> fetchSemesters() async {
    final resp = await _postWithRetry(
      '$_baseUrl/schedule/semesters',
      const <String, dynamic>{},
      'fetchSemesters',
    );
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] as String? ?? 'Failed to fetch semesters');
    }

    _semesterInfo = SemesterInfo.fromJson(data['data'] as Map<String, dynamic>);
    await _storage.saveSemesters(_semesterInfo!);
    notifyListeners();
  }

  Future<void> fetchCourseTable(String semesterId) async {
    final extra = <String, dynamic>{
      'semester_id': semesterId,
      if (_semesterInfo?.tableId.isNotEmpty == true)
        'table_id': _semesterInfo!.tableId,
    };

    final resp = await _postWithRetry(
      '$_baseUrl/schedule/course_table',
      extra,
      'fetchCourseTable',
    );
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(
        data['error'] as String? ?? 'Failed to fetch course table',
      );
    }

    _courseTable = CourseTable.fromApiResponse(
      data['data'] as Map<String, dynamic>,
    );
    await _storage.saveCourseTable(semesterId, _courseTable!);
    notifyListeners();
  }

  Future<void> _fetchTermBeginForSemester(String semesterId) async {
    // Try to find the year and semester number from semesterInfo
    if (_semesterInfo == null) return;

    String? year;
    String? semNum;
    for (final yearEntry in _semesterInfo!.semesters.entries) {
      for (final semEntry in yearEntry.value.entries) {
        if (semEntry.value == semesterId) {
          // yearEntry.key is like "2024-2025"
          year = yearEntry.key.split('-').first;
          // Map label to number
          semNum = semEntry.key.contains('春') ? '1' : '2';
          break;
        }
      }
      if (year != null) break;
    }

    if (year == null || semNum == null) return;
    await fetchTermBegin(year, semNum, semesterId);
  }

  Future<void> fetchTermBegin(
    String year,
    String semester,
    String cacheKey,
  ) async {
    final extra = <String, dynamic>{'year': year, 'semester': semester};

    final resp = await _postWithRetry(
      '$_baseUrl/schedule/term_begin',
      extra,
      'fetchTermBegin',
    );
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] as String? ?? 'Failed to fetch term begin');
    }

    final dateStr = data['data'] as String;
    _termBegin = DateTime.tryParse(dateStr);
    if (_termBegin != null) {
      await _storage.saveTermBegin(cacheKey, _termBegin!);
    }
    notifyListeners();
  }

  Future<void> selectSemester(String semesterId) async {
    _selectedSemesterId = semesterId;
    await _storage.setSelectedSemester(semesterId);
    notifyListeners();

    // Load cached data for new semester first
    _courseTable = _storage.loadCourseTable(semesterId);
    _termBegin = _storage.loadTermBegin(semesterId);
    notifyListeners();

    if (!_hasEgateBinding) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.wait([
        fetchCourseTable(semesterId),
        _fetchTermBeginForSemester(semesterId),
      ]);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// POST [url] with CpDaily auth + [extra] body fields. On 401 the egate
  /// node is renewed exactly once (single-flighted across all concurrent
 /// callers) and the request retried with the fresh cookie. Throws on any
  /// non-200 after the retry budget is exhausted.
  Future<http.Response> _postWithRetry(
    String url,
    Map<String, dynamic> extra,
    String tag,
  ) async {
    final node = _tpAuth.egateNode;
    final resp = await _tpAuth.sessionTree.withCookie<http.Response>(
      node,
      (cp) async {
        final body = {..._authBody(cp), ...extra};
        final r = await _http.post(
          Uri.parse(url),
          headers: _jsonHeaders(),
          body: jsonEncode(body),
          tag: tag,
        );
        return CookieAction(
          r,
          expired: r.statusCode == 401,
        );
      },
    );
    if (resp == null) {
      throw Exception('eGate session unavailable');
    }
    if (resp.statusCode != 200) {
      throw Exception('Request failed with status ${resp.statusCode}');
    }
    return resp;
  }
}
