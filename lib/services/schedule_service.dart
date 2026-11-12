import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/campus_identity.dart';
import '../models/course_table.dart';
import '../models/custom_course.dart';
import '../models/graduate_schedule.dart';
import 'api_base_url.dart';
import 'auth_service.dart';
import 'graduate_schedule_client.dart';
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
  GraduateSchedule? _graduateSchedule;
  String? _graduateScheme;
  String? _identityForAccount;
  bool _graduateIdentity = false;
  String? _identityLabel;
  String? _identityWarning;
  String? _observedAccount;
  int _accountRevision = 0;

  bool get isGraduate => _semesterInfo?.tableId == graduateTableId;
  bool get hasGraduateIdentity => _graduateIdentity;
  String? get identityLabel => _identityLabel;
  String? get identityWarning => _identityWarning;
  CampusScheduleSource get scheduleSource => _storage.scheduleSourceFor(_campusAccount());

  Future<void> selectScheduleSource(CampusScheduleSource source) async {
    if (_loading) throw const FormatException('课表加载中，请稍后切换来源');
    final owner = _campusAccount();
    if (owner == null) throw const FormatException('请先绑定 CpDaily / IDS');
    final saved = _storage.setScheduleSource(owner, source);
    _identityForAccount = null;
    _graduateIdentity = source == CampusScheduleSource.graduate;
    _identityLabel = null;
    _identityWarning = null;
    _restoreCachedSchedule(source);
    notifyListeners();
    await saved;
    if (owner == _campusAccount()) await fetchAll();
  }

  Map<String, String> get graduateSchemes => _selectedSemesterId == null
      ? const {}
      : _graduateSchedule?.schemesFor(_selectedSemesterId!) ?? const {};
  String? get graduateScheme => _graduateScheme;
  List<Map<String, dynamic>> get graduateUnarranged => _selectedSemesterId == null
      ? const []
      : _graduateSchedule?.unarrangedFor(_selectedSemesterId!) ?? const [];
  List<Map<String, dynamic>> get graduateCancelled => _selectedSemesterId == null
      ? const []
      : _graduateSchedule?.cancelledFor(_selectedSemesterId!) ?? const [];
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

  /// Calendar weeks in the selected semester, including an exam period after
  /// teaching ends. Falls back to a generous default until the calendar loads.
  int get totalWeeks {
    final calendar = _termCalendar;
    if (calendar == null) {
      if (isGraduate && _courseTable != null) {
        return _courseTable!.courses
            .fold<int>(_fallbackTotalWeeks, (max, c) => math.max(max, c.weeks.length - 1));
      }
      return _fallbackTotalWeeks;
    }
    final weeks = math.max(calendar.allTeachWeeks, calendar.allTermWeeks);
    return weeks > 0 ? weeks : _fallbackTotalWeeks;
  }

  ScheduleService(this._storage, this._http, AuthService _, this._tpAuth) {
    // A renewed campus session, a cookie minted for a child service (eams,
    // elearning, egateApp) or a cloud-sync merge that replaced the account can
    // each turn a fetch that was failing into one that works. They all go through
    // requestFetch, which decides whether they amount to anything.
    _observedAccount = _campusAccount();
    _tpAuth.addListener(_onCampusChanged);
  }

  void _onCampusChanged() {
    final account = _campusAccount();
    if (account != _observedAccount) {
      _observedAccount = account;
      _accountRevision++;
      _identityForAccount = null;
      _graduateIdentity = false;
      _identityLabel = null;
      _identityWarning = null;
      _fetchedForAccount = null;
      _clearSchedule();
      notifyListeners();
    }
    requestFetch();
  }

  /// The campus account the timetable currently in hand was fetched for.
  ///
  /// Only who it belongs to — not the session token, not when it was refreshed. A
  /// renewal of the same account leaves the timetable as valid as it was, and
  /// treating that as a change is how a routine token refresh turned into another
  /// round of requests. A rebind, a different account or a sync merge that
  /// replaces it does change this, and data fetched for another account has to go.
  String? _fetchedForAccount;

  Timer? _pendingFetch;

  String? _campusAccount() {
    final account = _tpAuth.cpdailyNode.account;
    if (account == null) return null;
    return '${account.sid}|${account.account}';
  }

  /// The one way anything asks for the timetable to be refetched.
  ///
  /// Three things used to ask on their own — the app starting, a binding
  /// changing, a session being renewed — and around a login they all fire inside
  /// the same second, so one login meant three rounds of three requests. Bursts
  /// collapse into a single fetch here, and a trigger that neither the user asked
  /// for nor changed the account does nothing at all.
  void requestFetch({bool force = false}) {
    final account = _campusAccount();
    final accountChanged = account != null && account != _fetchedForAccount;
    final usable = _semesterInfo != null && _error == null;
    if (!force && !accountChanged && usable) return;

    _pendingFetch?.cancel();
    _pendingFetch = Timer(const Duration(milliseconds: 600), () {
      // Decide again now, not only when the trigger arrived. A round that was
      // still running then could not answer "is the data usable?" — it had not
      // finished — so a trigger landing inside it (the keep-alive and renewal
      // notifications do exactly that) scheduled a second identical round of
      // semesters, course table and term begin. `force` is not a reason to round
      // again either: it means "do not trust what a previous launch cached", and
      // a round already fetched in this process for this account is the answer.
      final current = _campusAccount();
      final changed = current != null && current != _fetchedForAccount;
      if (_fetchedForAccount != null && !changed && _error == null) return;
      unawaited(fetchAll());
    });
  }

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

  // ── Sessions the user entered by hand ──
  // Read straight from storage, so no second copy can go stale on a semester
  // change.

  List<CustomCourse> get customCourses => customCoursesFor(_selectedSemesterId);

  CourseTable? courseTableFor(String? semesterId) {
    if (semesterId == null) return null;
    return semesterId == _selectedSemesterId
        ? _courseTable
        : _storage.loadCourseTable(semesterId, owner: _campusAccount());
  }

  TermCalendar? termCalendarFor(String? semesterId) {
    if (semesterId == null) return null;
    return semesterId == _selectedSemesterId
        ? _termCalendar
        : _storage.loadTermCalendar(semesterId);
  }

  List<CustomCourse> customCoursesFor(String? semesterId) =>
      semesterId == null ? const [] : _storage.loadCustomCourses(semesterId);

  CustomCourse? findCustomCourse(String id) =>
      customCourses.where((course) => course.id == id).firstOrNull;

  /// Adds [course], or replaces the session sharing its id. A session moved to
  /// another semester is dropped from the old one in the same step.
  Future<void> saveCustomCourse(String semesterId, CustomCourse course) async {
    final previous = course.semesterId;
    final courses = [...customCoursesFor(semesterId)];
    final index = courses.indexWhere((existing) => existing.id == course.id);
    final stored = course.copyWith(semesterId: semesterId);
    if (index < 0) {
      courses.add(stored);
    } else {
      courses[index] = stored;
    }
    await _storage.saveCustomCourses(semesterId, courses);
    if (previous.isNotEmpty && previous != semesterId) {
      await _removeCustomCourse(previous, course.id);
    }
    notifyListeners();
  }

  Future<void> deleteCustomCourse(String semesterId, String id) async {
    await _removeCustomCourse(semesterId, id);
    notifyListeners();
  }

  Future<void> _removeCustomCourse(String semesterId, String id) => _storage.saveCustomCourses(
        semesterId,
        customCoursesFor(semesterId).where((course) => course.id != id).toList(),
      );

  Future<void> loadCachedData() async {
    if (_campusAccount() == null) await _storage.clearGraduateScheduleCache();
    _restoreCachedSchedule(scheduleSource, onStartup: true);
    final selected = _selectedSemesterId;
    if (selected != null && _storage.selectedSemester != selected) {
      await _storage.setSelectedSemester(selected);
    }
    notifyListeners();
  }

  void _clearSchedule() {
    _semesterInfo = null;
    _selectedSemesterId = null;
    _courseTable = null;
    _termCalendar = null;
    _graduateSchedule = null;
    _graduateScheme = null;
    _error = null;
  }

  void _restoreCachedSchedule(CampusScheduleSource source, {bool onStartup = false}) {
    _clearSchedule();
    final owner = _campusAccount();
    final saved = _storage.loadSemesters();
    final kind = switch (source) {
      CampusScheduleSource.graduate => CampusStudentKind.graduate,
      CampusScheduleSource.undergraduate => CampusStudentKind.undergraduate,
      CampusScheduleSource.automatic => owner == null ? null : _storage.loadCampusIdentity(owner)?.kind,
    };
    // A fresh switch to automatic must wait for IDS when no identity is cached.
    // On boot, older installations can still display their last timetable.
    if (!onStartup && kind == null) return;
    final graduate = kind == null ? saved?.info.tableId == graduateTableId : kind == CampusStudentKind.graduate;
    if (graduate) {
      if (owner == null || _storage.graduateScheduleOwner != owner) return;
      _graduateSchedule = _storage.loadGraduateSchedule();
      _semesterInfo = _graduateSchedule?.semesterInfo;
      if (_semesterInfo == null) return;
    } else {
      if (saved != null &&
          (saved.info.tableId == graduateTableId || (saved.owner != null && saved.owner != owner))) {
        return;
      }
      _semesterInfo = saved?.info;
    }
    final cachedId = _storage.selectedSemester;
    // Older undergraduate caches may contain just a selected term and its calendar.
    if (_semesterInfo == null && (!onStartup || cachedId?.startsWith(graduateSemesterPrefix) != false)) {
      return;
    }
    final id = _validSemester(cachedId)!;
    _selectedSemesterId = id;
    _courseTable = _storage.loadCourseTable(id, owner: owner);
    _termCalendar = _storage.loadTermCalendar(id);
    if (_graduateSchedule != null) {
      _graduateScheme = _schemeFor(_graduateSchedule!, id);
      try {
        _courseTable = _graduateTable(_graduateSchedule!, id, _graduateScheme!);
      } on FormatException {
        _error = '研究生课表缓存需要刷新，请核对学期起始日';
      }
    }
  }

  String? _validSemester(String? selected) {
    final info = _semesterInfo;
    if (info == null || info.semesters.values.any((terms) => terms.containsValue(selected))) {
      return selected;
    }
    return info.defaultSemester;
  }

  Future<void> fetchAll() async {
    if (_loading) return; // 避免启动时并发重复调用
    if (!_hasCpdailyBinding) return;
    final revision = _accountRevision;
    _loading = true;
    _error = null;
    _identityWarning = null;
    notifyListeners();

    try {
      if (await _fetchGraduateIfEligible() || revision != _accountRevision) return;
      await fetchSemesters();
      if (revision != _accountRevision) return;
      _selectedSemesterId = _validSemester(_selectedSemesterId);
      if (_selectedSemesterId != null) {
        if (_storage.selectedSemester != _selectedSemesterId) {
          await _storage.setSelectedSemester(_selectedSemesterId!);
          if (revision != _accountRevision) return;
        }
        await Future.wait([
          fetchCourseTable(_selectedSemesterId!),
          _fetchTermBeginForSemester(_selectedSemesterId!),
        ]);
      }
    } catch (e) {
      if (revision == _accountRevision) _error = e.toString();
    } finally {
      _loading = false;
      if (revision == _accountRevision) {
        if (_error == null) _fetchedForAccount = _campusAccount();
      } else if (_hasCpdailyBinding) {
        requestFetch(force: true);
      }
      notifyListeners();
    }
  }

  /// Resolve the current IDS principal before touching either academic system.
  /// A failed graduate application is never evidence of undergraduate identity.
  Future<bool> _fetchGraduateIfEligible() async {
    final account = _campusAccount();
    if (account == null) return false;
    final revision = _accountRevision;
    final client =
        GraduateScheduleClient(_http, _tpAuth.cpdailyNode.rawFields['tgc'] as String? ?? '');
    if (_identityForAccount != account) {
      final source = scheduleSource;
      if (source != CampusScheduleSource.automatic) {
        _graduateIdentity = source == CampusScheduleSource.graduate;
        _identityLabel = _graduateIdentity ? '手动选择研究生课表' : '手动选择本科课表';
        _identityForAccount = account;
      } else {
        try {
          final identity = await client.identity(_tpAuth.cpdailyStudentId);
          if (revision != _accountRevision) return true;
          if (identity.kind == CampusStudentKind.unknown) {
            throw const CampusIdentityConflict('IDS 未返回可识别的本研身份，请手动选择课表来源');
          }
          _graduateIdentity = identity.kind == CampusStudentKind.graduate;
          _identityLabel = 'IDS：${identity.categoryName}';
          _identityWarning = null;
          _identityForAccount = account;
          await _storage.saveCampusIdentity(account, identity);
        } catch (error) {
          if (revision != _accountRevision) return true;
          final cached = _storage.loadCampusIdentity(account);
          if (error is CampusIdentityConflict ||
              cached == null ||
              cached.kind == CampusStudentKind.unknown) {
            throw FormatException('身份识别失败：${_schoolError(error)}；可手动选择课表来源');
          }
          _graduateIdentity = cached.kind == CampusStudentKind.graduate;
          _identityLabel = 'IDS 已缓存身份：${cached.categoryName}';
          _identityWarning = 'IDS 身份暂时无法刷新，沿用此账号已确认的身份';
        }
      }
    }
    if (revision != _accountRevision) return true;
    if (_semesterInfo == null || isGraduate != _graduateIdentity) {
      _restoreCachedSchedule(
        _graduateIdentity ? CampusScheduleSource.graduate : CampusScheduleSource.undergraduate,
      );
      notifyListeners();
    }
    if (!_graduateIdentity) return false;
    // Public info supplies the official current term, including empty terms.
    // A broken optional configuration endpoint must not discard an otherwise valid
    // timetable. Prefer its term labels only when the metadata is available.
    Map<String, dynamic> public = const {};
    try {
      public = await client.publicInfo();
    } catch (error) {
      if (revision != _accountRevision) return true;
      final warning = '学期配置暂时不可用：${_schoolError(error)}；按课表中的学期显示';
      _identityWarning = [_identityWarning, warning].whereType<String>().join('；');
    }
    if (revision != _accountRevision) return true;
    final Map<String, dynamic> raw;
    try {
      raw = await client.timetable();
    } catch (error) {
      throw FormatException('研究生课表获取失败：${_schoolError(error)}');
    }
    if (revision != _accountRevision) return true;
    final current = public['lcxxMap'];
    final snapshot = GraduateSchedule.fromJson({
      ...raw,
      if (current is Map) 'currentTerm': current['XNXQDM'],
      if (current is Map) 'currentTermName': current['XNXQMC'],
    });
    final info = snapshot.semesterInfo;
    final ids = info.semesters.values.expand((terms) => terms.values);
    final semester =
        ids.contains(_selectedSemesterId) ? _selectedSemesterId! : info.defaultSemester;
    final scheme = _schemeFor(snapshot, semester);
    final table = _graduateTable(snapshot, semester, scheme);
    // Parse before committing anything, so malformed responses retain the last
    // good timetable rather than caching an empty success.
    _graduateSchedule = snapshot;
    _graduateScheme = scheme;
    _semesterInfo = info;
    _selectedSemesterId = semester;
    _courseTable = table;
    await _storage.saveGraduateSchedule(account, snapshot);
    if (revision != _accountRevision) return true;
    await _storage.setSelectedSemester(semester);
    if (revision != _accountRevision) return true;
    await _storage.saveCourseTable(semester, table, owner: account);
    if (revision != _accountRevision) return true;
    await _loadGraduateCalendar(semester);
    return true;
  }

  String _schoolError(Object error) {
    if (error is FormatException) return error.message;
    if (error is TimeoutException) return '查询超时，请检查网络或稍后重试';
    return '网络请求失败（${error.runtimeType}），请检查学校会话和连接';
  }

  Future<void> _loadGraduateCalendar(String semesterId) async {
    _termCalendar = _storage.loadTermCalendar(semesterId);
    final inferred = _graduateSchedule?.firstMondayFor(semesterId);
    if (_termCalendar == null && inferred != null) {
      await setGraduateFirstMonday(inferred);
    }
  }

  String _schemeFor(GraduateSchedule snapshot, String semesterId) {
    final saved = _storage.graduateSchemeFor(semesterId);
    return saved != null && snapshot.schemesFor(semesterId).containsKey(saved)
        ? saved
        : snapshot.defaultScheme(semesterId);
  }

  CourseTable _graduateTable(GraduateSchedule snapshot, String semester, String scheme) => snapshot
      .tableFor(semester, scheme, firstMonday: _storage.loadTermCalendar(semester)?.termBegin);

  Future<void> setGraduateFirstMonday(DateTime date) async {
    if (!isGraduate || _selectedSemesterId == null || date.weekday != DateTime.monday) {
      throw const FormatException('请选择研究生学期第 1 周的周一');
    }
    final semester = _selectedSemesterId!;
    final revision = _accountRevision;
    final owner = _campusAccount();
    final table =
        _graduateSchedule!.tableFor(semester, _graduateScheme!, firstMonday: date);
    final weeks =
        table.courses.fold<int>(_fallbackTotalWeeks, (n, c) => math.max(n, c.weeks.length - 1));
    _termCalendar = TermCalendar(
      code: 200,
      schoolYearTerm: semester,
      termBegin: DateTime(date.year, date.month, date.day),
      snapshotDate: null,
      snapshotWeekOfTerm: null,
      allTeachWeeks: weeks,
      allTermWeeks: weeks,
      amClasses: 0,
      pmClasses: 0,
      eveClasses: 0,
    );
    await _storage.saveTermCalendar(semester, _termCalendar!);
    if (revision != _accountRevision) return;
    _courseTable = table;
    await _storage.saveCourseTable(semester, table, owner: owner);
    if (revision != _accountRevision) return;
    notifyListeners();
  }

  Future<void> selectGraduateScheme(String scheme) async {
    final semester = _selectedSemesterId;
    if (_graduateSchedule == null || semester == null || !graduateSchemes.containsKey(scheme)) {
      return;
    }
    final revision = _accountRevision;
    final owner = _campusAccount();
    final table = _graduateTable(_graduateSchedule!, semester, scheme);
    _graduateScheme = scheme;
    _courseTable = table;
    await _storage.setGraduateScheme(semester, scheme);
    if (revision != _accountRevision) return;
    await _storage.saveCourseTable(semester, table, owner: owner);
    if (revision != _accountRevision) return;
    notifyListeners();
  }

  Future<void> fetchSemesters() async {
    final owner = _campusAccount();
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
    await _storage.saveSemesters(_semesterInfo!, owner: owner);
    notifyListeners();
  }

  Future<void> fetchCourseTable(String semesterId) async {
    if (semesterId.startsWith(graduateSemesterPrefix)) {
      if (_graduateSchedule == null) throw const FormatException('请先刷新研究生课表');
      final revision = _accountRevision;
      final owner = _campusAccount();
      final scheme = _schemeFor(_graduateSchedule!, semesterId);
      final table = _graduateTable(_graduateSchedule!, semesterId, scheme);
      _graduateScheme = scheme;
      _courseTable = table;
      await _storage.saveCourseTable(semesterId, table, owner: owner);
      if (revision != _accountRevision) return;
      notifyListeners();
      return;
    }
    final owner = _campusAccount();
    final extra = <String, dynamic>{
      'semester_id': semesterId,
      if (_semesterInfo?.tableId.isNotEmpty == true) 'table_id': _semesterInfo!.tableId,
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
    await _storage.saveCourseTable(semesterId, _courseTable!, owner: owner);
    notifyListeners();
  }

  Future<void> _fetchTermBeginForSemester(String semesterId) async {
    if (semesterId.startsWith(graduateSemesterPrefix)) {
      await _loadGraduateCalendar(semesterId);
      return;
    }
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
          semNum = rank < kSemesterTermNames.length ? (rank + 1).toString() : '2';
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
    final revision = _accountRevision;
    _selectedSemesterId = semesterId;
    await _storage.setSelectedSemester(semesterId);
    if (revision != _accountRevision) return;

    // Load cached data for the new semester so the UI updates instantly.
    _courseTable = _storage.loadCourseTable(semesterId, owner: _campusAccount());
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
      if (revision == _accountRevision) _error = e.toString();
    } finally {
      _loading = false;
      _suppressAssignmentRefetch = false;
      if (revision != _accountRevision && _hasCpdailyBinding) requestFetch(force: true);
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
    final revision = _accountRevision;
    final node = _tpAuth.eamsNode;
    final resp = await _tpAuth.sessionTree.withCookie<http.Response>(
      node,
      (cp) async {
        if (revision != _accountRevision) throw StateError('学校账号已切换');
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
    if (revision != _accountRevision) throw StateError('学校账号已切换');
    if (resp == null) {
      throw Exception('cpdaily session unavailable');
    }
    if (resp.statusCode != 200) {
      throw Exception('Request failed with status ${resp.statusCode}');
    }
    return resp;
  }

  @override
  void dispose() {
    _pendingFetch?.cancel();
    _tpAuth.removeListener(_onCampusChanged);
    super.dispose();
  }
}
