import 'dart:async';

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
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
  final bool _syncReminders;
  final DateTime Function() _now;

  List<Assignment> _assignments = const [];
  List<Assignment> _remoteAssignments = const [];
  Map<String, CustomDeadline>? _customDeadlines;
  Map<String, DeadlineReminderChange> _customReminderChanges = {};
  late final _writes = AsyncMutex();
  AssignmentOverrides _overrides = AssignmentOverrides();
  int _reminderChangesRevision = 0;
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
  int get reminderChangesRevision => _reminderChangesRevision;
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

  String reminderKeyFor(Assignment assignment) =>
      _hash(scopedKeyFor(assignment));

  ({
    Map<String, DeadlineReminderChange> changes,
    Duration? nextRemoval,
  }) get reminderSyncWork {
    final changes = {
      for (final entry
          in _activeOverrideReminderKeys(_overrides.reminderChanges.keys).entries)
        entry.value: _overrides.reminderChanges[entry.key]!,
      for (final entry in _customReminderChanges.entries)
        if (entry.value != DeadlineReminderChange.edit) entry.key: entry.value,
    };
    final now = _now().millisecondsSinceEpoch;
    int? nextRemoval;
    for (final entry
        in _activeOverrideReminderKeys(_overrides.reminderRemovals.keys).entries) {
      final after = _overrides.reminderRemovals[entry.key]!.after;
      if (after <= now) {
        changes[entry.value] = DeadlineReminderChange.remove;
      } else if (nextRemoval == null || after < nextRemoval) {
        nextRemoval = after;
      }
    }
    return (
      changes: changes,
      nextRemoval: nextRemoval == null ? null : Duration(milliseconds: nextRemoval - now),
    );
  }

  // Read after any local undo that has already started persisting.
  Future<({Map<String, DeadlineReminderChange> changes, Duration? nextRemoval})>
      readReminderSyncWork() => _writes.protect(() async => reminderSyncWork);

  Map<String, CustomDeadline> get pendingReminderEdits => {
        if (_customReminderChanges.containsValue(DeadlineReminderChange.edit))
          for (final deadline in _customDeadlines?.values ?? const <CustomDeadline>[])
            if (_customReminderChanges.containsKey(_reminderEditKey(deadline.id)))
              reminderKeyFor(deadline): deadline,
      };

  // Details and completion changes can both be pending for the same deadline.
  static String _reminderEditKey(String id) => 'edit:$id';

  static String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

  String _reminderSourceScope(String source) =>
      _hash(jsonEncode([_primaryIdentity, source, _sourceIdentities[source]]));

  String _overrideReminderKey(Assignment assignment, String reminderKey) =>
      '${_reminderSourceScope(_sourcePlatform(assignment))}:$reminderKey';

  // Retry changes from the current account and bindings even when a refresh
  // or semester switch has removed the original assignment from the list.
  Map<String, String> _activeOverrideReminderKeys(Iterable<String> storedKeys) {
    if (storedKeys.isEmpty) return const {};
    final scopes = {
      'custom',
      ...ThirdPartyPlatform.values.map((platform) => platform.id),
      ..._remoteAssignments.map(_sourcePlatform),
    }.map(_reminderSourceScope).toSet();
    return {
      for (final storedKey in storedKeys)
        if (storedKey.split(':') case [final scope, final reminderKey]
            when scopes.contains(scope))
          storedKey: reminderKey,
    };
  }

  static String _sourcePlatform(Assignment assignment) =>
      (assignment.platform == 'blackboard' || assignment.platform == 'exam')
          ? ThirdPartyPlatform.ids.id
          : assignment.platform;

  AssignmentService(
    this._storage,
    this._http,
    this._auth,
    this._tpAuth,
    this._schedule, {
    bool syncReminders = false,
    DateTime Function() now = DateTime.now,
  })  : _syncReminders = syncReminders,
        _now = now {
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
          _loadCustomDeadlines();
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
    _loadCustomDeadlines();
    _rebuildAssignments();
    notifyListeners();
  }

  void _loadCustomDeadlines() {
    final saved = _storage.loadCustomDeadlines(_primaryIdentity);
    _customDeadlines = saved?.deadlines;
    _customReminderChanges = saved?.reminderChanges ?? {};
  }

  Future<void> saveCustomDeadline({
    required String? owner,
    String? id,
    required String title,
    required DateTime due,
    String course = '',
    String? location,
    String notes = '',
  }) {
    final name = title.trim();
    if (name.isEmpty) throw ArgumentError.value(title, 'title', 'Required');
    return _mutateCustomDeadlines(owner, (deadlines, changes) {
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
        location: location?.trim() ?? previous?.location ?? '',
        notes: notes.trim(),
        completed: previous?.completed ?? false,
        reminderCompletedAt: previous?.reminderCompletedAt,
      );
      if (_syncReminders && previous != null) {
        changes[_reminderEditKey(deadlineId)] = DeadlineReminderChange.edit;
      }
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
      _mutateCustomDeadlines(owner, (deadlines, changes) {
        final deleted = deadlines.remove(id);
        if (deleted == null) return false;
        if (_syncReminders) {
          changes.remove(_reminderEditKey(id));
          changes[reminderKeyFor(deleted)] = DeadlineReminderChange.remove;
        }
        return true;
      });

  Future<void> _mutateCustomDeadlines(
    String? owner,
    bool Function(
      Map<String, CustomDeadline>,
      Map<String, DeadlineReminderChange>,
    ) apply,
  ) =>
      _writes.protect(() async {
        if (_disposed || owner != _primaryIdentity) {
          throw StateError('Deadline workspace changed');
        }
        final updated = {...?_customDeadlines};
        final changes = {..._customReminderChanges};
        if (!apply(updated, changes)) return;
        await _storage.saveCustomDeadlines(owner, updated.values, changes);
        if (_disposed || owner != _primaryIdentity) return;
        if (!mapEquals(_customDeadlines, updated)) {
          _customDeadlines = updated;
          _rebuildAssignments();
        }
        if (!mapEquals(_customReminderChanges, changes)) {
          _customReminderChanges = changes;
          _reminderChangesRevision++;
        }
        notifyListeners();
      });

  Future<void> _setCustomCompletion(String id, {bool? completed}) =>
      _mutateCustomDeadlines(_primaryIdentity, (deadlines, changes) {
        final deadline = deadlines[id];
        if (deadline == null) return false;
        final next = completed ?? !deadline.completed;
        if (deadline.completed == next) return false;
        deadlines[id] = deadline.withCompletion(next);
        _recordReminderCompletion(changes, deadline, next);
        return true;
      });

  // -- Override mutators --

  Future<void> _mutateOverrides(bool Function(AssignmentOverrides) apply) {
    final epoch = _identityEpoch;
    return _writes.protect(() async {
      if (_disposed || epoch != _identityEpoch) return;
      final updated = _overrides.copy();
      if (!apply(updated)) return;
      await _storage.saveAssignmentOverrides(updated);
      if (_disposed) return;
      if (!mapEquals(_overrides.reminderChanges, updated.reminderChanges) ||
          !mapEquals(_overrides.reminderRemovals, updated.reminderRemovals)) {
        _reminderChangesRevision++;
      }
      if (epoch == _identityEpoch) {
        _overrides = updated;
      } else {
        _overrides.reminderChanges
          ..clear()
          ..addAll(updated.reminderChanges);
        _overrides.reminderRemovals
          ..clear()
          ..addAll(updated.reminderRemovals);
      }
      notifyListeners();
    });
  }

  void _recordReminderCompletion(
    Map<String, DeadlineReminderChange> changes,
    Assignment assignment,
    bool completed,
  ) {
    if (!_syncReminders) return;
    final key = reminderKeyFor(assignment);
    final storedKey = assignment is CustomDeadline
        ? key
        : _overrideReminderKey(assignment, key);
    changes[storedKey] = completed
        ? DeadlineReminderChange.complete
        : DeadlineReminderChange.reopen;
  }

  Future<void> setCompleted(Assignment a, bool completed) {
    if (a is CustomDeadline) {
      return _setCustomCompletion(a.id, completed: completed);
    }
    return _setOverrideCompletion(a, completed: completed);
  }

  Future<void> _setOverrideCompletion(Assignment a, {bool? completed}) =>
      _mutateOverrides((overrides) {
        final key = AssignmentOverrides.keyFor(a);
        final previous = overrides.effectiveCompleted(a);
        final next = completed ?? !previous;
        if (overrides.completed[key] == next) return false;
        overrides.completed[key] = next;
        if (previous != next) {
          _recordReminderCompletion(overrides.reminderChanges, a, next);
        }
        return true;
      });

  Future<void> acknowledgeReminderChanges(
    Map<String, DeadlineReminderChange> sent, {
    required int epoch,
  }) async {
    final owner = _primaryIdentity;
    await _mutateOverrides((overrides) {
      if (epoch != _identityEpoch) return false;
      final pending = overrides.reminderChanges;
      final removals = overrides.reminderRemovals;
      final now = _now().millisecondsSinceEpoch;
      var changed = false;
      for (final entry
          in _activeOverrideReminderKeys({...pending.keys, ...removals.keys}).entries) {
        final action = sent[entry.value];
        if (action == null) continue;
        final removal = removals[entry.key];
        if (action == DeadlineReminderChange.remove &&
            removal != null &&
            (removal.after <= now || _customReminderChanges[entry.value] == action)) {
          removals.remove(entry.key);
          pending.remove(entry.key);
          changed = true;
        } else if (pending[entry.key] == action) {
          pending.remove(entry.key);
          changed = true;
        }
      }
      return changed;
    });
    if (_disposed || epoch != _identityEpoch) return;
    await _mutateCustomDeadlines(owner, (_, pending) {
      if (epoch != _identityEpoch) return false;
      final previousLength = pending.length;
      pending.removeWhere((key, change) => sent[key] == change);
      return pending.length != previousLength;
    });
  }

  Future<void> acknowledgeReminderEdits(
    Iterable<CustomDeadline> saved, {
    required int epoch,
  }) =>
      _mutateCustomDeadlines(_primaryIdentity, (deadlines, pending) {
        if (epoch != _identityEpoch) return false;
        var changed = false;
        for (final deadline in saved) {
          if (identical(deadlines[deadline.id], deadline) &&
              pending.remove(_reminderEditKey(deadline.id)) != null) {
            changed = true;
          }
        }
        return changed;
      });

  Future<void> applyReminderCompletions(
    Map<String, ({Assignment assignment, int completedAt})> completions, {
    required int epoch,
  }) async {
    if (completions.isEmpty) return;
    final owner = _primaryIdentity;
    await _mutateOverrides((overrides) {
      if (epoch != _identityEpoch) return false;
      var recorded = false;
      for (final entry in completions.entries) {
        final (:assignment, :completedAt) = entry.value;
        if (assignment is CustomDeadline ||
            overrides.reminderChanges.containsKey(
              _overrideReminderKey(assignment, entry.key),
            )) {
          continue;
        }
        final previous = overrides.reminderCompletions[entry.key];
        if (previous != null && previous >= completedAt) continue;
        overrides.reminderCompletions[entry.key] = completedAt;
        recorded = true;
        if (!overrides.effectiveCompleted(assignment)) {
          overrides.completed[AssignmentOverrides.keyFor(assignment)] = true;
        }
      }
      return recorded;
    });
    if (epoch != _identityEpoch || _disposed) return;
    await _mutateCustomDeadlines(owner, (deadlines, changes) {
      if (epoch != _identityEpoch) return false;
      var updated = false;
      for (final entry in completions.entries) {
        final (:assignment, :completedAt) = entry.value;
        if (assignment is! CustomDeadline || changes.containsKey(entry.key)) continue;
        final deadline = deadlines[assignment.id];
        if (deadline == null ||
            (deadline.reminderCompletedAt ?? -1) >= completedAt) {
          continue;
        }
        deadlines[assignment.id] =
            deadline.withCompletion(true, reminderCompletedAt: completedAt);
        updated = true;
      }
      return updated;
    });
  }

  Future<void> toggleCompleted(Assignment a) {
    if (a is CustomDeadline) return _setCustomCompletion(a.id);
    return _setOverrideCompletion(a);
  }

  Future<void> clearCompletionOverride(Assignment a) =>
      resetOverrides([AssignmentOverrides.keyFor(a)]);

  Future<void> resetOverrides(Iterable<String> keys) =>
      _mutateOverrides((overrides) {
        final removed = <String, bool>{
          for (final key in keys.toSet())
            if (overrides.completed.remove(key) case final completed?)
              key: completed,
        };
        for (final assignment in _remoteAssignments) {
          final previous = removed[AssignmentOverrides.keyFor(assignment)];
          if (previous != null && previous != assignment.submitted) {
            _recordReminderCompletion(
              overrides.reminderChanges,
              assignment,
              assignment.submitted,
            );
          }
        }
        return removed.isNotEmpty;
      });

  Future<void> hide(Assignment a, {Duration? reminderUndoWindow}) =>
      _mutateOverrides((overrides) {
        final key = AssignmentOverrides.keyFor(a);
        if (!overrides.hidden.add(key)) return false;
        if (_syncReminders && reminderUndoWindow != null) {
          overrides.reminderRemovals[_overrideReminderKey(a, reminderKeyFor(a))] = (
            assignmentKey: key,
            after: _now().add(reminderUndoWindow).millisecondsSinceEpoch,
          );
        }
        return true;
      });

  Future<void> unhide(String key) => _mutateOverrides((overrides) {
        if (!overrides.hidden.remove(key)) return false;
        _cancelReminderRemovals(overrides, {key});
        return true;
      });

  Future<void> unhideAll() => _mutateOverrides((overrides) {
        if (overrides.hidden.isEmpty) return false;
        _cancelReminderRemovals(overrides, overrides.hidden);
        overrides.hidden.clear();
        return true;
      });

  void _cancelReminderRemovals(AssignmentOverrides overrides, Set<String> keys) {
    final removals = overrides.reminderRemovals;
    for (final storedKey in _activeOverrideReminderKeys(removals.keys).keys) {
      if (keys.contains(removals[storedKey]!.assignmentKey)) removals.remove(storedKey);
    }
  }

  Future<void> clearAllOverrides() => _writes.protect(() async {
        if (_disposed) return;
        final reset = AssignmentOverrides(
          reminderChanges: {..._overrides.reminderChanges},
          reminderRemovals: {..._overrides.reminderRemovals},
        );
        if (reset.reminderChanges.isEmpty && reset.reminderRemovals.isEmpty) {
          await _storage.clearAssignmentOverrides();
        } else {
          await _storage.saveAssignmentOverrides(reset);
        }
        if (_disposed) return;
        _overrides = reset;
        notifyListeners();
      });

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
