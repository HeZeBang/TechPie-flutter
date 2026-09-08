import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import '../models/third_party_account.dart';
import 'api_base_url.dart';
import 'auth_service.dart';
import 'http_client.dart';
import 'schedule_service.dart';
import 'session/session_failure.dart';
import 'session/session_tree.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

class AssignmentService extends ChangeNotifier {
  final StorageService _storage;
  final LoggingHttpClient _http;
  final AuthService _auth;
  final ThirdPartyAuthService _tpAuth;
  final ScheduleService _schedule;

  List<Assignment> _assignments = [];
  AssignmentOverrides _overrides = AssignmentOverrides();
  bool _loading = false;
  String? _error;
  // Per-platform error messages (keyed by lowercase platform id).
  final Map<String, String> _platformErrors = {};

  String get _baseUrl => apiBaseUrl(_storage);

  List<Assignment> get assignments => _assignments;

  /// Same list as [assignments] but with locally hidden ids filtered out.
  /// Use this in UI; use [assignments] only for places that need the raw
  /// (e.g. the hidden-list screen).
  List<Assignment> get visibleAssignments =>
      _assignments.where((a) => !_overrides.isHidden(a)).toList();

  AssignmentOverrides get overrides => _overrides;

  bool get loading => _loading;
  String? get error => _error;
  Map<String, String> get platformErrors => Map.unmodifiable(_platformErrors);

  bool isCompleted(Assignment a) => _overrides.effectiveCompleted(a);
  bool hasCompletionOverride(Assignment a) =>
      _overrides.hasCompletionOverride(a);
  bool isHidden(Assignment a) => _overrides.isHidden(a);

  AssignmentService(
    this._storage,
    this._http,
    this._auth,
    this._tpAuth,
    this._schedule,
  ) {
    // Refetch when bindings or auth change *after* initial app boot.
    // The initial fetch is kicked off explicitly from main.dart so we
    // don't double-fire during service initialization.
    _tpAuth.addListener(_onBindingsOrAuthChanged);
    _auth.addListener(_onBindingsOrAuthChanged);
    _schedule.addListener(_onScheduleChanged);
  }

  bool _autoRefetchEnabled = false;
  bool _pendingBindingFetch = false;
  int _request = 0;
  String? _bindingStamp;
  String get _currentStamp => '${_auth.isLoggedIn}:'
      '${_tpAuth.cpdailyNode.generation}:${_tpAuth.gradescopeNode.generation}:'
      '${_tpAuth.hydroNode.generation}';
  Map<String, String> get _owners => {
        if (_tpAuth.cpdailyNode.identityKey case final String owner) ...{
          'blackboard': '$owner:blackboard',
          'exam': '$owner:exam:${_schedule.selectedSemesterId ?? ""}',
        },
        if (_tpAuth.gradescopeNode.identityKey case final String owner)
          'gradescope': owner,
        if (_tpAuth.hydroNode.identityKey case final String owner)
          'hydro': '$owner:${_tpAuth.hydroNode.account?.hydroOrigin ?? ""}',
      };
  String get _overrideOwner => jsonEncode(_owners);

  // Track the last semester we refetched for, so schedule notifies that
  // don't change the semester (loading flips, course_table updates, errors)
  // do NOT trigger a redundant assignment refetch.
  String? _lastRefetchedSemesterId;

  /// Allow auto-refetch on auth/binding changes. Call after the first
  /// explicit fetch from app boot has been kicked off.
  void enableAutoRefetch() {
    _autoRefetchEnabled = true;
    _bindingStamp = _currentStamp;
    // Seed so the first schedule notify (which doesn't change the semester)
    // doesn't trigger a redundant refetch of the same semester.
    _lastRefetchedSemesterId = _schedule.selectedSemesterId;
  }

  /// Auth or binding changed — always refetch (tokens, accounts differ).
  void _onBindingsOrAuthChanged() {
    if (!_autoRefetchEnabled || _bindingStamp == _currentStamp) return;
    _bindingStamp = _currentStamp;
    _request++;
    _loading = false;
    loadCached();
    _lastRefetchedSemesterId = _schedule.selectedSemesterId;
    if (_schedule.suppressAssignmentRefetch) {
      _pendingBindingFetch = true;
      return;
    }
    unawaited(fetchAssignments());
  }

  /// Schedule changed — only refetch if the selected semester actually
  /// changed, not on every loading/error/course_table flip. This prevents
  /// a cascade of redundant blackboard+exam fetches during a semester switch.
  /// Also defers the refetch while selectSemester is mid-fetch (its
  /// course_table request primes the EAMS session; firing exam_table
  /// concurrently would race on EAMS's stateful session and fail with
  /// "Failed to extract numeric ids").
  void _onScheduleChanged() {
    if (!_autoRefetchEnabled) return;
    if (_schedule.suppressAssignmentRefetch) return;
    final currentSemester = _schedule.selectedSemesterId;
    if (currentSemester == _lastRefetchedSemesterId && !_pendingBindingFetch) {
      return;
    }
    _pendingBindingFetch = false;
    _lastRefetchedSemesterId = currentSemester;
    _request++;
    _loading = false;
    loadCached();
    unawaited(fetchAssignments());
  }

