import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/course_table.dart';
import 'auth_service.dart';
import 'http_client.dart';
import 'storage_service.dart';

const String _devBaseUrl = 'http://localhost:3000/api';
const String _prodBaseUrl = 'https://techpie.geekpie.club/api';

class ScheduleService extends ChangeNotifier {
  final StorageService _storage;
  final LoggingHttpClient _http;
  final AuthService _auth;

  SemesterInfo? _semesterInfo;
  CourseTable? _courseTable;
  DateTime? _termBegin;
  String? _selectedSemesterId;
  bool _loading = false;
  String? _error;

  String get _baseUrl => _storage.useLocalhost ? _devBaseUrl : _prodBaseUrl;

  SemesterInfo? get semesterInfo => _semesterInfo;
  CourseTable? get courseTable => _courseTable;
  DateTime? get termBegin => _termBegin;
  String? get selectedSemesterId => _selectedSemesterId;
  bool get loading => _loading;
  String? get error => _error;

  ScheduleService(this._storage, this._http, this._auth);

  int currentWeek() {
    if (_termBegin == null) return 1;
    final diff = DateTime.now().difference(_termBegin!).inDays;
    if (diff < 0) return 1;
    return ((diff ~/ 7) + 1).clamp(1, 25).toInt();
  }

  Map<String, String> _jsonHeaders() => {
    'Content-Type': 'application/json; charset=UTF-8',
  };

  Map<String, dynamic> _authBody() {
    final session = _auth.session!;
    // Ensure CASTGC (tgc) is included in the cookies sent to EAMS
    final baseCookies = session.cookies;
    final tgc = session.tgc;
    final cookies = tgc.isNotEmpty
        ? (baseCookies.isNotEmpty ? '$baseCookies; CASTGC=$tgc' : 'CASTGC=$tgc')
        : baseCookies;
    return {'studentId': session.studentId, 'cookies': cookies};
  }

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
    if (!_auth.isLoggedIn) return;
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
      _authBody(),
      'fetchSemesters',
    );
    if (resp == null) return;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] as String? ?? 'Failed to fetch semesters');
    }

    _semesterInfo = SemesterInfo.fromJson(data['data'] as Map<String, dynamic>);
    _storage.saveSemesters(_semesterInfo!);
    notifyListeners();
  }

  Future<void> fetchCourseTable(String semesterId) async {
    final body = {
      ..._authBody(),
      'semester_id': semesterId,
      if (_semesterInfo?.tableId.isNotEmpty == true)
        'table_id': _semesterInfo!.tableId,
    };

    final resp = await _postWithRetry(
      '$_baseUrl/schedule/course_table',
      body,
      'fetchCourseTable',
    );
    if (resp == null) return;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(
        data['error'] as String? ?? 'Failed to fetch course table',
      );
    }

    _courseTable = CourseTable.fromApiResponse(
      data['data'] as Map<String, dynamic>,
    );
    _storage.saveCourseTable(semesterId, _courseTable!);
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
    final body = {..._authBody(), 'year': year, 'semester': semester};

    final resp = await _postWithRetry(
      '$_baseUrl/schedule/term_begin',
      body,
      'fetchTermBegin',
    );
    if (resp == null) return;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] as String? ?? 'Failed to fetch term begin');
    }

    final dateStr = data['data'] as String;
    _termBegin = DateTime.tryParse(dateStr);
    if (_termBegin != null) {
      _storage.saveTermBegin(cacheKey, _termBegin!);
    }
    notifyListeners();
  }

  Future<void> selectSemester(String semesterId) async {
    _selectedSemesterId = semesterId;
    _storage.setSelectedSemester(semesterId);
    notifyListeners();

    // Load cached data for new semester first
    _courseTable = _storage.loadCourseTable(semesterId);
    _termBegin = _storage.loadTermBegin(semesterId);
    notifyListeners();

    if (!_auth.isLoggedIn) return;

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

  Future<dynamic> _postWithRetry(
    String url,
    Map<String, dynamic> body,
    String tag,
  ) async {
    var resp = await _http.post(
      Uri.parse(url),
      headers: _jsonHeaders(),
      body: jsonEncode(body),
      tag: tag,
    );

    if (resp.statusCode == 401) {
      final renewed = await _auth.tryRenewSession();
      if (renewed) {
        // Rebuild body with refreshed session
        final newBody = {...body, ..._authBody()};
        resp = await _http.post(
          Uri.parse(url),
          headers: _jsonHeaders(),
          body: jsonEncode(newBody),
          tag: '$tag-retry',
        );
      }
    }

    if (resp.statusCode != 200) {
      throw Exception('Request failed with status ${resp.statusCode}');
    }

    return resp;
  }
}
