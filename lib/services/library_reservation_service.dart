import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'session/cookie_provider.dart';
import 'session/session_tree.dart';
import 'third_party_auth_service.dart';

const _libraryHost = 'libspace.shanghaitech.edu.cn';
const _idsHost = 'ids.shanghaitech.edu.cn';
const _basePath = '/spaceReservationApp/api';

enum LibrarySpaceType {
  discussion('讨论室', 'DISCUSSION_ROOM'),
  study('个人研习室', 'STUDY_ROOM'),
  silent('静音舱', 'SILENT_BOOTH');

  const LibrarySpaceType(this.label, this.apiValue);
  final String label;
  final String apiValue;
}

enum LibrarySlotStatus { available, occupied, closed }

@immutable
class LibraryAvailability {
  const LibraryAvailability({
    required this.rooms,
    required this.cycleDays,
    required this.openStart,
    required this.openEnd,
    required this.stepMinutes,
    required this.minMinutes,
    required this.maxMinutes,
  });

  final List<LibraryRoom> rooms;
  final int cycleDays;
  final int openStart;
  final int openEnd;
  final int stepMinutes;
  final int minMinutes;
  final int maxMinutes;

  LibrarySlotStatus statusAt(LibraryRoom room, int start) {
    if (room.disabled || start < openStart || start + stepMinutes > openEnd) {
      return LibrarySlotStatus.closed;
    }
    return room.slots[start] ?? LibrarySlotStatus.closed;
  }

  int latestEnd(LibraryRoom room, int start) {
    final limit = start + maxMinutes;
    var end = start;
    while (end + stepMinutes <= limit &&
        statusAt(room, end) == LibrarySlotStatus.available) {
      end += stepMinutes;
    }
    return end;
  }

  Iterable<int> startTimes(LibraryRoom room) sync* {
    if (room.disabled) return;
    for (var start = openStart;
        start + minMinutes <= openEnd;
        start += stepMinutes) {
      final requiredEnd = start + minMinutes;
      var end = start;
      while (end < requiredEnd &&
          end + stepMinutes <= start + maxMinutes &&
          statusAt(room, end) == LibrarySlotStatus.available) {
        end += stepMinutes;
      }
      if (end >= requiredEnd) yield start;
    }
  }
}

@immutable
class LibraryRoom {
  const LibraryRoom({
    required this.id,
    required this.name,
    required this.capacity,
    required this.disabled,
    required this.slots,
  });

  final String id;
  final String name;
  final int? capacity;
  final bool disabled;
  final Map<int, LibrarySlotStatus> slots;
}

@immutable
class LibraryParticipant {
  const LibraryParticipant({required this.name, required this.number});
  final String name;
  final String number;
}

@immutable
class LibraryReservationRecord {
  const LibraryReservationRecord._({
    required this.id,
    required this.name,
    required this.typeLabel,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.statusLabel,
    required String status,
  }) : _status = status;

  final String id;
  final String name;
  final String typeLabel;
  final String date;
  final String startTime;
  final String endTime;
  final String statusLabel;
  final String _status;

  bool get canCancel => _status == 'WAIT_SIGN' || _status == 'INIT';
}

