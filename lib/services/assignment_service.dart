import 'dart:async';

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../features/campus_card/core/async_mutex.dart';
import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import '../models/third_party_account.dart';
import 'api_base_url.dart';
import 'auth_service.dart';
import 'http_client.dart';
import 'schedule_service.dart';
import 'session/session_tree.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

class AssignmentService extends ChangeNotifier {
  final StorageService _storage;
  final LoggingHttpClient _http;
  final AuthService _auth;
  final ThirdPartyAuthService _tpAuth;
  final ScheduleService _schedule;

  List<Assignment> _assignments = const [];
  List<Assignment> _remoteAssignments = const [];
  Map<String, CustomDeadline>? _customDeadlines;
  final _customDeadlineWrites = AsyncMutex();
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
  bool get hasCachedData => _hasCachedData || _customDeadlines != null;
  String? get customDeadlineOwner => _primaryIdentity;
  String? get error => _error;
  Map<String, String> get platformErrors => Map.unmodifiable(_platformErrors);

  bool isCompleted(Assignment a) => _overrides.effectiveCompleted(a);
  bool hasCompletionOverride(Assignment a) =>
      _overrides.hasCompletionOverride(a);
  bool isHidden(Assignment a) => _overrides.isHidden(a);

  CustomDeadline? findCustomDeadline(String id) => _customDeadlines?[id];

  void _rebuildAssignments() {
    _assignments = List.unmodifiable(
      <Assignment>[
        ..._remoteAssignments,
        ...?_customDeadlines?.values,
      ]..sort((a, b) => a.due.compareTo(b.due)),
    );
  }

  String scopedKeyFor(Assignment assignment) => jsonEncode([
        _primaryIdentity,
        _sourceIdentities[_sourcePlatform(assignment)],
        AssignmentOverrides.keyFor(assignment),
      ]);

  static String _sourcePlatform(Assignment assignment) =>
      (assignment.platform == 'blackboard' || assignment.platform == 'exam')
          ? ThirdPartyPlatform.ids.id
          : assignment.platform;

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
  // Track the last semester we refetched for, so schedule notifies that
  // don't change the semester (loading flips, course_table updates, errors)
  // do NOT trigger a redundant assignment refetch.
  String? _lastRefetchedSemesterId;

  /// Allow auto-refetch on auth/binding changes. Call after the first
  /// explicit fetch from app boot has been kicked off.
  void enableAutoRefetch() {
    _autoRefetchEnabled = true;
    // Seed so the first schedule notify (which doesn't change the semester)
    // doesn't trigger a redundant refetch of the same semester.
    _lastRefetchedSemesterId = _schedule.selectedSemesterId;
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
      final wasSignedIn = _primaryIdentity != null;
      _primaryIdentity = primary;
      _sourceIdentities = sources;
      if (_cacheHydrated) {
        _identityEpoch++;
        if (primaryChanged) {
          _signedOut = wasSignedIn && primary == null;
        }
        if (primary != null) _signedOut = false;
        _remoteAssignments = primaryChanged
            ? const []
            : _remoteAssignments
                .where((a) => !changed.contains(_sourcePlatform(a)))
                .toList();
        if (primaryChanged) {
          _customDeadlines = _storage.loadCustomDeadlines(primary);
          _hasCachedData = false;
          unawaited(_storage.clearCachedAssignments());
        } else if (_hasCachedData) {
          unawaited(
            _storage.saveCachedAssignments(
              _remoteAssignments.map((a) => a.toJson()).toList(),
            ),
          );
        }
        _rebuildAssignments();
        notifyListeners();
      }
    }
    if (!_autoRefetchEnabled) return;
    if (_signedOut) return;
    _lastRefetchedSemesterId = _schedule.selectedSemesterId;
    if (_loading) {
      // Renewal status notifications must not retry the active sync.
      if (primaryChanged || changed.isNotEmpty) _refetchPending = true;
      return;
    }
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
    if (currentSemester == _lastRefetchedSemesterId) return;
    _lastRefetchedSemesterId = currentSemester;
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

  /// Clear fetched deadlines (called on primary logout).
  Future<void> clearCache() async {
    _identityEpoch++;
    _hasCachedData = false;
    _remoteAssignments = const [];
    _rebuildAssignments();
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
    _remoteAssignments = _storage
        .loadCachedAssignments()
        .map(Assignment.fromJson)
        .toList();
    _customDeadlines = _storage.loadCustomDeadlines(_primaryIdentity);
    _rebuildAssignments();
    notifyListeners();
  }

  Future<void> saveCustomDeadline({
    required String? owner,
    String? id,
    required String title,
    required DateTime due,
    String course = '',
    String notes = '',
  }) {
    final name = title.trim();
    if (name.isEmpty) throw ArgumentError.value(title, 'title', 'Required');
    return _mutateCustomDeadlines(owner, (deadlines) {
      final previous = deadlines[id];
      if (id != null && previous == null) {
        throw StateError('Custom deadline no longer exists');
      }
      final deadlineId = id ?? _newCustomDeadlineId();
      deadlines[deadlineId] = CustomDeadline(
        id: deadlineId,
        title: name,
        course: course.trim(),
        due: due,
        notes: notes.trim(),
        completed: previous?.completed ?? false,
        reminderCompletedAt: previous?.reminderCompletedAt,
      );
      return true;
    });
  }

