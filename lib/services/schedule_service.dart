import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/campus_identity.dart';
import '../models/course.dart';
import '../models/course_table.dart';
import '../models/custom_course.dart';
import '../models/graduate_schedule.dart';
import 'api_base_url.dart';
import 'auth_service.dart';
import 'graduate_schedule_client.dart';
import 'http_client.dart';
import 'school_calendar_client.dart';
import 'session/cookie_provider.dart';
import 'session/session_tree.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

typedef _GraduateTerm = ({Map<String, CourseTable> tables, TermCalendar? calendar});
typedef _FetchContext = ({int accountRevision, String? idsSession});

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
  Map<String, CourseTable> _graduateTables = const {};
  String? _graduateScheme;
  String? _identityForAccount;
  String? _identityForSession;
  bool _identityResolved = false;
  Completer<void>? _fetchCompletion;
  bool _graduateIdentity = false;
  String? _identityLabel;
  String? _identityWarning;
  String? _observedAccount;
  String? _observedIdsSession;
  int _accountRevision = 0;

  bool get isGraduate => _semesterInfo?.tableId == graduateTableId;
  bool get hasGraduateIdentity => _graduateIdentity;
  String? get identityLabel => _identityLabel;
  String? get identityWarning => _identityWarning;
  CampusScheduleSource get scheduleSource => _storage.scheduleSourceFor(_campusAccount());
  String? get _idsSession => _tpAuth.idsNode.cookieProvider?.cookies;
  bool get _identityIsCurrent => _identityResolved &&
      (scheduleSource != CampusScheduleSource.automatic || _identityForSession == _idsSession);

  Future<void> selectScheduleSource(CampusScheduleSource source) async {
    if (_loading) throw const FormatException('课表加载中，请稍后切换来源');
    final owner = _campusAccount();
    if (owner == null) throw const FormatException('请先绑定 CpDaily / IDS');
    final saved = _storage.setScheduleSource(owner, source);
    _identityForAccount = null;
    _identityForSession = null;
    _identityResolved = false;
    _graduateIdentity = source == CampusScheduleSource.graduate;
    _identityLabel = null;
    _identityWarning = null;
    _restoreCachedSchedule(source);
    _suppressAssignmentRefetch = true;
    notifyListeners();
    try {
      await saved;
      if (owner == _campusAccount()) await fetchAll();
    } finally {
      _suppressAssignmentRefetch = false;
      notifyListeners();
    }
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
  // Delay exam refreshes until a changed timetable selection has finished
  // priming the stateful EAMS session.
  bool _suppressAssignmentRefetch = false;
  bool get suppressAssignmentRefetch => _suppressAssignmentRefetch;

  String get _baseUrl => apiBaseUrl(_storage);

  // Fallback used before the school calendar has been fetched at least once.
  static const _fallbackTotalWeeks = 25;

  SemesterInfo? get semesterInfo => _semesterInfo;
  CourseTable? get courseTable => _courseTable;

  /// All fetched courses, with the selected period grid for display.
  CourseTable? get fullCourseTable {
    final table = _courseTable;
    if (table == null || _graduateTables.length <= 1) return table;
    return CourseTable(
      periods: table.periods,
      courses: [for (final schemeTable in _graduateTables.values) ...schemeTable.courses],
    );
  }

  TermCalendar? get termCalendar => _termCalendar;
  DateTime? get termBegin => _termCalendar?.termBegin;
  String? get selectedSemesterId => _selectedSemesterId;
  int get campusAccountRevision => _accountRevision;
  bool get loading => _loading;
  String? get error => _error;

  /// Calendar weeks in the selected semester, including an exam period after
  /// teaching ends. Falls back to a generous default until the calendar loads.
  int get totalWeeks => _lastGraduateWeek(_graduateTables, _calendarWeeks);

  int get _calendarWeeks {
    final calendar = _termCalendar;
    if (calendar == null) return _fallbackTotalWeeks;
    final weeks = math.max(calendar.allTeachWeeks, calendar.allTermWeeks);
    return weeks > 0 ? weeks : _fallbackTotalWeeks;
  }

  static int _lastGraduateWeek(Map<String, CourseTable> tables, int minimum) => tables.values
      .expand((table) => table.courses)
      .fold<int>(minimum, (max, course) => math.max(max, course.weeks.length - 1));

  ScheduleService(this._storage, this._http, AuthService _, this._tpAuth) {
    _observedAccount = _campusAccount();
    _observedIdsSession = _idsSession;
    // Passkey replacement suppresses facade notifications until persistence
    // finishes. Observe the IDS node so old timetable requests expire at once.
    _tpAuth.idsNode.addListener(_onCampusChanged);
  }

  void _onCampusChanged() {
    final account = _campusAccount();
    final session = _idsSession;
    final accountChanged = account != _observedAccount;
    final sessionChanged = session != _observedIdsSession;
    _observedIdsSession = session;
    if (accountChanged) {
      _observedAccount = account;
      _accountRevision++;
      _identityForAccount = null;
      _identityForSession = null;
      _identityResolved = false;
      _graduateIdentity = false;
      _identityLabel = null;
      _identityWarning = null;
      _clearSchedule();
      notifyListeners();
    }
    // Failure notifications and clearing a cookie supply no usable session.
    if (account != null && (accountChanged || (sessionChanged && session != null))) {
      requestFetch();
    }
  }

  _FetchContext? _lastFetch;
  _FetchContext get _fetchContext => (accountRevision: _accountRevision, idsSession: _idsSession);
  Timer? _pendingFetch;

  String? _campusAccount() {
    final account = _tpAuth.idsNode.account;
    if (account == null) return null;
    return '${account.sid}|${account.account}';
  }

  bool _needsFetch({required bool retry}) {
    if (!_hasIdsBinding) return false;
    final previous = _lastFetch;
    if (previous == null || previous.accountRevision != _accountRevision) return true;
    if (retry && _error != null) return true;
    return previous.idsSession != _idsSession &&
        (scheduleSource == CampusScheduleSource.automatic ||
            _loading ||
            _semesterInfo == null ||
            _error != null);
  }

  /// Combine boot and binding notifications for the same IDS account and
  /// session. A failed renewal still notifies listeners, with the same session.
  void requestFetch({bool force = false}) {
    final retry = force && !_loading;
    if (!_needsFetch(retry: retry)) return;

    _pendingFetch?.cancel();
    _pendingFetch = Timer(const Duration(milliseconds: 600), () async {
      // Let an in-flight round finish before deciding whether it covered the
      // account and session that triggered this refresh.
      final timer = _pendingFetch;
      final active = _fetchCompletion;
      if (active != null) await active.future;
      if (_pendingFetch != timer) return;
      _pendingFetch = null;
      if (_needsFetch(retry: retry)) await fetchAll();
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
  /// last calendar week. Callers should hide "this week"/"today" indicators
  /// when this is false, since there is no meaningful "current week".
  bool get isTodayInTerm {
    final begin = termBegin;
    if (begin == null) return false;
    final diff = DateTime.now().difference(begin).inDays;
    if (diff < 0) return false;
    final week = (diff ~/ 7) + 1;
    return week <= _calendarWeeks;
  }

  Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json; charset=UTF-8',
      };

  /// Auth payload built from a [CookieProvider] snapshot captured at request
  /// time. The epoch captured alongside is what makes the renew-retry
  /// storm-safe (see [_postWithRetry]).
  Map<String, dynamic> _authBody(CookieProvider cp) => {
        // eams downstream cookie; studentId comes from the ids binding.
        'studentId': _tpAuth.idsNode.account?.sid ?? '',
        'cookies': cp.cookies,
      };

  bool get _hasIdsBinding => _tpAuth.hasIdsBinding;

  // ── Sessions the user entered by hand ──
  // Read straight from storage, so no second copy can go stale on a semester
  // change.

  List<CustomCourse> get customCourses => customCoursesFor(_selectedSemesterId);

  CourseTable? courseTableForWatch(String watchOwner) {
    final id = _selectedSemesterId;
    if (id == null) return null;
    return _storage.loadCourseTable(id, owner: _campusAccount(), watchOwner: watchOwner);
  }

  Future<void> adoptLegacyCourseTable(String watchOwner) async {
    final id = _selectedSemesterId;
    if (id != null && _courseTable != null && !_loading) {
      await _storage.adoptLegacyCourseTable(id, _campusAccount(), watchOwner);
    }
  }

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
      semesterId == null ? const [] : _storage.loadCustomCourses(semesterId, owner: _campusAccount());

  CustomCourse? findCustomCourse(String id) =>
      customCourses.where((course) => course.id == id).firstOrNull;

  /// Adds [course], or replaces the session sharing its id. A session moved to
  /// another semester is dropped from the old one in the same step.
  Future<void> saveCustomCourse(
    String semesterId,
    CustomCourse course, {
    List<Period>? periods,
  }) async {
    final owner = _campusAccount();
    final previous = course.semesterId;
    final courses = [..._storage.loadCustomCourses(semesterId, owner: owner)];
    final index = courses.indexWhere((existing) => existing.id == course.id);
    var stored = course.copyWith(semesterId: semesterId);
    if (semesterId.startsWith(graduateSemesterPrefix) && stored.usesPeriods) {
      final grid = periods ?? courseTableFor(semesterId)?.periods.map((p) => p.toPeriod()).toList();
      if (grid != null) stored = stored.withFixedTime(grid);
    }
    if (index < 0) {
      courses.add(stored);
    } else {
      courses[index] = stored;
    }
    await _storage.saveCustomCourses(semesterId, courses, owner: owner);
    if (previous.isNotEmpty && previous != semesterId) {
      await _removeCustomCourse(previous, course.id, owner);
    }
    notifyListeners();
  }

  Future<void> deleteCustomCourse(String semesterId, String id) async {
    await _removeCustomCourse(semesterId, id, _campusAccount());
    notifyListeners();
  }

  Future<void> _removeCustomCourse(String semesterId, String id, String? owner) =>
      _storage.saveCustomCourses(
        semesterId,
        _storage
            .loadCustomCourses(semesterId, owner: owner)
            .where((course) => course.id != id)
            .toList(),
        owner: owner,
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
    _graduateTables = const {};
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
    if (_graduateSchedule case final snapshot?) {
      try {
        _applyGraduateTerm(_buildGraduateTerm(snapshot, id), _schemeFor(snapshot, id));
      } on FormatException {
        _error = '研究生课表日期缓存需要刷新';
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

  Future<bool> canFetchUndergraduateExams() async {
    if (!_hasIdsBinding || scheduleSource == CampusScheduleSource.graduate) return false;
    final revision = _accountRevision;
    final active = _fetchCompletion;
    if (active != null) {
      await active.future;
    } else if (scheduleSource == CampusScheduleSource.automatic && !_identityIsCurrent) {
      await fetchAll();
    }
    if (revision != _accountRevision) return false;
    return switch (scheduleSource) {
      CampusScheduleSource.undergraduate => true,
      CampusScheduleSource.graduate => false,
      CampusScheduleSource.automatic =>
        _idsSession != null && _identityIsCurrent && !_graduateIdentity,
    };
  }

  Future<void> fetchAll() async {
    if (_loading) {
      await _fetchCompletion?.future;
      return;
    }
    if (!_hasIdsBinding) return;
    _pendingFetch?.cancel();
    _pendingFetch = null;
    _lastFetch = _fetchContext;
    final completion = _fetchCompletion = Completer<void>();
    final revision = _accountRevision;
    _loading = true;
    _error = null;
    _identityWarning = null;
    notifyListeners();

    try {
      if (await _fetchGraduateIfEligible() || revision != _accountRevision) return;
      await fetchSemesters();
      if (revision != _accountRevision || !_identityIsCurrent) return;
      _selectedSemesterId = _validSemester(_selectedSemesterId);
      if (_selectedSemesterId != null) {
        if (_storage.selectedSemester != _selectedSemesterId) {
          await _storage.setSelectedSemester(_selectedSemesterId!);
          if (revision != _accountRevision || !_identityIsCurrent) return;
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
      if (revision == _accountRevision && _error == null && _identityIsCurrent) {
        _lastFetch = _fetchContext;
      }
      _fetchCompletion = null;
      completion.complete();
      notifyListeners();
    }
  }

  Future<({GraduateScheduleClient client, String session})> _graduateClient() async {
    final revision = _accountRevision;
    final cookie = await _tpAuth.sessionTree.freshCookie(_tpAuth.idsNode);
    if (cookie == null) throw const FormatException('IDS 学校会话暂时不可用，请刷新 IDS 绑定');
    // This fetch already uses the session reported by the renewal notification.
    if (revision == _accountRevision && cookie.cookies == _idsSession) _lastFetch = _fetchContext;
    final tgc = RegExp(r'(?:^|;)\s*CASTGC=([^;]*)').firstMatch(cookie.cookies)?.group(1) ??
        _tpAuth.idsNode.rawFields['tgc'] as String? ?? '';
    return (client: GraduateScheduleClient(_http, tgc), session: cookie.cookies);
  }

  /// Resolve the current IDS principal before touching either academic system.
  /// A failed graduate application is never evidence of undergraduate identity.
  Future<bool> _fetchGraduateIfEligible() async {
    final account = _campusAccount();
    if (account == null) return false;
    final revision = _accountRevision;
    late final client = _graduateClient();
    final source = scheduleSource;
    if (source != CampusScheduleSource.automatic) {
      _graduateIdentity = source == CampusScheduleSource.graduate;
      _identityLabel = _graduateIdentity ? '手动选择研究生课表' : '手动选择本科课表';
      _identityForAccount = account;
      _identityForSession = _idsSession;
    } else {
      var session = _idsSession;
      try {
        final school = await client;
        session = school.session;
        if (revision != _accountRevision || session != _idsSession) return true;
        if (_identityForAccount != account || !_identityIsCurrent) {
          _identityResolved = false;
          final identity = await school.client.identity(_tpAuth.idsStudentId);
          if (revision != _accountRevision || session != _idsSession) return true;
          if (identity.kind == CampusStudentKind.unknown) {
            throw const CampusIdentityConflict('IDS 未返回可识别的本研身份，请手动选择课表来源');
          }
          _graduateIdentity = identity.kind == CampusStudentKind.graduate;
          _identityLabel = 'IDS：${identity.categoryName}';
          _identityWarning = null;
          _identityForAccount = account;
          _identityForSession = session;
          await _storage.saveCampusIdentity(account, identity);
        }
      } catch (error) {
        if (revision != _accountRevision || session != _idsSession) return true;
        _identityResolved = false;
        _identityForAccount = null;
        if (error is CampusIdentityConflict) {
          await _storage.clearCampusIdentity();
          if (revision != _accountRevision || session != _idsSession) return true;
        }
        final cached = _storage.loadCampusIdentity(account);
        if (error is CampusIdentityConflict ||
            cached == null ||
            cached.kind == CampusStudentKind.unknown) {
          throw FormatException('身份识别失败：${_schoolError(error)}；可手动选择课表来源');
        }
        _graduateIdentity = cached.kind == CampusStudentKind.graduate;
        _identityLabel = 'IDS 已缓存身份：${cached.categoryName}';
        _identityWarning = 'IDS 身份暂时无法刷新，沿用此账号已确认的身份';
        _identityForSession = session;
      }
    }
    if (revision != _accountRevision ||
        (source == CampusScheduleSource.automatic && _identityForSession != _idsSession)) {
      return true;
    }
    _identityResolved = true;
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
      public = await (await client).client.publicInfo();
    } catch (error) {
      if (revision != _accountRevision || !_identityIsCurrent) return true;
      final warning = '学期配置暂时不可用：${_schoolError(error)}；按课表中的学期显示';
      _identityWarning = [_identityWarning, warning].whereType<String>().join('；');
    }
    if (revision != _accountRevision || !_identityIsCurrent) return true;
    final Map<String, dynamic> raw;
    try {
      raw = await (await client).client.timetable();
    } catch (error) {
      throw FormatException('研究生课表获取失败：${_schoolError(error)}');
    }
    if (revision != _accountRevision || !_identityIsCurrent) return true;
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
    final term = _buildGraduateTerm(snapshot, semester);
    // Parse before committing anything, so malformed responses retain the last
    // good timetable rather than caching an empty success.
    _graduateSchedule = snapshot;
    _semesterInfo = info;
    _selectedSemesterId = semester;
    _applyGraduateTerm(term, scheme);
    await _storage.saveGraduateSchedule(account, snapshot);
    if (revision != _accountRevision || !_identityIsCurrent) return true;
    await _storage.setSelectedSemester(semester);
    if (revision != _accountRevision || !_identityIsCurrent) return true;
    await _saveGraduateTerm(semester, term, scheme);
    return true;
  }

  String _schoolError(Object error) {
    if (error is FormatException) return error.message;
    if (error is TimeoutException) return '查询超时，请检查网络或稍后重试';
    return '网络请求失败（${error.runtimeType}），请检查学校会话和连接';
  }

  String _schemeFor(GraduateSchedule snapshot, String semesterId) {
    final saved = _storage.graduateSchemeFor(semesterId);
    return saved != null && snapshot.schemesFor(semesterId).containsKey(saved)
        ? saved
        : snapshot.defaultScheme(semesterId);
  }

  _GraduateTerm _buildGraduateTerm(GraduateSchedule snapshot, String semester) {
    final date =
        snapshot.firstMondayFor(semester) ?? _storage.loadTermCalendar(semester)?.termBegin;
    final tables = {
      for (final scheme in snapshot.schemesFor(semester).keys)
        scheme: snapshot.tableFor(semester, scheme, firstMonday: date),
    };
    if (date == null) return (tables: tables, calendar: null);
    final published = snapshot.publishedCalendarFor(semester);
    final weeks = published?.termWeeks ?? _lastGraduateWeek(tables, _fallbackTotalWeeks);
    final calendar = TermCalendar(
      code: 200,
      schoolYearTerm: semester,
      termBegin: date,
      snapshotDate: null,
      snapshotWeekOfTerm: null,
      allTeachWeeks: published?.teachingWeeks ?? weeks,
      allTermWeeks: weeks,
      amClasses: 0,
      pmClasses: 0,
      eveClasses: 0,
    );
    return (tables: tables, calendar: calendar);
  }

  void _applyGraduateTerm(_GraduateTerm term, String scheme) {
    _graduateTables = term.tables;
    _termCalendar = term.calendar;
    _graduateScheme = scheme;
    _courseTable = term.tables[scheme]!;
  }

  Future<void> _saveGraduateTerm(String semester, _GraduateTerm term, String scheme) async {
    final revision = _accountRevision;
    final owner = _campusAccount();
    final session = _idsSession;
    if (term.calendar case final calendar?) {
      await _storage.saveTermCalendar(semester, calendar);
      if (revision != _accountRevision || session != _idsSession) return;
    }
    await _storage.saveCourseTable(semester, term.tables[scheme]!, owner: owner);
    if (revision == _accountRevision && session == _idsSession) notifyListeners();
  }

  Future<void> selectGraduateScheme(String scheme) async {
    final semester = _selectedSemesterId;
    final table = _graduateTables[scheme];
    if (semester == null || table == null || scheme == _graduateScheme) return;
    final revision = _accountRevision;
    final owner = _campusAccount();
    // Older records have only period numbers. Preserve their current clock
    // times before the selected grid changes.
    final courses = customCourses;
    if (courses.any((course) => course.usesPeriods)) {
      final periods = _courseTable!.periods.map((p) => p.toPeriod()).toList();
      await _storage.saveCustomCourses(
        semester,
        courses.map((course) => course.withFixedTime(periods)).toList(),
        owner: owner,
      );
      if (revision != _accountRevision || semester != _selectedSemesterId) return;
    }
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
    await _postWithRetry(
      '$_baseUrl/schedule/semesters',
      const <String, dynamic>{},
      'fetchSemesters',
      (data) async {
        _semesterInfo = SemesterInfo.fromJson(data);
        await _storage.saveSemesters(_semesterInfo!, owner: owner);
        notifyListeners();
      },
    );
  }

  Future<void> fetchCourseTable(String semesterId) async {
    if (semesterId.startsWith(graduateSemesterPrefix)) {
      final snapshot = _graduateSchedule;
      if (snapshot == null) throw const FormatException('请先刷新研究生课表');
      final scheme = _schemeFor(snapshot, semesterId);
      final term = _buildGraduateTerm(snapshot, semesterId);
      _applyGraduateTerm(term, scheme);
      await _saveGraduateTerm(semesterId, term, scheme);
      return;
    }
    final owner = _campusAccount();
    final extra = <String, dynamic>{
      'semester_id': semesterId,
      if (_semesterInfo?.tableId.isNotEmpty == true) 'table_id': _semesterInfo!.tableId,
    };

    await _postWithRetry(
      '$_baseUrl/schedule/course_table',
      extra,
      'fetchCourseTable',
      (data) async {
        if (semesterId != _selectedSemesterId) return;
        _courseTable = CourseTable.fromApiResponse(data);
        await _storage.saveCourseTable(semesterId, _courseTable!, owner: owner);
        notifyListeners();
      },
    );
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
    final revision = _accountRevision;
    final automatic = scheduleSource == CampusScheduleSource.automatic;
    const changedSession = FormatException('IDS 会话不可用或已变更，请刷新课表');

    void checkIdentity() {
      if (revision != _accountRevision) throw StateError('学校账号已切换');
      if (automatic && (!_identityIsCurrent || _graduateIdentity || _idsSession == null)) {
        throw changedSession;
      }
    }

    checkIdentity();
    String? requestSession;
    final calendar = await _tpAuth.sessionTree.withCookie<TermCalendar?>(
      _tpAuth.idsNode,
      (cp) async {
        checkIdentity();
        final session = requestSession = _idsSession;
        final tgc = RegExp(r'(?:^|;)\s*CASTGC=([^;]*)').firstMatch(cp.cookies)?.group(1) ??
            _tpAuth.idsNode.rawFields['tgc'] as String? ??
            '';
        final result = await SchoolCalendarClient(_http, tgc).fetchTermCalendar(
          year: year,
          semester: semester,
        );
        checkIdentity();
        if (session != _idsSession) throw changedSession;
        return CookieAction(result.calendar, expired: result.sessionExpired);
      },
    );
    checkIdentity();
    if (requestSession != _idsSession) throw changedSession;
    if (calendar == null) {
      throw const FormatException('校历登录会话已失效，请刷新 IDS 绑定后重试');
    }
    if (_selectedSemesterId != null && cacheKey != _selectedSemesterId) return;
    _termCalendar = calendar;
    await _storage.saveTermCalendar(cacheKey, _termCalendar!);
    notifyListeners();
  }

  Future<void> selectSemester(String semesterId) async {
    final revision = _accountRevision;
    final active = _fetchCompletion;
    if (active != null) await active.future;
    if (revision != _accountRevision || _selectedSemesterId == semesterId) return;
    _selectedSemesterId = semesterId;
    await _storage.setSelectedSemester(semesterId);
    if (revision != _accountRevision) return;

    // Load cached data for the new semester so the UI updates instantly.
    _courseTable = _storage.loadCourseTable(semesterId, owner: _campusAccount());
    _termCalendar = _storage.loadTermCalendar(semesterId);
    _graduateTables = const {};
    // Notify the cached-swap UI update. AssignmentService._onScheduleChanged
    // sees the semester changed and would fire fetchAssignments here — but
    // that would race our own fetchCourseTable below (both hit
    // courseTableForStd.action on the same EAMS session, and concurrent
    // access to EAMS's stateful Spring/Struts session returns a partially
    // initialized page → "Failed to extract numeric ids"). We suppress the
    // assignment refetch during our own fetch and fire it once at the end.
    _suppressAssignmentRefetch = true;
    notifyListeners();

    if (!_hasIdsBinding) {
      _suppressAssignmentRefetch = false;
      return;
    }

    final graduate = semesterId.startsWith(graduateSemesterPrefix);
    if (!graduate && scheduleSource == CampusScheduleSource.automatic && !_identityIsCurrent) {
      await fetchAll();
      _suppressAssignmentRefetch = false;
      notifyListeners();
      return;
    }

    final completion = _fetchCompletion = Completer<void>();
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.wait([
        fetchCourseTable(semesterId),
        if (!graduate) _fetchTermBeginForSemester(semesterId),
      ]);
    } catch (e) {
      if (revision == _accountRevision) _error = e.toString();
    } finally {
      _loading = false;
      _suppressAssignmentRefetch = false;
      _fetchCompletion = null;
      completion.complete();
      // This final notify fires _onScheduleChanged again. Because
      // _suppressAssignmentRefetch is now false, AssignmentService will
      // refetch (the EAMS session is primed by our fetchCourseTable above,
      // so exam_table succeeds on the first try).
      notifyListeners();
    }
  }

  /// EAMS can renew the IDS parent while acquiring or retrying a cookie.
  /// A new IDS session in automatic mode must first go through classification.
  Future<void> _postWithRetry(
    String url,
    Map<String, dynamic> extra,
    String tag,
    Future<void> Function(Map<String, dynamic>) accept,
  ) async {
    final revision = _accountRevision;
    final automatic = scheduleSource == CampusScheduleSource.automatic;
    const changedSession = FormatException('IDS 会话不可用或已变更，请刷新课表');

    void checkIdentity() {
      if (revision != _accountRevision) throw StateError('学校账号已切换');
      if (automatic && (!_identityIsCurrent || _graduateIdentity || _idsSession == null)) {
        throw changedSession;
      }
    }

    checkIdentity();
    String? requestSession;
    final resp = await _tpAuth.sessionTree.withCookie<http.Response>(
      _tpAuth.eamsNode,
      (cp) async {
        checkIdentity();
        final session = requestSession = _idsSession;
        final body = {..._authBody(cp), ...extra};
        final r = await _http.post(
          Uri.parse(url),
          headers: _jsonHeaders(),
          body: jsonEncode(body),
          tag: tag,
        );
        checkIdentity();
        if (session != _idsSession) throw changedSession;
        return CookieAction(
          r,
          expired: r.statusCode == 401,
        );
      },
    );
    checkIdentity();
    if (resp == null) {
      throw Exception('ids session unavailable');
    }
    if (requestSession != _idsSession) throw changedSession;
    if (resp.statusCode != 200) {
      if (resp.statusCode == 401) {
        throw const FormatException('教务系统登录态已失效（HTTP 401），请刷新 IDS 绑定后重试');
      }
      String? backendError;
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['error'] is String) {
          backendError = (decoded['error'] as String).trim();
        }
      } on FormatException {
        // Non-JSON error body; fall back to HTTP status.
      }
      throw FormatException(
        backendError != null && backendError.isNotEmpty
            ? '课表服务请求失败（HTTP ${resp.statusCode}）：$backendError'
            : '课表服务请求失败（HTTP ${resp.statusCode}）',
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] as String? ?? '$tag failed');
    }
    await accept(data['data'] as Map<String, dynamic>);
  }

  @override
  void dispose() {
    _pendingFetch?.cancel();
    _pendingFetch = null;
    _tpAuth.idsNode.removeListener(_onCampusChanged);
    super.dispose();
  }
}
