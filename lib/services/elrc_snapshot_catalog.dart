import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/elrc_course.dart';
import '../models/elrc_recording.dart';

const elrcRecordingCatalogAsset = 'assets/config/elrc_recordings.json';

/// Course and media metadata exported from the user's ELRC browser session.
/// The export contains no school login credentials or browser cookies.
class ElrcCourseSnapshot {
  ElrcCourseSnapshot(this.course, this.outline, this.playbacks, this.capturedAt);
  final ElrcCourse course;
  final ElrcRecordingOutline outline;
  final Map<String, ElrcRecordingSources> playbacks;
  final DateTime capturedAt;
}

class ElrcSnapshotCatalog {
  factory ElrcSnapshotCatalog({Future<String> Function()? load}) =>
      load == null ? _shared : ElrcSnapshotCatalog._(load);

  ElrcSnapshotCatalog._(this._load);
  static final _shared = ElrcSnapshotCatalog._(
    () => rootBundle.loadString(elrcRecordingCatalogAsset),
  );

  final Future<String> Function() _load;
  Future<Map<String, ElrcCourseSnapshot>>? _pending;

  Future<ElrcCourseSnapshot?> find(ElrcCourse course) async {
    final records = await (_pending ??= _read());
    final record = records[course.key];
    // A reused course ID must not silently select another class or term.
    if (record != null &&
        (record.course.courseNo != course.courseNo ||
            record.course.term != course.term ||
            record.course.classNo != course.classNo)) {
      throw const FormatException('录播清单与开课记录不一致。');
    }
    return record;
  }

  Future<Map<String, ElrcCourseSnapshot>> _read() async {
    try {
      return await compute(parseElrcSnapshots, await Future<String>.sync(_load));
    } catch (_) {
      _pending = null;
      rethrow;
    }
  }
}

Map<String, ElrcCourseSnapshot> parseElrcSnapshots(String text) {
  final data = jsonDecode(text);
  if (data is! Map<String, dynamic> || data['version'] != 1 || data['courses'] is! List) {
    throw const FormatException('录播清单格式错误。');
  }
  final capturedValue = data['capturedAt'];
  final capturedAt = DateTime.tryParse(capturedValue is String ? capturedValue : '');
  if (capturedAt == null) throw const FormatException('录播清单缺少采集时间。');
  final result = <String, ElrcCourseSnapshot>{};
  for (final raw in data['courses'] as List<dynamic>) {
    if (raw is! Map<String, dynamic>) throw const FormatException('录播课程格式错误。');
    final course = parseElrcCourseCatalog(jsonEncode([raw['course']])).single;
    // Failed exports are not represented as empty courses.
    if (raw['status'] == 'failed') continue;
    if (!{'available', 'partial', 'empty'}.contains(raw['status']) ||
        raw['outline'] is! Map<String, dynamic> ||
        raw['files'] is! List) {
      throw const FormatException('录播课程数据不完整。');
    }
    final outlineData = raw['outline'] as Map<String, dynamic>;
    final outline = parseElrcRecordingOutline(
      outlineData,
      expectedCourseId: course.id,
      fallbackCourseNo: course.courseNo,
    );
    final playback = <String, ElrcRecordingSources>{};
    for (final rawWeek in outlineData['recordingVideoInfoShows'] as List<dynamic>) {
      final week = rawWeek as Map<String, dynamic>;
      for (final rawDetail in week['recordInfoDetailList'] as List<dynamic>) {
        final detail = rawDetail as Map<String, dynamic>;
        final one = parseElrcRecordingOutline(
          {
            ...outlineData,
            'recordingVideoInfoShows': [
              {
                ...week,
                'recordInfoDetailList': [detail],
              },
            ],
          },
          expectedCourseId: course.id,
          fallbackCourseNo: course.courseNo,
        );
        if (one.lessons.isEmpty) continue;
        final videos = <Map<String, dynamic>>[];
        final seen = <String>{};
        for (final rawVideo in (detail['videoInfoList'] as List<dynamic>?) ?? const []) {
          final video = rawVideo as Map<String, dynamic>;
          final id = video['videoId'];
          if (id is! String || id.isEmpty) throw const FormatException('视频标识缺失。');
          if (!seen.add(id)) continue;
          final rawLabel = video['seat'] ?? video['videoName'];
          final name = rawLabel is String ? rawLabel : '';
          final label = RegExp(r'教师全景画面|教师近景画面|教师画面|屏幕画面|学生画面').firstMatch(name)?.group(0);
          videos.add({'contentId_': id, 'seat': label ?? name});
        }
        playback[one.lessons.single.id] = parseElrcRecordingSources(videos, raw['files']);
      }
    }
    if (result.containsKey(course.key)) throw const FormatException('录播开课记录重复。');
    result[course.key] = ElrcCourseSnapshot(
      course,
      outline,
      Map.unmodifiable(playback),
      capturedAt,
    );
  }
  return Map.unmodifiable(result);
}
