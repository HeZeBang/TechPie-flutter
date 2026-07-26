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
  // While true, AssignmentService should NOT refetch on our notifies —
  // selectSemester sets this during its own network fetch to avoid a
  // concurrent exam_table + course_table race on EAMS's stateful session.
  bool _suppressAssignmentRefetch = false;
  bool get suppressAssignmentRefetch => _suppressAssignmentRefetch;

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
    _termBegin = _storage.loadTermBegin(_selectedSemesterId ?? '');
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

  /// Live, non-mutating fetch of the semester list. Mirrors [fetchSemesters]
  /// but returns the parsed [SemesterInfo] instead of writing it into
  /// [_semesterInfo] and never notifies. Used by the AI tools so a query about
  /// available terms doesn't touch the UI's selected-semester state.
  Future<SemesterInfo> fetchSemestersLive() async {
    final resp = await _postWithRetry(
      '$_baseUrl/schedule/semesters',
      const <String, dynamic>{},
      'fetchSemestersLive',
    );
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] as String? ?? 'Failed to fetch semesters');
    }
    return SemesterInfo.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// Live, non-mutating fetch of one semester's course table. Mirrors
  /// [fetchCourseTable] but returns the parsed [CourseTable] instead of
  /// writing it into [_courseTable] and never notifies. The AI tools use this
  /// (via [courseTableFor]) to read an arbitrary semester (e.g. a
  /// non-selected one) without polluting the UI's selected-semester view. The
  /// table_id is best-effort: sent only when [_semesterInfo] is available.
  Future<CourseTable> fetchCourseTableLive(String semesterId) async {
    final tableId = _semesterInfo?.tableId;
    final extra = <String, dynamic>{
      'semester_id': semesterId,
      if (tableId != null && tableId.isNotEmpty) 'table_id': tableId,
    };
    final resp = await _postWithRetry(
      '$_baseUrl/schedule/course_table',
      extra,
      'fetchCourseTableLive',
    );
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(
        data['error'] as String? ?? 'Failed to fetch course table',
      );
    }
    return CourseTable.fromApiResponse(data['data'] as Map<String, dynamic>);
  }

  /// Cache-first semester list for read-only consumers (AI tools): in-memory
  /// [_semesterInfo] → storage → live fetch (written back to storage only,
  /// never into [_semesterInfo], so UI state is untouched).
  Future<SemesterInfo> semestersCachedOrLive({bool refresh = false}) async {
    if (!refresh) {
      final cached = _semesterInfo ?? _storage.loadSemesters();
      if (cached != null) return cached;
    }
    final info = await fetchSemestersLive();
    await _storage.saveSemesters(info);
    return info;
  }

  /// Cache-first course table for an arbitrary semester. Storage is keyed per
  /// semester, so a non-selected (e.g. past) semester hits its own cache
  /// entry — the old AI-tool bug came from reading the in-memory
  /// [_courseTable], which only ever holds the selected semester. On miss (or
  /// [refresh]) fetches live and writes back to storage only, never into
  /// [_courseTable], so querying another semester can't pollute the UI.
  Future<CourseTable> courseTableFor(
    String semesterId, {
    bool refresh = false,
  }) async {
    if (!refresh) {
      final cached = _storage.loadCourseTable(semesterId);
      if (cached != null) return cached;
    }
    final table = await fetchCourseTableLive(semesterId);
    await _storage.saveCourseTable(semesterId, table);
    return table;
  }

  /// Cached term-begin date for [semesterId], if any (storage is per-semester
  /// keyed). Used to derive a default week for non-selected semesters.
  DateTime? termBeginFor(String semesterId) =>
      _storage.loadTermBegin(semesterId);

  Future<void> selectSemester(String semesterId) async {
    // No-op if the semester is already selected.
    if (_selectedSemesterId == semesterId) return;
    _selectedSemesterId = semesterId;
    await _storage.setSelectedSemester(semesterId);

    // Load cached data for the new semester so the UI updates instantly.
    _courseTable = _storage.loadCourseTable(semesterId);
    _termBegin = _storage.loadTermBegin(semesterId);
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
