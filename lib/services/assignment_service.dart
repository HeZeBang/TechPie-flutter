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
    _tpAuth.addListener(_onDepsChanged);
    _auth.addListener(_onDepsChanged);
    _schedule.addListener(_onDepsChanged);
  }

  bool _autoRefetchEnabled = false;

  /// Allow auto-refetch on auth/binding changes. Call after the first
  /// explicit fetch from app boot has been kicked off.
  void enableAutoRefetch() => _autoRefetchEnabled = true;

  void _onDepsChanged() {
    if (!_autoRefetchEnabled) return;
    unawaited(fetchAssignments());
  }

  @override
  void dispose() {
    _tpAuth.removeListener(_onDepsChanged);
    _auth.removeListener(_onDepsChanged);
    _schedule.removeListener(_onDepsChanged);
    super.dispose();
  }

  /// Clear cached + in-memory deadlines (called on primary logout).
  Future<void> clearCache() async {
    _assignments = [];
    _platformErrors.clear();
    _error = null;
    await _storage.clearCachedAssignments();
    notifyListeners();
  }

  /// Hydrate from local cache so the UI doesn't flash empty on app start
  /// or tab switch. Safe to call before login. Also loads overrides.
  void loadCached() {
    _overrides = _storage.loadAssignmentOverrides();
    final raw = _storage.loadCachedAssignments();
    if (raw.isEmpty) {
      notifyListeners();
      return;
    }
    _assignments = raw.map((e) => Assignment.fromJson(e)).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    notifyListeners();
  }

  // -- Override mutators --

  Future<void> _persistOverrides() =>
      _storage.saveAssignmentOverrides(_overrides);

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
    await _storage.clearAssignmentOverrides();
    notifyListeners();
  }

  Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json; charset=UTF-8',
      };

  Future<void> fetchAssignments() async {
    _loading = true;
    _error = null;
    _platformErrors.clear();
    notifyListeners();

    final successfulResults = <String, List<Assignment>>{};

    final futures = <Future<void>>[];

    if (_auth.hasEgateBinding) {
      futures.add(
        _fetchBlackboard().then((items) {
          if (items != null) successfulResults['blackboard'] = items;
        }),
      );
      futures.add(
        _fetchExamTable().then((items) {
          if (items != null) successfulResults['exam'] = items;
        }),
      );
    }

    for (final acc in _tpAuth.accounts) {
      switch (acc.platform) {
        case ThirdPartyPlatform.gradescope:
          futures.add(
            _fetchGradescope(acc).then((items) {
              if (items != null) successfulResults[acc.platform.id] = items;
            }),
          );
          break;
        case ThirdPartyPlatform.hydro:
          futures.add(
            _fetchHydro(acc).then((items) {
              if (items != null) successfulResults[acc.platform.id] = items;
            }),
          );
          break;
        case ThirdPartyPlatform.egate:
          // eGate provides CpDaily session, not deadline data — skip.
          break;
      }
    }

    try {
      await Future.wait(futures);
      final merged = _mergeAssignments(
        successfulResults: successfulResults,
      );

      _assignments = merged;
      await _storage.saveCachedAssignments(
        merged.map((a) => a.toJson()).toList(),
      );
    } catch (e) {
      _error = '同步失败，请检查网络或稍后重试';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  List<Assignment> _mergeAssignments({
    required Map<String, List<Assignment>> successfulResults,
  }) {
    final successfulPlatforms =
        successfulResults.keys.map((p) => p.toLowerCase()).toSet();

    final merged = <Assignment>[
      for (final a in _assignments)
        if (!successfulPlatforms.contains(a.platform.toLowerCase())) a,
      ...successfulResults.values.expand((items) => items),
    ]..sort((a, b) => a.due.compareTo(b.due));

    return merged;
  }

  Future<void> fetchPlatform(String platformId) async {
    _loading = true;
    _error = null;
    _platformErrors.remove(platformId);
    notifyListeners();

    final successfulResults = <String, List<Assignment>>{};
    Future<void>? future;

    if (platformId == 'blackboard' && _auth.hasEgateBinding) {
      future = _fetchBlackboard().then((items) {
        if (items != null) successfulResults['blackboard'] = items;
      });
    } else if (platformId == 'exam' && _auth.hasEgateBinding) {
      future = _fetchExamTable().then((items) {
        if (items != null) successfulResults['exam'] = items;
      });
    } else {
      for (final acc in _tpAuth.accounts) {
        if (acc.platform.id == platformId) {
          if (acc.platform == ThirdPartyPlatform.gradescope) {
            future = _fetchGradescope(acc).then((items) {
              if (items != null) successfulResults[platformId] = items;
            });
          } else if (acc.platform == ThirdPartyPlatform.hydro) {
            future = _fetchHydro(acc).then((items) {
              if (items != null) successfulResults[platformId] = items;
            });
          }
          break;
        }
      }
    }

    if (future != null) {
      try {
        await future;
        final merged = _mergeAssignments(
          successfulResults: successfulResults,
        );

        _assignments = merged;
        await _storage.saveCachedAssignments(
          merged.map((a) => a.toJson()).toList(),
        );
      } catch (e) {
        _error = e.toString();
      }
    }

    _loading = false;
    notifyListeners();
  }

  // -- Per-platform fetchers --

  Future<List<Assignment>?> _fetchBlackboard() async {
    final egate = _tpAuth.account(ThirdPartyPlatform.egate);
    if (egate == null) return null;
    final tgc = (egate.raw['tgc'] as String?) ?? '';
    if (tgc.isEmpty) return null;

    Future<http.Response> doFetch(String token) => _http.post(
          Uri.parse('$_baseUrl/deadlines/blackboard'),
          headers: _jsonHeaders(),
          body: jsonEncode({'token': token}),
          tag: 'deadlines:blackboard',
        );

    try {
      var resp = await doFetch(tgc);
      if (resp.statusCode == 401) {
        final renewedRaw =
            await _auth.tryRenewCpDailySession(Map.from(egate.raw));
        if (renewedRaw != null) {
          await _tpAuth.updateRaw(ThirdPartyPlatform.egate, renewedRaw);
          final newTgc = (renewedRaw['tgc'] as String?) ?? tgc;
          resp = await doFetch(newTgc);
        }
      }
      return _parseDeadlinesResponse(resp, 'blackboard');
    } catch (e) {
      _platformErrors['blackboard'] = '同步失败，请检查网络或稍后重试';
      return null;
    }
  }

  Future<List<Assignment>?> _fetchExamTable() async {
    final semesterId = _selectedSemesterId();
    final egate = _tpAuth.account(ThirdPartyPlatform.egate);
    if (egate == null || semesterId == null || semesterId.isEmpty) {
      return null;
    }

    Map<String, dynamic> buildBody() => {
          'semester_id': semesterId,
          'cookies': _eamsCookies(egate),
        };

    try {
      var resp = await _http.post(
        Uri.parse('$_baseUrl/schedule/exam_table'),
        headers: _jsonHeaders(),
        body: jsonEncode(buildBody()),
        tag: 'schedule:exam_table',
      );
      if (resp.statusCode == 401) {
        final renewedRaw =
            await _auth.tryRenewCpDailySession(Map.from(egate.raw));
        if (renewedRaw != null) {
          await _tpAuth.updateRaw(ThirdPartyPlatform.egate, renewedRaw);
          resp = await _http.post(
            Uri.parse('$_baseUrl/schedule/exam_table'),
            headers: _jsonHeaders(),
            body: jsonEncode(buildBody()),
            tag: 'schedule:exam_table:retry',
          );
        }
      }
      return _parseExamTableResponse(resp);
    } catch (e) {
      _platformErrors['exam'] = '同步失败，请检查网络或稍后重试';
      return null;
    }
  }

  Future<List<Assignment>?> _fetchGradescope(ThirdPartyAccount acc) async {
    try {
      final resp = await _http.post(
        Uri.parse('$_baseUrl/deadlines/gradescope'),
        headers: _jsonHeaders(),
        body: jsonEncode({'token': acc.token}),
        tag: 'deadlines:gradescope',
      );
      if (resp.statusCode == 401) {
        await _tpAuth.unbind(ThirdPartyPlatform.gradescope);
        _platformErrors['gradescope'] = 'token 已失效,请重新绑定';
        return null;
      }
      return _parseDeadlinesResponse(resp, 'gradescope');
    } catch (e) {
      _platformErrors['gradescope'] = '同步失败，请检查网络或稍后重试';
      return null;
    }
  }

  Future<List<Assignment>?> _fetchHydro(ThirdPartyAccount acc) async {
    final origin = acc.hydroOrigin ?? 'https://acm.shanghaitech.edu.cn';
    final domains = acc.hydroDomains ?? const <String>[];
    if (domains.isEmpty) {
      _platformErrors['hydro'] = '未配置 Hydro 课程域 (domain),前往设置补全';
      return null;
    }

    final all = <Assignment>[];
    var hadError = false;
    for (final domain in domains) {
      final url = '${origin.replaceAll(RegExp(r'/+$'), '')}/d/$domain';
      try {
        final resp = await _http.post(
          Uri.parse('$_baseUrl/deadlines/hydro'),
          headers: _jsonHeaders(),
          body: jsonEncode({
            'token': acc.token,
            'args': {'url': url},
          }),
          tag: 'deadlines:hydro:$domain',
        );
        if (resp.statusCode == 401) {
          await _tpAuth.unbind(ThirdPartyPlatform.hydro);
          _platformErrors['hydro'] = 'token 已失效,请重新绑定';
          return null;
        }
        final items = _parseDeadlinesResponse(resp, 'hydro');
        if (items != null) {
          all.addAll(items);
        } else {
          hadError = true;
        }
      } catch (e) {
        _platformErrors['hydro'] = '同步失败，请检查网络或稍后重试';
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
          (data['error'] as String?) ?? '同步失败 (HTTP ${resp.statusCode})';
      return null;
    }

    final raw = data['data'] as List<dynamic>? ?? const [];
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
          (data['error'] as String?) ?? '同步失败 (HTTP ${resp.statusCode})';
      return null;
    }

    final payload = data['data'] is Map
        ? (data['data'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final batchId = payload['examBatchId']?.toString() ?? '';
    final batchName = payload['examBatchName']?.toString() ?? '考试';
    final semesterId =
        payload['semesterId']?.toString() ?? _selectedSemesterId() ?? '';
    final raw = payload['exams'] as List<dynamic>? ?? const [];

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
      _schedule.selectedSemesterId ??
      _storage.selectedSemester ??
      _schedule.semesterInfo?.defaultSemester;

  String _eamsCookies(ThirdPartyAccount egate) {
    final raw = egate.raw;
    final baseCookies = (raw['cookies'] as String?) ?? '';
    final tgc = (raw['tgc'] as String?) ?? '';
    return tgc.isNotEmpty
        ? (baseCookies.isNotEmpty ? '$baseCookies; CASTGC=$tgc' : 'CASTGC=$tgc')
        : baseCookies;
  }
}
