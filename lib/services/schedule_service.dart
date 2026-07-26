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
  TermCalendar? _termCalendar;
  String? _selectedSemesterId;
  bool _loading = false;
  String? _error;
  // While true, AssignmentService should NOT refetch on our notifies —
  // selectSemester sets this during its own network fetch to avoid a
  // concurrent exam_table + course_table race on EAMS's stateful session.
  bool _suppressAssignmentRefetch = false;
  bool get suppressAssignmentRefetch => _suppressAssignmentRefetch;

  String get _baseUrl => apiBaseUrl(_storage);

  // Fallback used before the school calendar has been fetched at least once.
  static const _fallbackTotalWeeks = 25;

  SemesterInfo? get semesterInfo => _semesterInfo;
  CourseTable? get courseTable => _courseTable;
  TermCalendar? get termCalendar => _termCalendar;
  DateTime? get termBegin => _termCalendar?.termBegin;
  String? get selectedSemesterId => _selectedSemesterId;
  bool get loading => _loading;
  String? get error => _error;

  /// Teaching weeks in the selected semester, i.e. the upper bound for week
  /// navigation. Falls back to a generous default until the calendar loads.
  int get totalWeeks =>
      (_termCalendar?.allTeachWeeks ?? 0) > 0
          ? _termCalendar!.allTeachWeeks
          : _fallbackTotalWeeks;

  ScheduleService(this._storage, this._http, AuthService _, this._tpAuth);

  int currentWeek() {
    final begin = termBegin;
    if (begin == null) return 1;
    final diff = DateTime.now().difference(begin).inDays;
    if (diff < 0) return 1;
    return ((diff ~/ 7) + 1).clamp(1, totalWeeks).toInt();
  }

  /// Whether "today" actually falls within the selected semester — false
  /// before the calendar has loaded, before the term begins, or after its
  /// last teaching week. Callers should hide "this week"/"today" indicators
  /// when this is false, since there is no meaningful "current week".
  bool get isTodayInTerm {
    final begin = termBegin;
    if (begin == null) return false;
    final diff = DateTime.now().difference(begin).inDays;
    if (diff < 0) return false;
    final week = (diff ~/ 7) + 1;
    return week <= totalWeeks;
  }

  Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json; charset=UTF-8',
      };

  /// Auth payload built from a [CookieProvider] snapshot captured at request
  /// time. The epoch captured alongside is what makes the renew-retry
  /// storm-safe (see [_postWithRetry]).
  Map<String, dynamic> _authBody(CookieProvider cp) => {
        // eams downstream cookie; studentId comes from the cpdaily binding.
        'studentId': _tpAuth.cpdailyNode.account?.sid ?? '',
        'cookies': cp.cookies,
      };

  bool get _hasCpdailyBinding => _tpAuth.cpdailyNode.isAvailable;

  Future<void> loadCachedData() async {
    _semesterInfo = _storage.loadSemesters();
    _selectedSemesterId =
        _storage.selectedSemester ?? _semesterInfo?.defaultSemester;
    if (_selectedSemesterId != null) {
      _courseTable = _storage.loadCourseTable(_selectedSemesterId!);
    }
    _termCalendar = _storage.loadTermCalendar(_selectedSemesterId ?? '');
    notifyListeners();
  }

  Future<void> fetchAll() async {
    if (_loading) return; // 避免启动时并发重复调用
    if (!_hasCpdailyBinding) return;
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
          // rank 0/1/2 (秋/春/暑) -> the term number the backend expects (1/2/3);
          // unrecognized term keys fall back to spring (2).
          final rank = semesterTermRank(semEntry.key);
          semNum = rank < kSemesterTermNames.length
              ? (rank + 1).toString()
              : '2';
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

    _termCalendar = TermCalendar.fromJson(data['data'] as Map<String, dynamic>);
    await _storage.saveTermCalendar(cacheKey, _termCalendar!);
    notifyListeners();
  }

  Future<void> selectSemester(String semesterId) async {
    // No-op if the semester is already selected.
    if (_selectedSemesterId == semesterId) return;
    _selectedSemesterId = semesterId;
    await _storage.setSelectedSemester(semesterId);

    // Load cached data for the new semester so the UI updates instantly.
    _courseTable = _storage.loadCourseTable(semesterId);
    _termCalendar = _storage.loadTermCalendar(semesterId);
    // Notify the cached-swap UI update. AssignmentService._onScheduleChanged
    // sees the semester changed and would fire fetchAssignments here — but
    // that would race our own fetchCourseTable below (both hit
    // courseTableForStd.action on the same EAMS session, and concurrent
    // access to EAMS's stateful Spring/Struts session returns a partially
    // initialized page → "Failed to extract numeric ids"). We suppress the
    // assignment refetch during our own fetch and fire it once at the end.
    _suppressAssignmentRefetch = true;
    notifyListeners();

    if (!_hasCpdailyBinding) {
      _suppressAssignmentRefetch = false;
      return;
    }

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
      _suppressAssignmentRefetch = false;
      // This final notify fires _onScheduleChanged again. Because
      // _suppressAssignmentRefetch is now false, AssignmentService will
      // refetch (the EAMS session is primed by our fetchCourseTable above,
      // so exam_table succeeds on the first try).
      notifyListeners();
    }
  }

  /// POST [url] with CpDaily auth + [extra] body fields. On 401 the eams
  /// node is renewed exactly once (single-flighted across all concurrent
 /// callers) and the request retried with the fresh cookie. For a stale
 /// parent tgc, [SessionTree.withCookie] falls back to renewing the
 /// cpdaily parent then re-minting the eams cookie. Throws on any non-200
 /// after the retry budget is exhausted.
  Future<http.Response> _postWithRetry(
    String url,
    Map<String, dynamic> extra,
    String tag,
  ) async {
    final node = _tpAuth.eamsNode;
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
      throw Exception('cpdaily session unavailable');
    }
    if (resp.statusCode != 200) {
      throw Exception('Request failed with status ${resp.statusCode}');
    }
    return resp;
  }
}