  static String _newCustomDeadlineId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> deleteCustomDeadline(String id, {required String? owner}) =>
      _mutateCustomDeadlines(owner, (deadlines) => deadlines.remove(id) != null);

  Future<void> _mutateCustomDeadlines(
    String? owner,
    bool Function(Map<String, CustomDeadline>) apply,
  ) =>
      _customDeadlineWrites.protect(() async {
        if (_disposed || owner != _primaryIdentity) {
          throw StateError('Deadline workspace changed');
        }
        final updated = {...?_customDeadlines};
        if (!apply(updated)) return;
        await _storage.saveCustomDeadlines(owner, updated.values);
        if (_disposed || owner != _primaryIdentity) return;
        _customDeadlines = updated;
        _rebuildAssignments();
        notifyListeners();
      });

  Future<void> _setCustomCompletion(String id, {bool? completed}) =>
      _mutateCustomDeadlines(_primaryIdentity, (deadlines) {
        final deadline = deadlines[id];
        if (deadline == null || deadline.completed == completed) return false;
        deadlines[id] = deadline.withCompletion(
          completed ?? !deadline.completed,
        );
        return true;
      });

  // -- Override mutators --

  Future<void> _persistOverrides() =>
      _storage.saveAssignmentOverrides(_overrides);

  Future<void> setCompleted(Assignment a, bool completed) async {
    if (a is CustomDeadline) {
      await _setCustomCompletion(a.id, completed: completed);
      return;
    }
    _overrides.completed[AssignmentOverrides.keyFor(a)] = completed;
    notifyListeners();
    await _persistOverrides();
  }

  Future<void> applyReminderCompletions(
    Map<String, ({Assignment assignment, int completedAt})> completions,
  ) async {
    final owner = _primaryIdentity;
    final customCompletions = <String, int>{};
    var recorded = false;
    var changed = false;
    for (final entry in completions.entries) {
      final completion = entry.value;
      if (completion.assignment is CustomDeadline) {
        customCompletions[completion.assignment.id] = completion.completedAt;
        continue;
      }
      final previous = _overrides.reminderCompletions[entry.key];
      if (previous != null && previous >= completion.completedAt) continue;
      _overrides.reminderCompletions[entry.key] = completion.completedAt;
      recorded = true;
      if (isCompleted(completion.assignment)) continue;
      _overrides.completed[AssignmentOverrides.keyFor(completion.assignment)] =
          true;
      changed = true;
    }
    if (changed) notifyListeners();
    if (recorded) await _persistOverrides();
    if (customCompletions.isEmpty || owner != _primaryIdentity || _disposed) {
      return;
    }
    await _mutateCustomDeadlines(owner, (deadlines) {
      var updated = false;
      for (final entry in customCompletions.entries) {
        final deadline = deadlines[entry.key];
        if (deadline == null ||
            (deadline.reminderCompletedAt ?? -1) >= entry.value) {
          continue;
        }
        deadlines[entry.key] = deadline.withCompletion(
          true,
          reminderCompletedAt: entry.value,
        );
        updated = true;
      }
      return updated;
    });
  }

  Future<void> toggleCompleted(Assignment a) async {
    if (a is CustomDeadline) return _setCustomCompletion(a.id);
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

    final futures = <Future<void>>[];

    if (_tpAuth.hasIdsBinding) {
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
      );

      _remoteAssignments = merged;
      _rebuildAssignments();
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
  }) {
    final successfulPlatforms =
        successfulResults.keys.map((p) => p.toLowerCase()).toSet();

    return <Assignment>[
      for (final a in _remoteAssignments)
        if (!successfulPlatforms.contains(a.platform.toLowerCase())) a,
      ...successfulResults.values.expand((items) => items),
    ];
  }

  Future<void> fetchPlatform(String platformId) async {
    if (_loading || _signedOut || _disposed) return;
    final epoch = _identityEpoch;
    _loading = true;
    _error = null;
    _platformErrors.remove(platformId);
    notifyListeners();

    final successfulResults = <String, List<Assignment>>{};
    Future<void>? future;

    if (platformId == 'blackboard' && _tpAuth.hasIdsBinding) {
      future = _fetchBlackboard().then((items) {
        if (items != null) successfulResults['blackboard'] = items;
      });
    } else if (platformId == 'exam' && _tpAuth.hasIdsBinding) {
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

    try {
      if (future != null) {
        await future;
        if (_disposed || epoch != _identityEpoch) return;
        final merged = _mergeAssignments(
          successfulResults: successfulResults,
        );

        _remoteAssignments = merged;
        _rebuildAssignments();
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

  Future<List<Assignment>?> _fetchExamTable() async {
    final semesterId = _selectedSemesterId();
    final node = _tpAuth.eamsNode;
    if (!_tpAuth.hasIdsBinding ||
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
      if (resp == null) return null;
      return _parseExamTableResponse(resp);
    } catch (e) {
      _platformErrors['exam'] = '同步失败，请检查网络或稍后重试';
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
