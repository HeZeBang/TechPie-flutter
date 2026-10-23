import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/oa_gym.dart';
import '../models/third_party_account.dart';
import 'api_base_url.dart';
import 'auth_service.dart';
import 'session/cookie_provider.dart';
import 'session/session_tree.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

class OaGymException implements Exception {
  final String message;
  OaGymException(this.message);

  @override
  String toString() => message;
}

class OaGymService extends ChangeNotifier {
  final AuthService _auth;
  final StorageService _storage;
  final ThirdPartyAuthService _tpAuth;
  final http.Client _client;

  bool _sessionReady = false;
  bool _metadataReady = false;
  bool _loading = false;
  int _activeRequests = 0;
  int _generation = 0;
  Future<void>? _metadataRequest;
  Future<void> _availabilityTail = Future.value();
  String _oaCookies = '';
  String _oaIdentity = '';
  bool _bulkSearchSupported = false;
  Map<String, String> _venues = {};
  Map<String, String> _allVenues = {};
  Map<String, String> _timeSlots = {};
  bool _profileSyncAttached = false;
  bool _profileSyncing = false;
  bool _profileSynced = false;
  String? _profileSyncError;
  String _profileBinding = '';
  int _profileGeneration = 0;
  int _profileRevision = 0;
  Future<void>? _profileRequest;

