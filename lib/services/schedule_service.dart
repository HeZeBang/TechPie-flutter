import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/course_table.dart';
import 'api_base_url.dart';
import 'auth_service.dart';
import 'http_client.dart';
import 'session/cookie_provider.dart';
import 'session/session_failure.dart';
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
  String? _owner;
  int _generation = -1;
  int _request = 0;
  bool _ready = false;
  bool _loading = false;
  SessionFailure? _failure;
  DateTime? _updatedAt;

  ScheduleService(this._storage, this._http, AuthService _, this._tpAuth) {
    _tpAuth.addListener(_onBindingChanged);
  }

  SemesterInfo? get semesterInfo => _semesterInfo;
  CourseTable? get courseTable => _courseTable;
  TermCalendar? get termCalendar => _termCalendar;
  DateTime? get termBegin => _termCalendar?.termBegin;
  String? get selectedSemesterId => _selectedSemesterId;
  String? get owner => _owner;
  bool get loading => _loading;
  String? get error => _failure?.message;
  SessionFailure? get failure => _failure;
  DateTime? get updatedAt => _updatedAt;
  // EAMS initializes its course and exam pages in the same server session.
  bool get suppressAssignmentRefetch => _loading;
  int get totalWeeks => (_termCalendar?.allTeachWeeks ?? 0) > 0
      ? _termCalendar!.allTeachWeeks
      : 25;

  int currentWeek() {
    final begin = termBegin;
    if (begin == null) return 1;
    return ((DateTime.now().difference(begin).inDays ~/ 7) + 1)
        .clamp(1, totalWeeks)
        .toInt();
  }

  bool get isTodayInTerm {
    final begin = termBegin;
    if (begin == null) return false;
    final days = DateTime.now().difference(begin).inDays;
    return days >= 0 && days ~/ 7 < totalWeeks;
  }

  void _readCache() {
    _semesterInfo =
        _owner == null ? null : _storage.loadSemesters(owner: _owner);
    _selectedSemesterId = _owner == null
        ? null
        : _storage.selectedSemesterFor(_owner!) ??
            _semesterInfo?.defaultSemester;
    _readSemesterCache();
  }

  void _readSemesterCache() {
    final id = _selectedSemesterId;
    _courseTable = _owner == null || id == null
        ? null
        : _storage.loadCourseTable(id, owner: _owner);
    _termCalendar = _owner == null || id == null
        ? null
        : _storage.loadTermCalendar(id, owner: _owner);
    _updatedAt = _owner == null || id == null
        ? null
        : _storage.scheduleUpdatedAt(_owner!, id);
  }

  void _onBindingChanged() {
    final node = _tpAuth.cpdailyNode;
    if (_generation == node.generation) return;
    _generation = node.generation;
    _owner = node.identityKey;
    _request++;
    _loading = false;
    _failure = null;
    _readCache();
    notifyListeners();
    if (_ready && _owner != null) unawaited(fetchAll());
  }

  Future<void> loadCachedData() async {
    _onBindingChanged();
    _ready = true;
  }

  Future<void> selectSemester(String semesterId) async {
    if (_selectedSemesterId == semesterId || _owner == null) return;
    _request++;
    _loading = false;
    _selectedSemesterId = semesterId;
    _readSemesterCache();
    await _storage.setSelectedSemester(semesterId, owner: _owner);
    await fetchAll();
  }

  Future<void> fetchAll() async {
    if (_loading || _owner == null) return;
    final owner = _owner!;
    final request = ++_request;
    _loading = true;
    _failure = null;
    notifyListeners();
    try {
      final semesters = SemesterInfo.fromJson(await _post('semesters', {}));
      if (request != _request) return;
      final id = _selectedSemesterId ?? semesters.defaultSemester;
      if (id.isEmpty) throw SessionFailure.unavailable;
      final tableData = await _post('course_table', {
        'semester_id': id,
        if (semesters.tableId.isNotEmpty) 'table_id': semesters.tableId,
      });
      if (tableData['courses'] is! List || tableData['periods'] is! List) {
        throw SessionFailure.unavailable;
      }
      final table = CourseTable.fromApiResponse(tableData);
      if (request != _request) return;
      String? year;
      String? term;
      for (final entry in semesters.semesters.entries) {
        for (final item in entry.value.entries) {
          if (item.value == id) {
            year = entry.key.split('-').first;
            final rank = semesterTermRank(item.key);
            term = rank < kSemesterTermNames.length ? '${rank + 1}' : '2';
          }
        }
      }
      if (year == null || term == null) throw SessionFailure.unavailable;
      final calendar = TermCalendar.fromJson(
        await _post('term_begin', {
          'year': year,
          'semester': term,
        }),
      );
      if (request != _request) return;
      final now = DateTime.now();
      _semesterInfo = semesters;
      _selectedSemesterId = id;
      _courseTable = table;
      _termCalendar = calendar;
      _updatedAt = now;
      await _storage.saveSemesters(semesters, owner: owner);
      await _storage.setSelectedSemester(id, owner: owner);
      await _storage.saveCourseTable(id, table, owner: owner);
      await _storage.saveTermCalendar(id, calendar, owner: owner);
      await _storage.saveScheduleUpdatedAt(owner, id, now);
    } catch (e) {
      if (request == _request) {
        _failure = e is SessionFailure ? e : SessionFailure.unavailable;
      }
    } finally {
      if (request == _request) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> extra,) async {
    final node = _tpAuth.eamsNode;
    final generation = node.generation;
    final response =
        await _tpAuth.sessionTree.withCookie<http.Response>(node, (cp) async {
      final r = await _http.post(
        Uri.parse('${apiBaseUrl(_storage)}/schedule/$path'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({..._authBody(cp), ...extra}),
        tag: 'schedule:$path',
      );
      return CookieAction(r, expired: r.statusCode == 401);
    });
    if (generation != node.generation) throw SessionFailure.changed;
    if (response == null) throw node.lastFailure ?? SessionFailure.unavailable;
    if (response.statusCode != 200) {
      throw SessionFailure.fromStatus(response.statusCode);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['success'] != true || data['data'] is! Map) {
      throw SessionFailure.unavailable;
    }
    return (data['data'] as Map).cast<String, dynamic>();
  }

  Map<String, dynamic> _authBody(CookieProvider cp) => {
        'studentId': cp.studentId,
        'cookies': cp.cookies,
      };

  @override
  void dispose() {
    _request++;
    _tpAuth.removeListener(_onBindingChanged);
    super.dispose();
  }
}
