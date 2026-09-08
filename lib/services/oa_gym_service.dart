import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/oa_gym.dart';
import 'api_base_url.dart';
import 'auth_service.dart';
import 'debug_logger.dart';
import 'http_client.dart';
import 'session/cookie_provider.dart';
import 'session/session_failure.dart';
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
  final LoggingHttpClient _client;
  int _generation = -1;

  bool _sessionReady = false;
  bool _metadataReady = false;
  bool _loading = false;
  Map<String, String> _venues = {};
  Map<String, String> _allVenues = {};
  Map<String, String> _timeSlots = {};

  OaGymService(
    this._auth,
    this._storage,
    this._tpAuth, {
    http.Client? client,
    DebugLogger? logger,
  }) : _client = LoggingHttpClient(logger ?? DebugLogger(), inner: client) {
    _tpAuth.addListener(_onBindingChanged);
  }

  void _onBindingChanged() {
    final generation = _tpAuth.cpdailyNode.generation;
    if (_generation == generation) return;
    _generation = generation;
    clearSession();
  }

  @override
  void dispose() {
    _tpAuth.removeListener(_onBindingChanged);
    _client.close();
    super.dispose();
  }

  String get _baseUrl => apiBaseUrl(_storage);

  bool get loading => _loading;
  bool get sessionReady => _sessionReady;
  Map<String, String> get venues => Map.unmodifiable(_venues);
  Map<String, String> get allVenues => Map.unmodifiable(_allVenues);
  Map<String, String> get timeSlots => Map.unmodifiable(_timeSlots);

  void clearSession() {
    _sessionReady = false;
    _metadataReady = false;
    _venues = {};
    _allVenues = {};
    _timeSlots = {};
    notifyListeners();
  }

  OaBookingProfile bookingProfile() {
    final saved = _storage.loadOaBookingProfile();
    // Fall back to the cpdaily binding's real name (not the primary SSO
    // account, whose userName is a Casdoor UUID). Phone is not available
    // from cpdaily, so the user must still fill it in manually.
    final cpdailyName = _tpAuth.cpdailyBinding?.name;
    return saved.copyWith(
      name: saved.name.isNotEmpty
          ? saved.name
          : (cpdailyName?.isNotEmpty == true ? cpdailyName! : ''),
      phone: saved.phone.isNotEmpty ? saved.phone : '',
    );
  }

  Future<void> saveBookingProfile(OaBookingProfile profile) async {
    await _storage.saveOaBookingProfile(profile);
    notifyListeners();
  }

  Future<void> ensureReady() async {
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
  }) async {
    final data = await _withLoadingResult(
      () => _postJson(
        'oa/gym/availability',
        {
          'sports': sports.map((sport) => sport.id).toList(),
          'date': date,
          'startSlot': startSlot,
          'endSlot': endSlot,
        },
      ),
    );
    final rows = data['data'] as List<dynamic>? ?? const [];
    _sessionReady = true;
    return rows.map((item) {
      final json = (item as Map).cast<String, dynamic>();
      final sport = _sportFromId(json['sport'] as String? ?? '');
      return OaAvailability(
        sport: sport,
        date: json['date'] as String? ?? date,
        timeSlot: (json['timeSlot'] as num?)?.toInt() ?? 0,
        availableCourts: (json['availableCourts'] as List<dynamic>? ?? const [])
            .map((value) => (value as num).toInt())
            .toList(),
        totalCourts: (json['totalCourts'] as num?)?.toInt() ??
            oaSportConfigs[sport]!.courtCount,
      );
    }).toList();
  }

  Future<OaBookingResult> bookCourt({
    required OaSport sport,
    required String date,
    required int timeSlot,
    required int courtNumber,
    required int playersCount,
  }) async {
    final auth = _requireAuth();
    final profile = bookingProfile();
    final studentId = _tpAuth.cpdailyStudentId;
    final userName =
        profile.name.isNotEmpty ? profile.name : (auth.session?.userName ?? '');
    final phone = profile.phone.isNotEmpty
        ? profile.phone
        : (auth.session?.phoneNumber ?? '');
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
            'sport': sport.id,
            'date': date,
            'timeSlot': timeSlot,
            'courtNumber': courtNumber,
            'playersCount': playersCount,
            'studentId': studentId,
            'userName': userName,
            'phone': phone,
            'email': profile.email,
          },
        },
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
  }) async {
    await _withLoading(() async {
      await _ensureMetadata();
    });
    final data = await _withLoadingResult(
      () => _postJson(
        'oa/gym/search',
        {
          'startDate': startDate,
          'endDate': endDate,
          'venueNames': venueNames.toList(),
          'timeRanges': timeRanges,
        },
      ),
    );
    final rows = data['data'] as List<dynamic>? ?? const [];
    _sessionReady = true;
    return rows.map((item) {
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
    }).toList();
  }

  Future<void> _ensureMetadata() async {
    if (_metadataReady) return;
    final data = await _postJson('oa/gym/metadata', const <String, dynamic>{});
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? data;
    _venues = _stringMap(payload['venues']);
    _allVenues = _stringMap(payload['allVenues']);
    _timeSlots = _stringMap(payload['timeSlots']);
    if (_venues.isEmpty || _timeSlots.isEmpty) {
      throw OaGymException('加载 OA 场馆数据失败，请稍后重试');
    }
    _metadataReady = true;
    _sessionReady = true;
  }

  Future<void> _withLoading(Future<void> Function() task) async {
    _loading = true;
    notifyListeners();
    try {
      await task();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<T> _withLoadingResult<T>(Future<T> Function() task) async {
    _loading = true;
    notifyListeners();
    try {
      return await task();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Guard for any gym call: requires a logged-in primary account AND a
  /// bound cpdaily account (the source of the CpDaily/CASTGC session the OA
  /// system authenticates against). Returns the AuthService so callers can
  /// also read identity fields (name/phone) from the primary session.
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
      'userId': (raw['userId'] as String?) ?? cp.studentId,
      'tenantId': (raw['tenantId'] as String?) ?? '',
    };
  }

  /// POST `$_baseUrl/[path]` with CpDaily auth + [extra] body fields. On 401
  /// the cpdaily node is renewed exactly once (single-flighted across all
  /// concurrent callers) and the request retried with the fresh cookie.
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> extra,
  ) async {
    _requireAuth();
    final node = _tpAuth.cpdailyNode;
    final generation = node.generation;
    final submitting = path == 'oa/gym/book';
    Future<CookieAction<http.Response>> send(CookieProvider cp) async {
      final response = await _client.post(
        Uri.parse('$_baseUrl/$path'),
        headers: const {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({...extra, 'auth': _authPayload(cp)}),
        tag: path,
      );
      return CookieAction(response, expired: response.statusCode == 401);
    }

    try {
      // Submission is sent once. A timeout cannot tell whether OA accepted it.
      final http.Response? response;
      if (submitting) {
        final cp = node.cookieProvider;
        if (cp == null) throw SessionFailure.fromStatus(401);
        response = (await send(cp)).value;
      } else {
        response =
            await _tpAuth.sessionTree.withCookie<http.Response>(node, send);
      }
      if (generation != node.generation) throw SessionFailure.changed;
      if (response == null) {
        throw node.lastFailure ?? SessionFailure.unavailable;
      }
      if (response.statusCode != 200) {
        throw SessionFailure.fromStatus(response.statusCode);
      }
      final decoded =
          (jsonDecode(response.body) as Map).cast<String, dynamic>();
      if (decoded['success'] != true) throw SessionFailure.unavailable;
      node.lastFailure = null;
      return decoded;
    } catch (error) {
      final failure =
          error is SessionFailure ? error : SessionFailure.unavailable;
      if (generation == node.generation) {
        node.lastFailure = failure;
        if (failure.needsLogin) _sessionReady = false;
      }
      throw OaGymException(
        submitting && !failure.needsLogin
            ? '未能确认预约结果，请先在 OA 查看预约记录，确认后再提交'
            : failure.message,
      );
    }
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