  OaGymService(
    this._auth,
    this._storage,
    this._tpAuth, {
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get _baseUrl => apiBaseUrl(_storage);

  bool get loading => _loading;
  bool get sessionReady => _sessionReady;
  Map<String, String> get venues => Map.unmodifiable(_venues);
  Map<String, String> get allVenues => Map.unmodifiable(_allVenues);
  Map<String, String> get timeSlots => Map.unmodifiable(_timeSlots);
  bool get profileSyncing => _profileSyncing;
  bool get profileSynced => _profileSynced;
  String? get profileSyncError => _profileSyncError;

  String get profileOwner {
    if (!_auth.isLoggedIn || !_tpAuth.hasCpdailyBinding) return '';
    final campusId = _tpAuth.cpdailyStudentId.isNotEmpty
        ? _tpAuth.cpdailyStudentId
        : _tpAuth.cpdailyBinding!.cpdailyUserId.isNotEmpty
            ? _tpAuth.cpdailyBinding!.cpdailyUserId
            : _tpAuth.cpdailyBinding!.account;
    return '${_auth.session!.userId}|$campusId';
  }

  String get bookingStudentId {
    if (profileOwner.isEmpty) return '';
    if (_tpAuth.cpdailyStudentId.isNotEmpty) return _tpAuth.cpdailyStudentId;
    // Legacy SMS bindings have a UUID and phone but no school ID. Only a
    // successful current-user OA response can supply their missing ID.
    return ThirdPartyAccount.cpdailySchoolId(
      _storage.loadOaBookingProfile(owner: profileOwner).studentId,
    );
  }

  String get _currentProfileBinding => profileOwner.isEmpty
      ? ''
      : '$profileOwner|${_tpAuth.cpdailyBinding!.boundAt.toIso8601String()}';

  /// Attach after boot hydration. Binding/rebinding starts a separate,
  /// best-effort read; login and court queries never wait for contact sync.
  void startProfileSync() {
    if (_profileSyncAttached) return;
    _profileSyncAttached = true;
    _auth.addListener(_onProfileBindingChanged);
    _tpAuth.addListener(_onProfileBindingChanged);
    _onProfileBindingChanged();
  }

  void _onProfileBindingChanged() {
    if (_prepareProfileBinding() && profileOwner.isNotEmpty) {
      unawaited(syncBookingProfile());
    }
  }

  bool _prepareProfileBinding() {
    final binding = _currentProfileBinding;
    if (_profileBinding == binding) return false;
    _profileBinding = binding;
    _profileGeneration++;
    _profileRequest = null;
    _profileSyncing = false;
    _profileSynced = false;
    _profileSyncError = null;
    notifyListeners();
    return true;
  }

  Future<void> syncBookingProfile({bool overwrite = false}) {
    _requireAuth();
    _prepareProfileBinding();
    final pending = _profileRequest;
    if (pending != null) return pending;
    late final Future<void> request;
    request = _loadBookingProfile(overwrite: overwrite).whenComplete(() {
      if (identical(_profileRequest, request)) _profileRequest = null;
    });
    _profileRequest = request;
    return request;
  }

  Future<void> _loadBookingProfile({required bool overwrite}) async {
    final owner = profileOwner;
    final generation = _profileGeneration;
    final revision = _profileRevision;
    _profileSyncing = true;
    _profileSyncError = null;
    notifyListeners();
    try {
      final response = await _postJson('oa/gym/profile', const {});
      if (generation != _profileGeneration || owner != profileOwner) return;
      final data = (response['data'] as Map?)?.cast<String, dynamic>();
      if (data == null) throw OaGymException('OA 个人信息响应不完整，请手动填写或重试');
      final studentId = ThirdPartyAccount.cpdailySchoolId(data['studentId']);
      if (studentId.isNotEmpty &&
          _tpAuth.cpdailyStudentId.isNotEmpty &&
          studentId != _tpAuth.cpdailyStudentId) {
        throw OaGymException('OA 资料与当前 eGate 账号不匹配，请重新绑定');
      }
      final incoming = OaBookingProfile.fromJson(data);
      if (revision != _profileRevision) return;
      final current = _storage.loadOaBookingProfile(owner: owner);
      final previous = _storage.loadOaSchoolProfile(owner: owner);
      // Never overwrite a contact edit saved while this request was running.
      String merge(String saved, String school, String oldSchool) =>
          school.isNotEmpty &&
                  (overwrite || saved.isEmpty || saved == oldSchool)
              ? school
              : saved;
      final phone = RegExp(r'^1[3-9]\d{9}$').hasMatch(incoming.phone)
          ? incoming.phone
          : '';
      final email =
          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(incoming.email)
              ? incoming.email
              : '';
      if (incoming.name.isEmpty && phone.isEmpty && email.isEmpty) {
        throw OaGymException('OA 暂未提供可同步的个人信息，请手动填写');
      }
      await _storage.saveOaBookingProfile(
        OaBookingProfile(
          name: merge(current.name, incoming.name, previous.name),
          phone: merge(current.phone, phone, previous.phone),
          email: merge(current.email, email, previous.email),
          studentId: studentId.isNotEmpty ? studentId : current.studentId,
        ),
        owner: owner,
        schoolProfile: OaBookingProfile(
          name: incoming.name.isNotEmpty ? incoming.name : previous.name,
          phone: phone.isNotEmpty ? phone : previous.phone,
          email: email.isNotEmpty ? email : previous.email,
          studentId: studentId.isNotEmpty ? studentId : previous.studentId,
        ),
      );
      if (generation == _profileGeneration && owner == profileOwner) {
        _profileSynced = true;
      }
    } catch (error) {
      if (generation == _profileGeneration && owner == profileOwner) {
        _profileSyncError =
            error is OaGymException ? error.message : '同步 OA 个人信息失败，可手动填写或稍后重试';
      }
    } finally {
      if (generation == _profileGeneration && owner == profileOwner) {
        _profileSyncing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_profileSyncAttached) {
      _auth.removeListener(_onProfileBindingChanged);
      _tpAuth.removeListener(_onProfileBindingChanged);
    }
    _profileGeneration++;
    super.dispose();
  }

  void clearSession() {
    _generation++;
    _oaCookies = '';
    _oaIdentity = '';
    _metadataRequest = null;
    _bulkSearchSupported = false;
    _sessionReady = false;
    _metadataReady = false;
    _venues = {};
    _allVenues = {};
    _timeSlots = {};
    notifyListeners();
  }

  OaBookingProfile bookingProfile() {
    if (profileOwner.isEmpty) {
      return const OaBookingProfile(name: '', phone: '', email: '');
    }
    final saved = _storage.loadOaBookingProfile(owner: profileOwner);
    // Contact sync enriches the bound school identity, never the Casdoor UUID.
    final cpdailyName = _tpAuth.cpdailyBinding?.name;
    return saved.copyWith(
      name: saved.name.isNotEmpty
          ? saved.name
          : (cpdailyName?.isNotEmpty == true ? cpdailyName! : ''),
      email: saved.email.isNotEmpty
          ? saved.email
          : (_tpAuth.cpdailyBinding?.email ?? ''),
    );
  }

  Future<void> saveBookingProfile(OaBookingProfile profile) async {
    _requireAuth();
    final owner = profileOwner;
    _profileRevision++;
    await _storage.saveOaBookingProfile(
      profile.copyWith(studentId: bookingStudentId),
      owner: owner,
    );
    notifyListeners();
  }

  Future<void> ensureReady() async {
    _syncIdentity();
    await _withLoading(() async {
      await _ensureMetadata();
      _sessionReady = true;
    });
  }

  Future<List<OaAvailability>> checkAvailability({
    required Set<OaSport> sports,
    required String date,
    required int startSlot,
    required int endSlot,
    void Function(List<OaAvailability>)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    _syncIdentity();
    _validateDates(date, date);
    if (sports.isEmpty ||
        startSlot < 1 ||
        endSlot > 11 ||
        startSlot > endSlot) {
      throw OaGymException('请选择运动项目和有效时间段');
    }
    final requested = Set<OaSport>.of(sports);
    final nativeSports = {
      for (final sport in requested)
        for (final court in oaCourtsForSport(sport)) court.bookingSport,
    };
    final previous = _availabilityTail;
    final done = Completer<void>();
    _availabilityTail = done.future;
    final generation = _generation;
    try {
      await previous;
      return await _withLoadingResult(() async {
        final result = <OaAvailability>[];
        // Bound each backend call to one hour. OA's tree picker is stateful,
        // so requests share one serial queue, including superseded UI checks.
        for (var slot = startSlot; slot <= endSlot; slot++) {
          if (generation != _generation || shouldContinue?.call() == false) {
            break;
          }
          final data = await _postJson('oa/gym/availability', {
            'sports': nativeSports.map((sport) => sport.id).toList(),
            'date': date,
            'startSlot': slot,
            'endSlot': slot,
          });
          final native = <OaSport, Set<int>>{};
          for (final item in data['data'] as List<dynamic>? ?? const []) {
            final row = (item as Map).cast<String, dynamic>();
            if (row['timeSlot'] != slot || row['date'] != date) {
              throw OaGymException('OA 返回的预约日期或时间段不匹配，请重试');
            }
            native[_sportFromId(row['sport'] as String)] =
                (row['availableCourts'] as List)
                    .cast<num>()
                    .map((n) => n.toInt())
                    .toSet();
          }
          if (!nativeSports.every(native.containsKey)) {
            throw OaGymException('OA 未返回完整场地状态，请刷新后重试');
          }
          for (final sport in requested) {
            final courts = oaCourtsForSport(sport);
            result.add(
              OaAvailability(
                sport: sport,
                date: date,
                timeSlot: slot,
                availableCourts: [
                  for (final court in courts)
                    if (native[court.bookingSport]!
                        .contains(court.bookingNumber))
                      court.number,
                ],
                totalCourts: courts.length,
              ),
            );
          }
          onProgress?.call(List.unmodifiable(result));
        }
        if (generation == _generation) _sessionReady = true;
        return result;
      });
    } finally {
      done.complete();
    }
  }

  Future<OaBookingResult> bookCourt({
    required OaSport sport,
    required String date,
    required int timeSlot,
    required int courtNumber,
    required int playersCount,
    bool Function()? shouldContinue,
  }) async {
    _syncIdentity();
    _validateDates(date, date);
    final choices =
        oaCourtsForSport(sport).where((court) => court.number == courtNumber);
    if (choices.isEmpty || timeSlot < 1 || timeSlot > 11 || playersCount < 1) {
      throw OaGymException('所选场地、时间段或预约人数无效');
    }
    final court = choices.single;
    _requireAuth();
    final profile = bookingProfile();
    final studentId = bookingStudentId;
    final userName = profile.name;
    final phone = profile.phone;
    if (userName.isEmpty || phone.isEmpty) {
      throw OaGymException('请先在「个人信息」里补全姓名和手机号');
    }
    if (studentId.isEmpty) {
      throw OaGymException('当前 eGate 绑定缺少学号，请重新绑定 eGate');
    }

    final data = await _withLoadingResult(
      () => _postJson(
        'oa/gym/book',
        {
          'booking': {
            'sport': court.bookingSport.id,
            'date': date,
            'timeSlot': timeSlot,
            'courtNumber': court.bookingNumber,
            'playersCount': playersCount,
            'studentId': studentId,
            'userName': userName,
            'phone': phone,
            'email': profile.email,
          },
        },
        shouldContinue: shouldContinue,
      ),
    );
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? data;
    _sessionReady = true;
    return OaBookingResult(
      success: payload['success'] == true,
      message: payload['message'] as String? ?? '提交完成',
    );
  }

  Future<List<OaCourtSearchResult>> searchCourts({
    required String startDate,
    required String endDate,
    required Set<String> venueNames,
    required List<String> timeRanges,
    void Function(List<OaCourtSearchResult>)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    _syncIdentity();
    _validateDates(startDate, endDate);
    await _withLoading(() async {
      await _ensureMetadata();
    });
    final venues = _resolveSearchVenues(venueNames);
    final ranges = timeRanges.isEmpty || timeRanges.contains('')
        ? <String>['']
        : timeRanges.toSet().toList();
    if (ranges
        .any((range) => range.isNotEmpty && !_timeSlots.containsKey(range))) {
      throw OaGymException('请选择有效时间段');
    }
    Future<List<OaCourtSearchResult>> query(
      List<String> names,
      List<String> times,
    ) async {
      final data = await _postJson('oa/gym/search', {
        'startDate': startDate,
        'endDate': endDate,
        'venueNames': names,
        'timeRanges': times,
      });
      final rows = data['data'] as List<dynamic>? ?? const [];
      final result = rows
          .map((item) {
            final json = (item as Map).cast<String, dynamic>();
            return OaCourtSearchResult(
              venue: json['venue'] as String? ?? '',
              timeRange: json['timeRange'] as String? ?? '',
              rows: (json['rows'] as List<dynamic>? ?? const [])
                  .map(
                    (row) => (row as List<dynamic>)
                        .map((value) => value?.toString() ?? '')
                        .toList(),
                  )
                  .toList(),
            );
          })
          .where((result) => !oaIsUnusedVenue(result.venue))
          .toList();
      final returned = {
        for (final row in result) '${row.venue}|${row.timeRange}',
      };
      if (names.any(
        (name) => times.any((time) => !returned.contains('$name|$time')),
      )) {
        throw OaGymException('部分场地查询失败，当前结果不完整，请重试');
      }
      return result;
    }

    return _withLoadingResult(() async {
      if (_bulkSearchSupported) {
        final result = await query(venues, ranges);
        onProgress?.call(result);
        return result;
      }
      // Compatibility with older deployments: never send their unbounded
      // venue × hour loop in one 30-second request. Three workers is enough.
      final jobs = [
        for (final venue in venues)
          for (var i = 0; i < ranges.length; i += 3)
            (venue, ranges.sublist(i, (i + 3).clamp(0, ranges.length))),
      ];
      final result = <OaCourtSearchResult>[];
      var next = 0;
      var failed = false;
      await Future.wait([
        for (var worker = 0; worker < 3 && worker < jobs.length; worker++)
          () async {
            while (next < jobs.length) {
              if (failed || shouldContinue?.call() == false) return;
              final job = jobs[next++];
              try {
                result.addAll(await query([job.$1], job.$2));
              } catch (_) {
                failed = true;
                rethrow;
              }
              onProgress?.call(List.unmodifiable(result));
            }
          }(),
      ]);
      _sessionReady = true;
      return result;
    });
  }

  Future<void> _ensureMetadata() async {
    if (_metadataReady) return;
    final pending = _metadataRequest;
    if (pending != null) return pending;
    final request = _loadMetadata();
    _metadataRequest = request;
    try {
      await request;
    } finally {
      if (identical(_metadataRequest, request)) _metadataRequest = null;
    }
  }

  Future<void> _loadMetadata() async {
    final generation = _generation;
    final data = await _postJson('oa/gym/metadata', const <String, dynamic>{});
    if (generation != _generation) throw OaGymException('账号已变更，请重新查询');
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? data;
    _venues = _stringMap(payload['venues'])
      ..removeWhere((name, id) => oaIsUnusedVenue(name) || id == '44');
    _allVenues = _stringMap(payload['allVenues'])
      ..removeWhere((name, id) => oaIsUnusedVenue(name) || id == '44');
    _timeSlots = _stringMap(payload['timeSlots']);
    _bulkSearchSupported =
        (data['capabilities'] as Map?)?['bulkSearch'] == true;
    if (_venues.isEmpty || _timeSlots.isEmpty) {
      throw OaGymException('加载 OA 场馆数据失败，请稍后重试');
    }
    _metadataReady = true;
    _sessionReady = true;
  }

  Future<void> _withLoading(Future<void> Function() task) async {
    await _withLoadingResult(task);
  }

  Future<T> _withLoadingResult<T>(Future<T> Function() task) async {
    _activeRequests++;
    _loading = _activeRequests > 0;
    notifyListeners();
    try {
      return await task();
    } finally {
      _activeRequests--;
      _loading = _activeRequests > 0;
      notifyListeners();
    }
  }

  /// Guard for any gym call: requires a logged-in primary account AND a
  /// bound cpdaily account (the source of the CpDaily/CASTGC session the OA
  /// system authenticates against).
  AuthService _requireAuth() {
    if (!_auth.isLoggedIn) {
      throw OaGymException('请先登录 TechPie 主账号');
    }
    if (!_tpAuth.hasCpdailyBinding) {
      throw OaGymException('场馆预约需要绑定 eGate 账号，请在「第三方账号」中绑定');
    }
    return _auth;
  }

  /// CpDaily auth payload built from a [CookieProvider] snapshot plus the
  /// cpdaily node's raw session fields (tgc/sessionToken/userId/tenantId). The
  /// cookie + epoch captured at request time drive the storm-safe renew-retry
  /// in [_postJson].
  Map<String, dynamic> _authPayload(CookieProvider cp) {
    final raw = _tpAuth.cpdailyNode.rawFields;
    return {
      'tgc': (raw['tgc'] as String?) ?? '',
      'cookies': cp.cookies,
      'sessionToken': (raw['sessionToken'] as String?) ?? '',
      'userId': (raw['userId'] as String?) ?? '',
      'tenantId': (raw['tenantId'] as String?) ?? '',
      if (_oaCookies.isNotEmpty) 'oaCookies': _oaCookies,
    };
  }

  /// POST `$_baseUrl/[path]` with CpDaily auth + [extra] body fields. On 401
  /// the cpdaily node is renewed exactly once (single-flighted across all
  /// concurrent callers) and the request retried with the fresh cookie.
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> extra, {
    bool Function()? shouldContinue,
  }) async {
    _requireAuth();
    final node = _tpAuth.cpdailyNode;
    var identity = _identity;
    final generation = _generation;
    final response = await _tpAuth.sessionTree.withCookie<http.Response>(
      node,
      (cp) async {
        if (shouldContinue?.call() == false) {
          throw OaGymException('请求已取消，请重新发起预约');
        }
        _syncIdentity();
        identity = _identity;
        final body = {...extra, 'auth': _authPayload(cp)};
        http.Response r;
        try {
          r = await _client
              .post(
                Uri.parse('$_baseUrl/$path'),
                headers: const {
                  'Content-Type': 'application/json; charset=UTF-8',
                },
                body: jsonEncode(body),
              )
              .timeout(const Duration(seconds: 30));
        } on TimeoutException {
          throw OaGymException(
            path.endsWith('/book')
                ? '预约提交超时，请先查询预约记录确认结果，避免重复提交'
                : '学校 OA 查询超时，请稍后重试或缩小日期范围',
          );
        } on http.ClientException {
          throw OaGymException('无法连接场馆服务，请检查网络后重试');
        }
        // A booking has no idempotency key. Even a 401 response must not
        // automatically replay a mutation; let the user confirm a new attempt.
        return CookieAction(
          r,
          expired: r.statusCode == 401 && !path.endsWith('/book'),
        );
      },
    );
    if (response == null) {
      throw OaGymException('当前 eGate 登录态已失效，请重新绑定 eGate');
    }
    if (response.statusCode == 401) {
      _sessionReady = false;
    }
    if (generation != _generation || identity != _identity) {
      throw OaGymException('账号或登录态已变更，请重新查询');
    }
    if (path == 'oa/gym/profile' && response.statusCode == 404) {
      throw OaGymException('当前后端暂不支持自动同步，请手动填写个人信息');
    }
    Map<String, dynamic> decoded;
    try {
      decoded = (jsonDecode(response.body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw OaGymException('场馆服务返回异常（HTTP ${response.statusCode}），请稍后重试');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] == false) {
      throw OaGymException(
        decoded['error'] as String? ?? 'OA 场馆服务请求失败，请稍后重试',
      );
    }
    final session = decoded['session'];
    if (session is Map && session['oaCookies'] is String) {
      _oaCookies = session['oaCookies'] as String;
    }
    return decoded;
  }

  String get _identity => '${_auth.session?.userId}|'
      '${_tpAuth.cpdailyBinding?.account}|${_tpAuth.cpdailyNode.epoch}|'
      '${_tpAuth.cpdailyNode.rawFields['tgc']}';

  void _syncIdentity() {
    _requireAuth();
    if (_oaIdentity == _identity) return;
    _oaIdentity = _identity;
    _oaCookies = '';
    // Metadata contains school-wide IDs. It can survive an automatic token
    // renewal, but an explicit logout/unbind calls clearSession.
  }

  void _validateDates(String start, String end) {
    for (final value in [start, end]) {
      final parsed = DateTime.tryParse(value);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != value) {
        throw OaGymException('日期格式应为有效的 YYYY-MM-DD');
      }
    }
    if (start.compareTo(end) > 0) throw OaGymException('开始日期不得晚于结束日期');
  }

  List<String> _resolveSearchVenues(Set<String> requested) {
    const groups = {'所有场地', '室内羽毛球场', '室内乒乓球场', '网球场', '匹克球场'};
    final concrete = _venues.keys.where((venue) => !groups.contains(venue));
    final resolved = <String>{};
    for (final venue in requested.isEmpty ? {'所有场地'} : requested) {
      if (venue == '所有场地') {
        resolved.addAll(concrete);
      } else if (groups.contains(venue)) {
        final sport = OaSport.values
            .firstWhere((sport) => oaSportConfigs[sport]!.parentName == venue);
        resolved
            .addAll(concrete.where((name) => oaVenueMatchesSport(name, sport)));
      } else if (_venues.containsKey(venue) && !oaIsUnusedVenue(venue)) {
        resolved.add(venue);
      } else {
        throw OaGymException('找不到有效场地：$venue');
      }
    }
    if (resolved.isEmpty) throw OaGymException('未找到可查询场地，请刷新数据后重试');
    return resolved.toList();
  }

  Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return {};
    return value.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }

  OaSport _sportFromId(String id) {
    for (final sport in OaSport.values) {
      if (sport.id == id) return sport;
    }
    throw OaGymException('未知运动类型: $id');
  }
}
