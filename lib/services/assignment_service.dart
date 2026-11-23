import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import '../models/campus_identity.dart';
import '../models/graduate_schedule.dart';
import '../models/third_party_account.dart';
import 'api_base_url.dart';
import 'auth_service.dart';
import 'http_client.dart';
import 'schedule_service.dart';
import 'session/session_tree.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

typedef _ExamSelection = ({
  CampusScheduleSource source,
  String? semesterId,
  bool unsupported,
});
typedef _ExamResult = ({
  _ExamSelection selection,
  String? idsSession,
  List<Assignment> items,
});

class AssignmentService extends ChangeNotifier {
  final StorageService _storage;
  final LoggingHttpClient _http;
  final AuthService _auth;
  final ThirdPartyAuthService _tpAuth;
  final ScheduleService _schedule;

  List<Assignment> _assignments = [];
  AssignmentOverrides _overrides = AssignmentOverrides();
  bool _loading = false;
  int _identityEpoch = 0;
  bool _hasCachedData = false;
  bool _cacheHydrated = false;
  bool _refetchPending = false;
  bool _signedOut = false;
  bool _disposed = false;
  String? _primaryIdentity;
  Map<String, String> _sourceIdentities = {};
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
  int get identityEpoch => _identityEpoch;
  bool get hasCachedData => _hasCachedData;
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
    _primaryIdentity = _auth.session?.userId;
    _sourceIdentities = _currentSources();
    // Refetch when bindings or auth change *after* initial app boot.
    // The initial fetch is kicked off explicitly from main.dart so we
    // don't double-fire during service initialization.
    _tpAuth.addListener(_onBindingsOrAuthChanged);
    _auth.addListener(_onBindingsOrAuthChanged);
    _schedule.addListener(_onScheduleChanged);
  }

  bool _autoRefetchEnabled = false;
  _ExamSelection? _lastRefetchedExamSelection;

  /// Allow auto-refetch on auth/binding changes. Call after the first
  /// explicit fetch from app boot has been kicked off.
  void enableAutoRefetch() {
    _autoRefetchEnabled = true;
    _lastRefetchedExamSelection = _examSelection;
  }

  /// Queue a refetch during an active sync only when the identity changes.
  void _onBindingsOrAuthChanged() {
    final primary = _auth.session?.userId;
    final sources = _currentSources();
    final primaryChanged = primary != _primaryIdentity;
    final changed = <String>{
      for (final key in {..._sourceIdentities.keys, ...sources.keys})
        if (_sourceIdentities[key] != sources[key]) key,
    };
    if (primaryChanged || changed.isNotEmpty) {
      if (_cacheHydrated) {
        _identityEpoch++;
        if (primaryChanged) {
          _signedOut = _primaryIdentity != null && primary == null;
        }
        if (primary != null) _signedOut = false;
        _assignments = primaryChanged
            ? []
            : _assignments.where((a) {
                final source =
                    (a.platform == 'blackboard' || a.platform == 'exam')
                        ? ThirdPartyPlatform.ids.id
                        : a.platform;
                return !changed.contains(source);
              }).toList();
        if (primaryChanged) {
          _hasCachedData = false;
          unawaited(_storage.clearCachedAssignments());
        } else if (_hasCachedData) {
          unawaited(
            _storage.saveCachedAssignments(
              _assignments.map((a) => a.toJson()).toList(),
            ),
          );
        }
        notifyListeners();
      }
      _primaryIdentity = primary;
      _sourceIdentities = sources;
    }
    if (!_autoRefetchEnabled) return;
    if (_signedOut) return;
    if (_loading) {
      // Renewal status notifications must not retry the active sync.
      if (primaryChanged || changed.isNotEmpty) _refetchPending = true;
      return;
    }
    if (!_schedule.suppressAssignmentRefetch) _lastRefetchedExamSelection = _examSelection;
    unawaited(fetchAssignments());
  }

  /// Who each binding is, not which session it holds. Token rotations and
  /// derived campus sessions must not count as an account change.
  Map<String, String> _currentSources() => {
        for (final account in _tpAuth.accounts)
          account.platform.id: jsonEncode([
            account.account,
            account.hydroOrigin,
            account.hydroDomains,
          ]),
      };

  /// Wait for the timetable switch to finish priming EAMS before fetching
  /// exams for the new selection.
  void _onScheduleChanged() {
    if (!_autoRefetchEnabled) return;
    if (_schedule.suppressAssignmentRefetch) return;
    final selection = _examSelection;
    if (selection == _lastRefetchedExamSelection) return;
    _lastRefetchedExamSelection = selection;
    if (_loading) {
      _refetchPending = true;
      return;
    }
    unawaited(fetchAssignments());
  }

  @override
  void dispose() {
    _disposed = true;
    _tpAuth.removeListener(_onBindingsOrAuthChanged);
    _auth.removeListener(_onBindingsOrAuthChanged);
    _schedule.removeListener(_onScheduleChanged);
    super.dispose();
  }

  /// Clear cached + in-memory deadlines (called on primary logout).
  Future<void> clearCache() async {
    _identityEpoch++;
    _hasCachedData = false;
    _assignments = [];
    _platformErrors.clear();
    _error = null;
    await _storage.clearCachedAssignments();
    notifyListeners();
  }

  /// Hydrate from local cache so the UI doesn't flash empty on app start
  /// or tab switch. Safe to call before login. Also loads overrides.
  void loadCached() {
    _cacheHydrated = true;
    _hasCachedData = _storage.hasCachedAssignments;
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
    notifyListeners();
    await _persistOverrides();
  }

  Future<void> toggleCompleted(Assignment a) async {
    final cur = _overrides.effectiveCompleted(a);
    return setCompleted(a, !cur);
  }

  Future<void> clearCompletionOverride(Assignment a) async {
    _overrides.completed.remove(AssignmentOverrides.keyFor(a));
    notifyListeners();
    await _persistOverrides();
  }

  Future<void> resetOverrides(Iterable<String> keys) async {
    var changed = false;
    for (final k in keys) {
      if (_overrides.completed.remove(k) != null) changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await _persistOverrides();
  }

  Future<void> hide(Assignment a) async {
    _overrides.hidden.add(AssignmentOverrides.keyFor(a));
    notifyListeners();
    await _persistOverrides();
  }

  Future<void> unhide(String key) async {
    if (_overrides.hidden.remove(key)) {
      notifyListeners();
      await _persistOverrides();
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
    if (_loading || _signedOut || _disposed) return;
    final epoch = _identityEpoch;
    _loading = true;
    _error = null;
    _platformErrors.clear();
    notifyListeners();

    final successfulResults = <String, List<Assignment>>{};
    _ExamResult? exams;

    final futures = <Future<void>>[];

    if (_tpAuth.hasIdsBinding) {
      futures.add(
        _fetchBlackboard().then((items) {
          if (items != null) successfulResults['blackboard'] = items;
        }),
      );
      futures.add(
        _fetchExamTable().then((result) {
          exams = result;
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
        case ThirdPartyPlatform.ids:
          // ids provides the IDS session, not deadline data — skip.
          break;
      }
    }

    try {
      await Future.wait(futures);
      if (_disposed || epoch != _identityEpoch) return;
      final merged = _mergeAssignments(
        successfulResults: successfulResults,
        exams: exams,
      );

      _assignments = merged;
      _hasCachedData = _hasCachedData || successfulResults.isNotEmpty;
      if (!_hasCachedData) return;
      await _storage.saveCachedAssignments(
        merged.map((a) => a.toJson()).toList(),
      );
    } catch (e) {
      _error = '同步失败，请检查网络或稍后重试';
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
      if (_refetchPending && !_disposed) {
        _refetchPending = false;
        unawaited(fetchAssignments());
      }
    }
  }

  List<Assignment> _mergeAssignments({
    required Map<String, List<Assignment>> successfulResults,
    required _ExamResult? exams,
  }) {
    final selection = _examSelection;
    if (selection.unsupported) {
      _platformErrors.remove('exam');
      if (_assignments.any((assignment) => assignment.platform == 'exam')) {
        successfulResults['exam'] = const [];
      }
    } else if (exams != null && exams.selection == selection && exams.idsSession == _idsSession) {
      successfulResults['exam'] = exams.items;
    }
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
    if (_loading || _signedOut || _disposed) return;
    final epoch = _identityEpoch;
    _loading = true;
    _error = null;
    _platformErrors.remove(platformId);
    notifyListeners();

    final successfulResults = <String, List<Assignment>>{};
    _ExamResult? exams;
    Future<void>? future;

    if (platformId == 'blackboard' && _tpAuth.hasIdsBinding) {
      future = _fetchBlackboard().then((items) {
        if (items != null) successfulResults['blackboard'] = items;
      });
    } else if (platformId == 'exam' && _tpAuth.hasIdsBinding) {
      future = _fetchExamTable().then((result) {
        exams = result;
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

    try {
      if (future != null) {
        await future;
        if (_disposed || epoch != _identityEpoch) return;
        final merged = _mergeAssignments(
          successfulResults: successfulResults,
          exams: exams,
        );

        _assignments = merged;
        _hasCachedData = _hasCachedData || successfulResults.isNotEmpty;
        if (!_hasCachedData) return;
        await _storage.saveCachedAssignments(
          merged.map((a) => a.toJson()).toList(),
        );
      }
    } catch (e) {
      if (epoch == _identityEpoch) _error = e.toString();
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
      if (_refetchPending && !_disposed) {
        _refetchPending = false;
        unawaited(fetchAssignments());
      }
    }
  }

  Future<List<Assignment>?> _fetchBlackboard() async {
    final node = _tpAuth.elearningNode;
    // withCookie handles initial minting if the downstream cookie isn't set.
    if (!_tpAuth.hasIdsBinding) return null;

    try {
      final resp = await _tpAuth.sessionTree.withCookie<http.Response>(
        node,
        (cp) async {
          // cp.cookies is the elearning cookie string minted from the
          // ids CASTGC. The backend uses it directly to query
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
      if (resp == null) return null;
      return _parseDeadlinesResponse(resp, 'blackboard');
    } catch (e) {
      _platformErrors['blackboard'] = '同步失败，请检查网络或稍后重试';
      return null;
    }
  }

  _ExamSelection get _examSelection {
    final semesterId = _selectedSemesterId();
    final unsupported = _schedule.hasGraduateIdentity ||
        _schedule.isGraduate ||
        semesterId?.startsWith(graduateSemesterPrefix) == true;
    return (
      source: _schedule.scheduleSource,
      semesterId: unsupported ? null : semesterId,
      unsupported: unsupported,
    );
  }

  String? get _idsSession => _tpAuth.idsNode.cookieProvider?.cookies;

  Future<_ExamResult?> _fetchExamTable() async {
    if (_examSelection.unsupported || !await _schedule.canFetchUndergraduateExams()) return null;
    var selection = _examSelection;
    if (selection.unsupported || selection.semesterId?.isNotEmpty != true) return null;
    var idsSession = _idsSession;

    bool requestIsCurrent() => selection == _examSelection && idsSession == _idsSession;

    try {
      final resp = await _tpAuth.sessionTree.withCookie<http.Response>(
        _tpAuth.eamsNode,
        (cp) async {
          // Minting EAMS cookies can renew IDS after the initial identity check.
          idsSession = _idsSession;
          if (!await _schedule.canFetchUndergraduateExams() || idsSession != _idsSession) {
            throw const FormatException('学校身份尚未确认');
          }
          final current = _examSelection;
          final semesterId = current.semesterId;
          if (current.unsupported || semesterId == null || semesterId.isEmpty) {
            throw const FormatException('本科课表学期尚未确认');
          }
          selection = current;
          final r = await _http.post(
            Uri.parse('$_baseUrl/schedule/exam_table'),
            headers: _jsonHeaders(),
            body: jsonEncode({
              'semester_id': semesterId,
              'cookies': cp.cookies,
            }),
            tag: 'schedule:exam_table',
          );
          return CookieAction(r, expired: r.statusCode == 401 && requestIsCurrent());
        },
      );
      if (resp == null || !requestIsCurrent()) return null;
      final items = _parseExamTableResponse(resp, selection.semesterId!);
      return items == null ? null : (selection: selection, idsSession: idsSession, items: items);
    } catch (_) {
      if (requestIsCurrent() && !_examSelection.unsupported) {
        _platformErrors['exam'] = '同步失败，请检查网络或稍后重试';
      }
      return null;
    }
  }

  Future<List<Assignment>?> _fetchGradescope(ThirdPartyAccount acc) async {
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
      if (resp == null) return null;
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
              tag: 'deadlines:hydro:$domain',
            );
            return CookieAction(r, expired: r.statusCode == 401);
          },
        );
        if (resp == null) return null;
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

  List<Assignment>? _parseExamTableResponse(http.Response resp, String requestedSemester) {
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
    final semesterId = payload['semesterId']?.toString() ?? requestedSemester;
    if (semesterId != requestedSemester) {
      _platformErrors['exam'] = '考试学期与当前课表不一致，请刷新后重试';
      return null;
    }
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

    return ExamAssignment(
      id: '$semesterId:$batchId:$courseCode:$examRoomId',
      title: '$courseName $examType'.trim(),
      course: detailParts.isEmpty
          ? courseName
          : '$courseName · ${detailParts.join(' · ')}',
      due: due,
      lateDue: end,
      status: examStatus.isEmpty ? null : examStatus,
      url: seatUrl.isEmpty ? null : seatUrl,
      semesterId: semesterId,
      location: examPlace,
      batchName: batchName,
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
}
