import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/course_table.dart';
import 'storage_service.dart';

String liveScheduleFingerprint(CourseTable table) {
  final courses = table.courses.map((course) {
    final days = course.times.keys.toList()..sort();
    return jsonEncode([
      course.name,
      course.classroom,
      course.weeks,
      for (final day in days)
        [
          day,
          [...course.times[day]!]..sort(),
        ],
    ]);
  }).toList()
    ..sort();
  return sha256.convert(utf8.encode(jsonEncode(courses))).toString();
}

String normalizeLiveClassroom(String name) => name
    .trim()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAllMapped(RegExp(r'([A-Za-z])-(?=\d)'), (m) => m[1]!)
    .toUpperCase();

/// Account, backend and semester scoped. Unknown rooms are negative cache entries.
class LiveClassroomCache {
  LiveClassroomCache(this.storage, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final StorageService storage;
  final DateTime Function() _now;
  static const lifetime = Duration(hours: 6);
  static const cooldown = Duration(minutes: 1);
  static final Map<String, Future<void>> _pending = {};

  Future<int?> resolve({
    required String scope,
    required String fingerprint,
    required String classroom,
    required Future<Map<String, Object>> Function() fetch,
  }) async {
    final key = sha256.convert(utf8.encode(scope)).toString();
    final name = normalizeLiveClassroom(classroom);
    var entry = storage.loadLiveClassrooms(key);
    final now = _now().millisecondsSinceEpoch;
    final fetchedAt = entry?['fetchedAt'] as int? ?? 0;
    final age = now - fetchedAt;
    final sameSchedule = entry?['fingerprint'] == fingerprint;
    var rooms = _rooms(entry);
    final fresh = fetchedAt > 0 && age >= 0 && age < lifetime.inMilliseconds;
    final missing = !rooms.containsKey(name);
    final refresh = !fresh || !sameSchedule || (missing && age >= cooldown.inMilliseconds);
    if (refresh) {
      final pending = _pending[key];
      if (pending != null) {
        await pending;
      } else {
        final attemptedAt = entry?['attemptedAt'] as int? ?? 0;
        if (now - attemptedAt < cooldown.inMilliseconds) {
          throw StateError('直播教室信息暂不可用，请稍后重试');
        }
        final future = () async {
          await storage.saveLiveClassrooms(key, {...?entry, 'attemptedAt': now});
          final result = await fetch();
          final normalized = <String, Object>{};
          for (final item in result.entries) {
            final normalizedName = normalizeLiveClassroom(item.key);
            final prior = normalized[normalizedName];
            normalized[normalizedName] =
                prior != null && prior != item.value ? 'unknown' : item.value;
          }
          await storage.saveLiveClassrooms(key, {
            'fingerprint': fingerprint,
            'fetchedAt': _now().millisecondsSinceEpoch,
            'attemptedAt': now,
            'classrooms': normalized,
          });
        }();
        _pending[key] = future;
        try {
          await future;
        } finally {
          if (identical(_pending[key], future)) {
            final removed = _pending.remove(key);
            assert(identical(removed, future));
          }
        }
      }
      entry = storage.loadLiveClassrooms(key);
      if (entry?['fingerprint'] != fingerprint) {
        throw StateError('课表已更新，请稍后重新进入直播');
      }
      rooms = _rooms(entry);
    }
    if (!rooms.containsKey(name)) {
      // A successful complete response omitted this name. Remember that result.
      rooms[name] = 'unknown';
      await storage.saveLiveClassrooms(key, {...?entry, 'classrooms': rooms});
    }
    final id = rooms[name];
    return id is int ? id : null;
  }

  Map<String, Object> _rooms(Map<String, dynamic>? entry) {
    final raw = entry?['classrooms'];
    if (raw is! Map) return {};
    return {
      for (final item in raw.entries)
        if (item.key is String &&
            (item.value == 'unknown' || item.value is int && (item.value as int) > 0))
          item.key as String: item.value as Object,
    };
  }
}