class LibraryReservationException implements Exception {
  const LibraryReservationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LibraryReservationService {
  LibraryReservationService(this._auth, {http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _owner = _auth.campusWebSession.owner;

  final ThirdPartyAuthService _auth;
  final http.Client _client;
  final bool _ownsClient;
  final String _owner;
  String? _token;
  Future<String>? _handshake;

  static DateTime get campusNow => DateTime.now().toUtc().add(const Duration(hours: 8));

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<LibraryAvailability> load(
    LibrarySpaceType type,
    DateTime date, {
    DateTime? through,
  }) async {
    final config = _mapData(
      await _safeGet('/spaces/space-config', {'spaceType': type.apiValue}),
    );
    final openStart = _timeField(config['openStartTime']);
    final openEnd = _timeField(config['openEndTime']);
    final minMinutes = _hours(config['minDurationHours'], '最短预约时长');
    final maxMinutes = _hours(config['maxDurationHours'], '最长预约时长');
    final step =
        config['stepMinutes'] == null ? minMinutes : _integer(config['stepMinutes'], '预约步长');
    final cycleDays = _integer(config['cycleDays'], '可预约天数');
    if (cycleDays < 1 || step < 1 || openEnd - openStart < step || maxMinutes < minMinutes) {
      throw const LibraryReservationException('图书馆返回了无效的预约规则');
    }
    if (through != null &&
        (through.isBefore(date) || through.difference(date).inDays >= cycleDays)) {
      throw const LibraryReservationException('结束日期超出可预约范围');
    }
    final dates = await Future.wait([
      _roomsFor(type, date),
      if (through != null)
        for (var day = date.add(const Duration(days: 1));
            !day.isAfter(through);
            day = day.add(const Duration(days: 1)))
          _roomsFor(type, day),
    ]);
    final later = [
      for (final rooms in dates.skip(1)) {for (final room in rooms) room.id: room},
    ];
    return LibraryAvailability(
      rooms: List.unmodifiable(
        later.isEmpty
            ? dates.first
            : dates.first.map((room) {
                final matches = [for (final rooms in later) rooms[room.id]];
                return LibraryRoom(
                  id: room.id,
                  name: room.name,
                  capacity: room.capacity,
                  disabled: room.disabled || matches.any((match) => match?.disabled ?? true),
                  slots: Map.unmodifiable({
                    for (final slot in room.slots.entries)
                      slot.key: matches.fold(
                        slot.value,
                        (status, match) => _combinedStatus(status, match?.slots[slot.key]),
                      ),
                  }),
                );
              }),
      ),
      cycleDays: cycleDays,
      openStart: openStart,
      openEnd: openEnd,
      stepMinutes: step,
      minMinutes: minMinutes,
      maxMinutes: maxMinutes,
    );
  }

  static LibrarySlotStatus _combinedStatus(LibrarySlotStatus a, LibrarySlotStatus? b) {
    if (a == LibrarySlotStatus.closed || b == null || b == LibrarySlotStatus.closed) {
      return LibrarySlotStatus.closed;
    }
    return a == LibrarySlotStatus.occupied || b == LibrarySlotStatus.occupied
        ? LibrarySlotStatus.occupied
        : LibrarySlotStatus.available;
  }

  Future<List<LibraryRoom>> _roomsFor(LibrarySpaceType type, DateTime date) async {
    final dateText = _date(date);
    final rooms = <LibraryRoom>[];
    var page = 1;
    var total = 0;
    do {
      final data = _mapData(
        await _safeGet('/spaces', {
          'date': dateText,
          'type': type.apiValue,
          'pageNo': '$page',
          'pageSize': '100',
        }),
      );
      final list = data['list'];
      total = _integer(data['total'], '房间总数');
      if (list is! List) throw const LibraryReservationException('图书馆返回了无效的房间列表');
      if (list.isEmpty && rooms.length < total) {
        throw const LibraryReservationException('图书馆返回的房间列表不完整');
      }
      for (final room in list) {
        if (room is! Map<String, dynamic>) {
          throw const LibraryReservationException('图书馆返回了无效的房间信息');
        }
        if (room['scheduleDate'] != dateText) {
          throw const LibraryReservationException('图书馆返回了错误日期的房间信息');
        }
        final id = room['id']?.toString() ?? '';
        final name = room['spaceName'];
        final slots = room['slots'];
        if (id.isEmpty || name is! String || slots is! List) {
          throw const LibraryReservationException('图书馆返回了无效的房间信息');
        }
        final statusByTime = <int, LibrarySlotStatus>{};
        for (final slot in slots) {
          if (slot is! Map<String, dynamic>) {
            throw const LibraryReservationException('图书馆返回了无效的时段信息');
          }
          final status = slot['statusCode'];
          final time = slot['time'];
          if (status is! String || time is! String) {
            throw const LibraryReservationException('图书馆返回了无效的时段信息');
          }
          statusByTime[_time(time)] = switch (status) {
            'AVAILABLE' => LibrarySlotStatus.available,
            'OCCUPIED' => LibrarySlotStatus.occupied,
            _ => LibrarySlotStatus.closed,
          };
        }
        rooms.add(
          LibraryRoom(
            id: id,
            name: name,
            capacity: room['capacity'] is int ? room['capacity'] as int : null,
            disabled: room['disabled'] == true,
            slots: Map.unmodifiable(statusByTime),
          ),
        );
      }
      page++;
    } while (rooms.length < total);

    return rooms;
  }

  Future<({Map<String, String> types, Map<String, String> topics})> discussionOptions() async {
    final results = await Future.wait([
      _safeGet('/dicts/meeting_type'),
      _safeGet('/dicts/meeting_topic'),
    ]);
    return (types: _options(results[0]), topics: _options(results[1]));
  }

  Future<List<LibraryParticipant>> findParticipants(String query) async {
    final data = _data(
      await _safeGet('/reservations/queryUsers', {'nameKeyWords': query}),
    );
    if (data is! List) throw const LibraryReservationException('图书馆返回了无效的用户列表');
    return List.unmodifiable(
      data.map((value) {
        if (value case {'userName': final String name, 'userNo': final String number}) {
          return LibraryParticipant(name: name, number: number);
        }
        throw const LibraryReservationException('图书馆返回了无效的用户信息');
      }),
    );
  }

  Future<({List<LibraryReservationRecord> records, bool hasMore})> listReservations({
    required bool history,
    required int page,
  }) async {
    if (page < 1) throw const LibraryReservationException('预约页码无效');
    const pageSize = 10;
    final data = _mapData(
      await _safeRead(
        'POST',
        '/my/reservations/list',
        body: {
          'tab': history ? 'history' : 'current',
          'pageNo': page,
          'pageSize': pageSize,
        },
      ),
    );
    final list = data['list'];
    final total = _integer(data['total'], '预约总数');
    if (list is! List || total < 0) {
      throw const LibraryReservationException('图书馆返回了无效的预约列表');
    }
    final records = list.map((value) {
      if (value is! Map) {
        throw const LibraryReservationException('图书馆返回了无效的预约信息');
      }
      final id = value['reservationId']?.toString();
      final name = value['spaceName'];
      final type = value['typeName'];
      final date = value['reserveDate'];
      final start = value['startTime'];
      final end = value['endTime'];
      final status = value['reservationStatus'];
      final statusLabel = value['reservationStatusStr'];
      if (id == null ||
          !RegExp(r'^\d+$').hasMatch(id) ||
          name is! String ||
          type is! String ||
          date is! String ||
          start is! String ||
          end is! String ||
          status is! String ||
          statusLabel is! String) {
        throw const LibraryReservationException('图书馆返回了无效的预约信息');
      }
      return LibraryReservationRecord._(
        id: id,
        name: name,
        typeLabel: type,
        date: date,
        startTime: start,
        endTime: end,
        statusLabel: statusLabel,
        status: status,
      );
    });
    return (
      records: List<LibraryReservationRecord>.unmodifiable(records),
      hasMore: page * pageSize < total,
    );
  }

  Future<void> cancelReservation(LibraryReservationRecord record) async {
    if (!record.canCancel || !RegExp(r'^\d+$').hasMatch(record.id)) {
      throw const LibraryReservationException('该预约无法取消');
    }
    await _write(
      http.Request('POST', _uri('/my/reservations/${record.id}/cancel')),
      unknownMessage: '取消结果未知，请刷新“我的预约”确认',
      expiredMessage: '登录已过期，请刷新预约记录后重试',
    );
  }

  Future<void> book({
    required LibrarySpaceType type,
    required LibraryRoom room,
    required List<DateTime> dates,
    required int start,
    required int end,
    required bool continuous,
    String meetingType = '',
    String topic = '',
    List<LibraryParticipant> participants = const [],
  }) async {
    await _write(
      http.Request('POST', _uri('/reservations'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'spaceId': room.id,
          'spaceType': type.apiValue,
          'dates': dates.map(_date).toList(),
          'continuous': continuous,
          'startTime': _formatTime(start),
          'endTime': _formatTime(end),
          'meetingType': meetingType,
          'title': topic,
          'inviterList':
              participants.map((p) => {'inviterName': p.name, 'inviterNo': p.number}).toList(),
        }),
      unknownMessage: '预约结果未知，请先检查“我的预约”后再重试',
      expiredMessage: '登录已过期，请重试预约',
    );
  }

  Future<void> _write(
    http.Request request, {
    required String unknownMessage,
    required String expiredMessage,
  }) async {
    _guard();
    final token = await _accessToken();
    _guard();
    request.headers['token'] = token;
    http.Response response;
    try {
      response = await _send(request);
    } catch (_) {
      throw LibraryReservationException(unknownMessage);
    }
    _guard();
    if (response.statusCode >= 500 || (response.statusCode >= 300 && response.statusCode < 400)) {
      throw LibraryReservationException(unknownMessage);
    }
    if (response.statusCode == 401) {
      if (_token == token) _token = null;
      throw LibraryReservationException(expiredMessage);
    }
    final Map<String, dynamic> json;
    try {
      json = _json(response);
    } on LibraryReservationException {
      throw LibraryReservationException(unknownMessage);
    }
    if (json['code'] == 40101) {
      if (_token == token) _token = null;
      throw LibraryReservationException(expiredMessage);
    }
    if (response.statusCode >= 400 || json['code'] != 0) {
      throw LibraryReservationException(_message(json));
    }
  }

  Future<Map<String, dynamic>> _safeGet(String path, [Map<String, String>? query]) =>
      _safeRead('GET', path, query: query);

  Future<Map<String, dynamic>> _safeRead(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      _guard();
      final token = await _accessToken();
      _guard();
      final request = http.Request(method, _uri(path, query))..headers['token'] = token;
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await _send(request);
      _guard();
      if (response.statusCode == 401) {
        if (_token == token) _token = null;
        continue;
      }
      final json = _json(response);
      if (json['code'] == 40101) {
        if (_token == token) _token = null;
        continue;
      }
      if (response.statusCode != 200 || json['code'] != 0) {
        throw LibraryReservationException(_message(json));
      }
      return json;
    }
    throw const LibraryReservationException('图书馆登录已过期，请稍后重试');
  }

  Future<String> _accessToken() async {
    _guard();
    if (_token case final token?) return token;
    final pending = _handshake ??= _login();
    try {
      final token = await pending;
      _guard();
      return _token = token;
    } finally {
      if (identical(_handshake, pending)) _handshake = null;
    }
  }

  Future<String> _login() async {
    final result = await _auth.sessionTree.withCookie<String>(
      _auth.cpdailyNode,
      (provider) async {
        final token = await _loginWith(provider);
        return CookieAction(token ?? '', expired: token == null);
      },
    );
    _guard();
    if (result == null || result.isEmpty) {
      throw const LibraryReservationException('统一身份认证失败，请重新绑定校园账号');
    }
    return result;
  }

  Future<String?> _loginWith(CookieProvider provider) async {
    final castgc = _lastCookie(provider.cookies, 'CASTGC');
    if (castgc == null) return null;
    final cookies = <String, Map<String, String>>{};
    Uri next = _uri('/login');
    String? state;
    for (var redirects = 0; redirects < 8; redirects++) {
      _guard();
      final request = http.Request('GET', next);
      final scoped = cookies[next.host];
      if (scoped != null && scoped.isNotEmpty) {
        request.headers['Cookie'] = scoped.entries.map((e) => '${e.key}=${e.value}').join('; ');
      }
      if (next.host == _idsHost) {
        request.headers['Cookie'] = [
          if (request.headers['Cookie'] case final existing?) existing,
          'CASTGC=$castgc',
        ].join('; ');
      }
      final response = await _send(request);
      _guard();
      _storeCookies(cookies, next.host, response.headers['set-cookie']);
      if (response.statusCode < 300 || response.statusCode >= 400) return null;
      final location = response.headers['location'];
      if (location == null) return null;
      final target = next.resolve(location);
      if (target.scheme != 'https' ||
          target.port != 443 ||
          target.userInfo.isNotEmpty ||
          !_allowedRedirect(target)) {
        return null;
      }
      if (state == null && target.host == _idsHost) {
        state = target.queryParameters['state'];
      }
      if (target.host == _libraryHost) {
        if (state == null || state.isEmpty || target.queryParameters['state'] != state) {
          return null;
        }
        final code = target.queryParameters['code'];
        if (code == null || code.isEmpty) return null;
        final callbackRequest = http.Request(
          'GET',
          _uri('/callBack', {'code': code, 'state': state}),
        );
        final libraryCookies = cookies[_libraryHost];
        if (libraryCookies != null && libraryCookies.isNotEmpty) {
          callbackRequest.headers['Cookie'] =
              libraryCookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
        }
        final callback = await _send(callbackRequest);
        final json = _json(callback);
        if (callback.statusCode != 200 || json['code'] != 0) return null;
        final data = json['data'];
        final token = (data is Map ? data['access_token'] : null) ?? json['token'];
        return token is String && token.isNotEmpty ? token : null;
      }
      next = target;
    }
    return null;
  }

  bool _allowedRedirect(Uri uri) => switch (uri.host) {
        _idsHost => const {
            '/authserver/oauth2.0/authorize',
            '/authserver/oauth2.0/callbackAuthorize',
            '/authserver/login',
          }.contains(uri.path),
        _libraryHost => uri.path == '/login',
        _ => false,
      };

  Future<http.Response> _send(http.Request request) async {
    request.followRedirects = false;
    try {
      return await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const LibraryReservationException('图书馆请求超时，请稍后重试');
    } on http.ClientException {
      throw const LibraryReservationException('无法连接图书馆，请检查网络后重试');
    }
  }

  void _guard() {
    if (_auth.campusWebSession.owner != _owner) {
      _token = null;
      throw const LibraryReservationException('账号已切换，请重新打开图书馆预约');
    }
    if (!_auth.hasCpdailyBinding) {
      throw const LibraryReservationException('请先在「第三方账号」中绑定校园账号');
    }
  }

  static Uri _uri(String path, [Map<String, String>? query]) => Uri.https(
        _libraryHost,
        '$_basePath$path',
        query,
      );

  static Map<String, dynamic> _json(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map<String, dynamic>) return value;
    } catch (_) {}
    throw const LibraryReservationException('图书馆返回了无法识别的响应');
  }