  @override
  void dispose() {
    _tpAuth.removeListener(_onBindingsOrAuthChanged);
    _auth.removeListener(_onBindingsOrAuthChanged);
    _schedule.removeListener(_onScheduleChanged);
    super.dispose();
  }

  /// Clear cached + in-memory deadlines (called on primary logout).
  Future<void> clearCache() async {
    _request++;
    _loading = false;
    _assignments = [];
    _platformErrors.clear();
    _error = null;
    for (final owner in _owners.values) {
      await _storage.clearCachedAssignments(owner: owner);
    }
    notifyListeners();
  }

  void loadCached() {
    _platformErrors.clear();
    _error = null;
    _overrides = _storage.loadAssignmentOverrides(owner: _overrideOwner);
    _assignments = [
      for (final entry in _owners.entries)
        ..._storage
            .loadCachedAssignments(owner: entry.value)
            .map(Assignment.fromJson)
            .where((a) => a.platform.toLowerCase() == entry.key),
    ]..sort((a, b) => a.due.compareTo(b.due));
    notifyListeners();
  }

  // -- Override mutators --

  Future<void> _persistOverrides() =>
      _storage.saveAssignmentOverrides(_overrides, owner: _overrideOwner);

  Future<void> setCompleted(Assignment a, bool completed) async {
    _overrides.completed[AssignmentOverrides.keyFor(a)] = completed;
    await _persistOverrides();
    notifyListeners();
  }

  Future<void> toggleCompleted(Assignment a) async {
    final cur = _overrides.effectiveCompleted(a);
    return setCompleted(a, !cur);
  }

  Future<void> clearCompletionOverride(Assignment a) async {
    _overrides.completed.remove(AssignmentOverrides.keyFor(a));
    await _persistOverrides();
    notifyListeners();
  }

  Future<void> resetOverrides(Iterable<String> keys) async {
    var changed = false;
    for (final k in keys) {
      if (_overrides.completed.remove(k) != null) changed = true;
    }
    if (!changed) return;
    await _persistOverrides();
    notifyListeners();
  }

  Future<void> hide(Assignment a) async {
    _overrides.hidden.add(AssignmentOverrides.keyFor(a));
    await _persistOverrides();
    notifyListeners();
  }

  Future<void> unhide(String key) async {
    if (_overrides.hidden.remove(key)) {
      await _persistOverrides();
      notifyListeners();
    }
  }

  Future<void> unhideAll() async {
    if (_overrides.hidden.isEmpty) return;
    _overrides.hidden.clear();
    await _persistOverrides();
    notifyListeners();
  }

