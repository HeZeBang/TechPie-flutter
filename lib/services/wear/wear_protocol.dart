import 'dart:convert';
import 'dart:typed_data';

class WearFailure implements Exception {
  const WearFailure(this.code, {this.retryable = false, this.nativeCode});
  final String code;
  final bool retryable;
  final int? nativeCode;
  @override
  String toString() => 'WearFailure($code)';
}

/// Byte-oriented framing: never splits a multi-byte UTF-8 character as text.
class WearFrames {
  static const maxBytes = 32768;
  static const chunkBytes = 512;
  final Map<String, _Assembly> _pending = {};

  static List<Uint8List> encode(Map<String, dynamic> message) {
    final id = message['id'];
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(id)) {
      throw const WearFailure('INVALID_PAYLOAD');
    }
    final bytes = utf8.encode(jsonEncode(message));
    if (bytes.length > maxBytes) throw const WearFailure('PAYLOAD_TOO_LARGE');
    final count = (bytes.length + chunkBytes - 1) ~/ chunkBytes;
    return List.generate(count, (i) {
      final end = (i + 1) * chunkBytes;
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'mid': id,
            'i': i,
            'n': count,
            'data': base64Encode(
              bytes.sublist(i * chunkBytes, end.clamp(0, bytes.length)),
            ),
          }),
        ),
      );
    });
  }

  Map<String, dynamic>? accept(Uint8List frame, DateTime now) {
    _pending
        .removeWhere((_, value) => now.difference(value.at).inSeconds >= 30);
    if (frame.length > 1024) throw const WearFailure('PAYLOAD_TOO_LARGE');
    try {
      final json = jsonDecode(utf8.decode(frame));
      if (json is! Map<String, dynamic> ||
          json['v'] != 1 ||
          json['mid'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(json['mid'] as String) ||
          json['i'] is! int ||
          json['n'] is! int ||
          json['data'] is! String) {
        throw const WearFailure('INVALID_PAYLOAD');
      }
      final id = json['mid'] as String;
      final index = json['i'] as int;
      final count = json['n'] as int;
      if (count < 1 || count > 64 || index < 0 || index >= count) {
        _pending.remove(id);
        throw const WearFailure('INVALID_PAYLOAD');
      }
      final data = base64Decode(json['data'] as String);
      if (data.isEmpty ||
          data.length > chunkBytes ||
          (index < count - 1 && data.length != chunkBytes)) {
        _pending.remove(id);
        throw const WearFailure('INVALID_PAYLOAD');
      }
      // One in-flight logical message per native peer; the transport selects one peer.
      if (_pending.isNotEmpty && !_pending.containsKey(id)) {
        throw const WearFailure('RATE_LIMITED', retryable: true);
      }
      final assembly = _pending.putIfAbsent(id, () => _Assembly(count, now));
      if (assembly.count != count ||
          (assembly.parts[index] != null &&
              base64Encode(assembly.parts[index]!) != base64Encode(data))) {
        _pending.remove(id);
        throw const WearFailure('INVALID_PAYLOAD');
      }
      assembly.parts[index] = data;
      assembly.at = now;
      if (assembly.parts.length != count) return null;
      _pending.remove(id);
      final bytes = BytesBuilder(copy: false);
      for (var i = 0; i < count; i++) {
        bytes.add(assembly.parts[i]!);
      }
      final message = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (message is! Map<String, dynamic> ||
          message['id'] != id ||
          message['v'] != 1 ||
          message['type'] is! String ||
          message['body'] is! Map ||
          message['sentAtMs'] is! int) {
        throw const WearFailure('INVALID_PAYLOAD');
      }
      return message;
    } on WearFailure {
      rethrow;
    } catch (_) {
      throw const WearFailure('INVALID_PAYLOAD');
    }
  }

  void clear() => _pending.clear();
}

class _Assembly {
  _Assembly(this.count, this.at);
  final int count;
  DateTime at;
  final Map<int, Uint8List> parts = {};
}

class WearAccount {
  const WearAccount({
    required this.scope,
    required this.name,
    required this.studentId,
  });

  /// Local opaque identity only. Never sent to the watch.
  final String scope;
  final String name;
  final String studentId;
  Map<String, dynamic> toJson() {
    if (scope.isEmpty ||
        name.trim().isEmpty ||
        studentId.trim().isEmpty ||
        name.runes.length > 64 ||
        studentId.runes.length > 64) {
      throw const WearFailure('ACCOUNT_NOT_READY');
    }
    return {'name': name, 'studentId': studentId};
  }
}

class WearDdl {
  const WearDdl({
    required this.id,
    required this.title,
    required this.courseName,
    required this.dueAt,
    required this.completed,
    this.remindAt = const [],
  });
  final String id;
  final String title;
  final String courseName;
  final DateTime dueAt;
  final bool completed;
  final List<DateTime> remindAt;
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'courseName': courseName,
        'dueAtMs': dueAt.millisecondsSinceEpoch,
        'status': completed ? 'completed' : 'open',
        'remindAtMs': completed
            ? <int>[]
            : remindAt.map((t) => t.millisecondsSinceEpoch).toList(),
      };
}

class WearCampusCode {
  WearCampusCode({
    required this.bytes,
    required this.issuedAt,
    required this.validUntil,
  });
  final Uint8List bytes;
  final DateTime issuedAt;
  final DateTime validUntil;
}

abstract interface class WearDataSource {
  Future<WearAccount> account();
  Future<List<WearDdl>> deadlines();
  Future<WearCampusCode> campusCode(String purpose);
}

abstract interface class WearTransport {
  Stream<Uint8List> get frames;
  Stream<Map<String, dynamic>> get states;
  Future<Map<String, dynamic>> status();
  Future<List<Map<String, dynamic>>> devices();
  Future<Map<String, dynamic>> authorize({required bool notify});
  Future<void> open(String deviceId, String fingerprint);
  Future<void> send(Uint8List bytes);
  Future<void> close();
  Future<void> scheduleReminders(Map<String, dynamic> spec);
  Future<void> cancelReminders();
  Future<String> sendReminder(String id);
  void dispose();
}

abstract interface class WearMetadata {
  String? read();
  Future<void> write(String value);
}