  static dynamic _data(Map<String, dynamic> json) => json['data'];
  static Map<String, dynamic> _mapData(Map<String, dynamic> json) {
    final data = _data(json);
    if (data is! Map) throw const LibraryReservationException('图书馆返回了无效的数据');
    return Map<String, dynamic>.from(data);
  }

  static Map<String, String> _options(Map<String, dynamic> json) {
    final data = _data(json);
    if (data is! List) throw const LibraryReservationException('图书馆返回了无效的选项');
    final result = <String, String>{};
    for (final value in data) {
      if (value case {'code': final String code, 'name': final String name}) {
        if (value['enabled'] != false) result[code] = name;
      } else {
        throw const LibraryReservationException('图书馆返回了无效的选项');
      }
    }
    return Map.unmodifiable(result);
  }

  static int _integer(dynamic value, String name) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    throw LibraryReservationException('图书馆返回了无效的$name');
  }

  static int _hours(dynamic value, String name) {
    if (value is! num || value <= 0) throw LibraryReservationException('图书馆返回了无效的$name');
    return (value * 60).round();
  }

  static int _timeField(dynamic value) {
    if (value is! String) throw const LibraryReservationException('图书馆返回了无效的开放时间');
    return _time(value);
  }

  static int _time(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) throw const LibraryReservationException('图书馆返回了无效的时段');
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 24 || minute > 59 || (hour == 24 && minute != 0)) {
      throw const LibraryReservationException('图书馆返回了无效的时段');
    }
    return hour * 60 + minute;
  }

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  static String _formatTime(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  static String _message(Map<String, dynamic> json) {
    final message = json['msg'] ?? json['message'];
    return message is String && message.isNotEmpty ? message : '图书馆请求失败，请稍后重试';
  }

  static String? _lastCookie(String header, String name) {
    String? result;
    for (final part in header.split(';')) {
      final separator = part.indexOf('=');
      if (separator > 0 && part.substring(0, separator).trim() == name) {
        final value = part.substring(separator + 1).trim();
        if (value.isNotEmpty) result = value;
      }
    }
    return result;
  }

  static void _storeCookies(
    Map<String, Map<String, String>> jar,
    String host,
    String? header,
  ) {
    if (header == null) return;
    for (final cookie in header.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
      final first = cookie.split(';').first;
      final separator = first.indexOf('=');
      if (separator <= 0) continue;
      jar.putIfAbsent(host, () => {})[first.substring(0, separator).trim()] =
          first.substring(separator + 1).trim();
    }
  }
}