  Future<void> clearAllOverrides() async {
    _overrides = AssignmentOverrides();
    await _persistOverrides();
    notifyListeners();
  }

  Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json; charset=UTF-8',
      };

  Future<void> fetchAssignments([String? onlyPlatform]) async {
    if (_loading) return;
    final request = ++_request;
    final owners = _owners;
    _loading = true;
    _error = null;
    if (onlyPlatform == null) {
      _platformErrors.clear();
    } else {
      _platformErrors.remove(onlyPlatform);
    }
    notifyListeners();
    try {
      final results = <String, List<Assignment>>{};
      await Future.wait(
        owners.keys
            .where((p) => onlyPlatform == null || p == onlyPlatform)
            .map((p) async {
          final items = switch (p) {
            'blackboard' => await _fetchBlackboard(),
            'exam' => await _fetchExamTable(),
            'gradescope' =>
              await _fetchGradescope(_tpAuth.gradescopeNode.account!),
            'hydro' => await _fetchHydro(_tpAuth.hydroNode.account!),
            _ => null,
          };
          if (items != null) results[p] = items;
        }),
      );
      if (request != _request) return;
      // Failed platforms keep their last successful data, including on 401.
      _assignments = [
        for (final a in _assignments)
          if (!results.containsKey(a.platform.toLowerCase())) a,
        ...results.values.expand((items) => items),
      ]..sort((a, b) => a.due.compareTo(b.due));
      for (final entry in results.entries) {
        await _storage.saveCachedAssignments(
          entry.value.map((a) => a.toJson()).toList(),
          owner: owners[entry.key],
        );
      }
    } catch (_) {
      if (request == _request) _error = '同步失败，请稍后重试';
    } finally {
      if (request == _request) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchPlatform(String platformId) => fetchAssignments(platformId);

  Future<List<Assignment>?> _fetchBlackboard() async {
    final request = _request;
    final node = _tpAuth.elearningNode;
    // withCookie handles initial minting if the downstream cookie isn't set.
    if (!_tpAuth.hasCpdailyBinding) return null;

    try {
      final resp = await _tpAuth.sessionTree.withCookie<http.Response>(
        node,
        (cp) async {
          // cp.cookies is the elearning cookie string minted from the
          // cpdaily CASTGC. The backend uses it directly to query
          // Blackboard (no SSO bounce needed).
          final r = await _http.post(
            Uri.parse('$_baseUrl/deadlines/blackboard'),
            headers: _jsonHeaders(),
            body: jsonEncode({'token': cp.cookies}),
            tag: 'deadlines:blackboard',
          );
          return CookieAction(r, expired: r.statusCode == 401);
        },
      );
      if (request != _request) return null;
      if (resp == null) throw node.lastFailure ?? SessionFailure.unavailable;
      final items = _parseDeadlinesResponse(resp, 'blackboard');
      if (items != null) node.markVerified();
      return items;
    } catch (e) {
      if (request == _request) {
        _platformErrors['blackboard'] =
            e is SessionFailure ? e.message : '同步失败，请稍后重试';
      }
      return null;
    }
  }

  Future<List<Assignment>?> _fetchExamTable() async {
    final request = _request;
    final semesterId = _selectedSemesterId();
    final node = _tpAuth.eamsNode;
    if (!_tpAuth.hasCpdailyBinding ||
        semesterId == null ||
        semesterId.isEmpty) {
      return null;
    }

    try {
      final resp = await _tpAuth.sessionTree.withCookie<http.Response>(
        node,
        (cp) async {
          final r = await _http.post(
            Uri.parse('$_baseUrl/schedule/exam_table'),
            headers: _jsonHeaders(),
            body: jsonEncode({
              'semester_id': semesterId,
              'cookies': cp.cookies,
            }),
            tag: 'schedule:exam_table',
          );
          return CookieAction(r, expired: r.statusCode == 401);
        },
      );
      if (request != _request) return null;
      if (resp == null) throw node.lastFailure ?? SessionFailure.unavailable;
      return _parseExamTableResponse(resp);
    } catch (e) {
      if (request == _request) {
        _platformErrors['exam'] =
            e is SessionFailure ? e.message : '同步失败，请稍后重试';
      }
      return null;
    }
  }

  Future<List<Assignment>?> _fetchGradescope(ThirdPartyAccount acc) async {
    final request = _request;
    final node = _tpAuth.gradescopeNode;
    if (!node.isAvailable) return null;
    try {
      final resp = await _tpAuth.sessionTree.withCookie<http.Response>(
        node,
        (cp) async {
          // cp.cookies is the gradescope bearer token.
          final r = await _http.post(
            Uri.parse('$_baseUrl/deadlines/gradescope'),
            headers: _jsonHeaders(),
            body: jsonEncode({'token': cp.cookies}),
            tag: 'deadlines:gradescope',
          );
          return CookieAction(r, expired: r.statusCode == 401);
        },
      );
      if (request != _request) return null;
      if (resp == null) throw node.lastFailure ?? SessionFailure.unavailable;

      return _parseDeadlinesResponse(resp, 'gradescope');
    } catch (e) {
      if (request == _request) {
        _platformErrors['gradescope'] =
            e is SessionFailure ? e.message : '同步失败，请稍后重试';
      }
      return null;
    }
  }

  Future<List<Assignment>?> _fetchHydro(ThirdPartyAccount acc) async {
    final request = _request;
    final origin = acc.hydroOrigin ?? 'https://acm.shanghaitech.edu.cn';
    final domains = acc.hydroDomains ?? const <String>[];
    if (domains.isEmpty) {
      _platformErrors['hydro'] = '未配置 Hydro 课程域 (domain),前往设置补全';
      return null;
    }

    final node = _tpAuth.hydroNode;
    if (!node.isAvailable) return null;

    final all = <Assignment>[];
    var hadError = false;
    for (final domain in domains) {
      final url = '${origin.replaceAll(RegExp(r'/+$'), '')}/d/$domain';
      try {
        final resp = await _tpAuth.sessionTree.withCookie<http.Response>(
          node,
          (cp) async {
            // cp.cookies is the hydro sid cookie.
            final r = await _http.post(
              Uri.parse('$_baseUrl/deadlines/hydro'),
              headers: _jsonHeaders(),
              body: jsonEncode({
                'token': cp.cookies,
                'args': {'url': url},
              }),
              tag: 'deadlines:hydro',
            );
            return CookieAction(r, expired: r.statusCode == 401);
          },
        );
        if (request != _request) return null;
        if (resp == null) throw node.lastFailure ?? SessionFailure.unavailable;

        final items = _parseDeadlinesResponse(resp, 'hydro');
        if (items != null) {
          all.addAll(items);
        } else {
          hadError = true;
        }
      } catch (e) {
        if (request == _request) {
          _platformErrors['hydro'] =
              e is SessionFailure ? e.message : '同步失败，请稍后重试';
        }
        hadError = true;
      }
    }
    if (hadError) return null;
    return all;
  }

  List<Assignment>? _parseDeadlinesResponse(
    http.Response resp,
    String platformKey,
  ) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      _platformErrors[platformKey] = '同步失败，服务器返回异常数据';
      return null;
    }

    if (resp.statusCode != 200 || data['success'] != true) {
      _platformErrors[platformKey] =
          SessionFailure.fromStatus(resp.statusCode).message;
      return null;
    }

    if (data['data'] is! List) {
      _platformErrors[platformKey] = '服务返回异常，请稍后重试';
      return null;
    }
    final raw = data['data'] as List<dynamic>;
    return raw
        .map((e) => Assignment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<Assignment>? _parseExamTableResponse(http.Response resp) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      _platformErrors['exam'] = '同步失败，服务器返回异常数据';
      return null;
    }

    if (resp.statusCode != 200 || data['success'] != true) {
      _platformErrors['exam'] =
          SessionFailure.fromStatus(resp.statusCode).message;
      return null;
    }

    final payload = data['data'] is Map
        ? (data['data'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final batchId = payload['examBatchId']?.toString() ?? '';
    final batchName = payload['examBatchName']?.toString() ?? '考试';
    final semesterId =
        payload['semesterId']?.toString() ?? _selectedSemesterId() ?? '';
    if (payload['exams'] is! List) {
      _platformErrors['exam'] = '服务返回异常，请稍后重试';
      return null;
    }
    final raw = payload['exams'] as List<dynamic>;

    return raw
        .map((exam) => exam is Map ? exam.cast<String, dynamic>() : null)
        .whereType<Map<String, dynamic>>()
        .map(
          (exam) => _assignmentFromExam(
            exam,
            batchId: batchId,
            batchName: batchName,
            semesterId: semesterId,
          ),
        )
        .whereType<Assignment>()
        .toList();
  }

  Assignment? _assignmentFromExam(
    Map<String, dynamic> exam, {
    required String batchId,
    required String batchName,
    required String semesterId,
  }) {
    final courseCode = _stringField(exam, 'courseCode');
    final courseName = _stringField(exam, 'courseName');
    final examType = _stringField(exam, 'examType');
    final examDate = _stringField(exam, 'examDate');
    final examTimeRange = _stringField(exam, 'examTimeRange');
    final examPlace = _stringField(exam, 'examPlace');
    final examStatus = _stringField(exam, 'examStatus');
    final seatUrl = _stringField(exam, 'seatUrl');
    final examRoomId = _stringField(exam, 'examRoomId');

    final due = _examDateTime(examDate, examTimeRange, pickEnd: false);
    if (due == null) return null;
    final end = _examDateTime(examDate, examTimeRange, pickEnd: true);

    final detailParts = [
      if (examPlace.isNotEmpty) examPlace,
      if (batchName.isNotEmpty) batchName,
    ];

    return Assignment(
      id: '$semesterId:$batchId:$courseCode:$examRoomId',
      platform: 'exam',
      kind: DeadlineKind.exam,
      title: '$courseName $examType'.trim(),
      course: detailParts.isEmpty
          ? courseName
          : '$courseName · ${detailParts.join(' · ')}',
      due: due,
      lateDue: end,
      status: examStatus.isEmpty ? null : examStatus,
      url: seatUrl.isEmpty ? null : seatUrl,
    );
  }

  String _stringField(Map<String, dynamic> data, String key) =>
      data[key]?.toString().trim() ?? '';

  DateTime? _examDateTime(
    String examDate,
    String examTimeRange, {
    required bool pickEnd,
  }) {
    final dateMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(examDate);
    final timeMatches =
        RegExp(r'(\d{1,2}):(\d{2})').allMatches(examTimeRange).toList();
    if (dateMatch == null || timeMatches.length < 2) return null;

    final timeMatch = pickEnd ? timeMatches.last : timeMatches.first;
    return DateTime(
      int.parse(dateMatch.group(1)!),
      int.parse(dateMatch.group(2)!),
      int.parse(dateMatch.group(3)!),
      int.parse(timeMatch.group(1)!),
      int.parse(timeMatch.group(2)!),
    );
  }

  String? _selectedSemesterId() =>
      _schedule.selectedSemesterId ?? _schedule.semesterInfo?.defaultSemester;
}
