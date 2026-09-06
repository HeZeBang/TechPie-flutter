import 'dart:convert';

const elrcOrigin = 'https://elrc.shanghaitech.edu.cn';

/// Recording metadata only. This layer performs no network or credential access.
class ElrcRecordingLesson {
  ElrcRecordingLesson({
    required this.courseId,
    required this.courseNo,
    required this.week,
    required this.weekDay,
    required this.weekDate,
    required this.section,
    required List<String> scheduleIds,
  }) : scheduleIds = List<String>.unmodifiable(scheduleIds);

  final String courseId;
  final String courseNo;
  final String week;
  final String weekDay;
  final String weekDate;
  final String section;
  final List<String> scheduleIds;

  // Encoding the tuple avoids collisions when upstream identifiers contain
  // separators. A schedule number alone does not uniquely identify a lesson.
  String get id => jsonEncode([
        courseId,
        courseNo,
        week,
        weekDay,
        section,
        scheduleIds,
      ]);

  String get title => '第$week周 $weekDay $section节';

  Map<String, Object> toVideoQuery() => {
        'courseId': courseId,
        'courseNo': courseNo,
        'week': week,
        'weekDay': weekDay,
        'section': section,
        'scheduleIds': scheduleIds,
      };
}

class ElrcRecordingOutline {
  ElrcRecordingOutline({
    required this.courseId,
    required this.name,
    required List<ElrcRecordingLesson> lessons,
    required this.incompleteLessonCount,
  }) : lessons = List<ElrcRecordingLesson>.unmodifiable(lessons);

  final String courseId;
  final String name;
  final List<ElrcRecordingLesson> lessons;

  /// There is a schedule, but required query metadata is incomplete.
  /// Keep this distinct from a valid course with no recording schedules.
  final int incompleteLessonCount;
}

String _text(Object? value) {
  if (value is String) {
    return value.trim();
  }
  if (value is num) {
    return value.toString();
  }
  return '';
}

Map<String, dynamic> _object(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw const FormatException('录播课程数据格式发生变化。');
}

List<dynamic> _list(Object? value) {
  if (value == null) {
    return const [];
  }
  if (value is List) {
    return value;
  }
  throw const FormatException('录播课次列表格式发生变化。');
}

String _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

/// Port of OpenCourse's courseNo fallback and schedule-id extraction.
/// Input is the courseInfo response's data object, not the HTTP envelope.
ElrcRecordingOutline parseElrcRecordingOutline(
  Map<String, dynamic> data, {
  required String expectedCourseId,
  String? fallbackCourseNo,
}) {
  final courseId = _text(data['courseId']);
  if (courseId.isEmpty || courseId != expectedCourseId) {
    throw const FormatException('返回的课程与所选课程不一致。');
  }
  if (data['recordingVideoInfoShows'] is! List) {
    throw const FormatException('未返回录播课次信息，请核对课程参数或重新登录。');
  }
  final lessons = <String, ElrcRecordingLesson>{};
  var incomplete = 0;
  for (final rawWeek in _list(data['recordingVideoInfoShows'])) {
    final week = _object(rawWeek);
    if (week['recordInfoDetailList'] is! List) {
      throw const FormatException('录播课次列表格式发生变化。');
    }
    for (final rawDetail in _list(week['recordInfoDetailList'])) {
      final detail = _object(rawDetail);
      final live = detail['courseLiveInfo'] == null
          ? <String, dynamic>{}
          : _object(detail['courseLiveInfo']);
      final nestedCourseId = _text(live['courseId']);
      if (nestedCourseId.isNotEmpty && nestedCourseId != courseId) {
        throw const FormatException('课次与所选课程不一致。');
      }
      final schedules = <String>{};
      void addSchedule(Object? value) {
        final id = _text(value);
        if (id.isNotEmpty) {
          schedules.add(id);
        }
      }

      addSchedule(live['scheduleId']);
      for (final rawVideo in _list(detail['videoInfoList'])) {
        addSchedule(_object(rawVideo)['scheduleId']);
      }
      if (schedules.isEmpty) {
        incomplete++;
        continue;
      }
      final courseNo = _firstText([
        live['courseNo'],
        detail['courseNo'],
        detail['course_number'],
        detail['courseNumber'],
        data['courseNo'],
        data['course_number'],
        data['courseNumber'],
        fallbackCourseNo,
      ]);
      if (courseNo.isEmpty ||
          _text(week['week']).isEmpty ||
          _text(detail['weekDay']).isEmpty ||
          _text(detail['section']).isEmpty) {
        incomplete++;
        continue;
      }
      final lesson = ElrcRecordingLesson(
        courseId: courseId,
        courseNo: courseNo,
        week: _text(week['week']),
        weekDay: _text(detail['weekDay']),
        weekDate: _text(detail['weekDate']),
        section: _text(detail['section']),
        scheduleIds: schedules.toList(),
      );
      lessons[lesson.id] = lesson;
    }
  }
  return ElrcRecordingOutline(
    courseId: courseId,
    name: _text(data['courseName']),
    lessons: lessons.values.toList(),
    incompleteLessonCount: incomplete,
  );
}

enum ElrcCameraKind { screen, teacher, other }

class ElrcRecordingSource {
  const ElrcRecordingSource({
    required this.contentId,
    required this.label,
    required this.uri,
    required this.kind,
  });
  final String contentId;
  final String label;
  final Uri uri;
  final ElrcCameraKind kind;
}

class ElrcRecordingSources {
  ElrcRecordingSources(List<ElrcRecordingSource> sources, this.unavailableCount)
      : sources = List.unmodifiable(sources);
  final List<ElrcRecordingSource> sources;
  final int unavailableCount;

  ElrcRecordingSource get preferred => sources.firstWhere(
        (source) => source.kind == ElrcCameraKind.screen,
        orElse: () => sources.firstWhere(
          (source) => source.kind == ElrcCameraKind.teacher,
          orElse: () => sources.first,
        ),
      );
}

/// Fail closed: same HTTPS origin, explicit media file type, no userinfo or
/// fragments. Relative school paths are preserved, including /mstorage.
Uri? parseElrcMediaUri(Object? value) {
  if (value is! String ||
      value.trim().isEmpty ||
      RegExp(r'[\x00-\x20\x7f\\]').hasMatch(value.trim())) {
    return null;
  }
  try {
    final uri = Uri.parse(elrcOrigin).resolve(value.trim());
    if (uri.scheme != 'https' ||
        uri.host != 'elrc.shanghaitech.edu.cn' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !RegExp(r'\.(mp4|m4v|mov|m3u8)$', caseSensitive: false).hasMatch(uri.path)) {
      return null;
    }
    // Matches the media URL handling in the user-supplied Lingke_OSLab
    // CourseVideoPlayer commit 9912371. This affects bucket media only;
    // it is not a login flag for the course/video/fileinfo APIs.
    if (uri.path.contains('/bucket-z/') && !uri.queryParameters.containsKey('isSysAuth')) {
      return uri.replace(
        query: '${uri.hasQuery && uri.query.isNotEmpty ? '${uri.query}&' : ''}isSysAuth=true',
      );
    }
    return uri;
  } on FormatException {
    return null;
  }
}

List<Map<String, dynamic>> parseElrcVideoItems(Object? value) {
  if (value is! List) throw const FormatException('缺少视频列表。');
  final byId = <String, Map<String, dynamic>>{};
  for (final raw in value) {
    final item = _object(raw);
    final id = _text(item['contentId_']);
    if (id.isEmpty) throw const FormatException('缺少视频标识。');
    byId.putIfAbsent(id, () => item);
  }
  return byId.values.toList();
}

ElrcRecordingSources parseElrcRecordingSources(
  List<Map<String, dynamic>> videos,
  Object? rawFiles,
) {
  if (rawFiles is! List) throw const FormatException('缺少视频文件列表。');
  final files = <String, Map<String, dynamic>>{};
  for (final raw in rawFiles) {
    final file = _object(raw);
    final id = _text(file['contentId']);
    if (id.isEmpty || files.containsKey(id)) {
      throw const FormatException('视频文件标识异常。');
    }
    files[id] = file;
  }
  final sources = <ElrcRecordingSource>[];
  var unavailable = 0;
  for (final video in videos) {
    final id = _text(video['contentId_']);
    final file = files[id];
    Uri? uri;
    if (file != null) {
      final stream = <Object?>[];
      final other = <Object?>[];
      for (final rawGroup in _list(file['fileGroups'])) {
        final group = _object(rawGroup);
        final target =
            RegExp(r'流媒体|stream', caseSensitive: false).hasMatch(_text(group['showName']))
                ? stream
                : other;
        for (final rawEntry in _list(group['files'])) {
          target.add(_object(rawEntry)['downloadAddress']);
        }
      }
      for (final address in [...stream, ...other, ..._list(file['downloadAddress'])]) {
        uri = parseElrcMediaUri(address);
        if (uri != null) break;
      }
    }
    if (uri == null) {
      unavailable++;
      continue;
    }
    final rawLabel = _firstText([
      video['seat'],
      file?['seat'],
      video['name'],
      video['name_'],
      video['entityName'],
      file?['name'],
    ]);
    final kind = rawLabel.contains('屏幕') || rawLabel.toLowerCase().contains('screen')
        ? ElrcCameraKind.screen
        : rawLabel.contains('教师')
            ? ElrcCameraKind.teacher
            : ElrcCameraKind.other;
    final safeLabel = rawLabel.isEmpty ||
            rawLabel.contains('://') ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(rawLabel)
        ? '机位 ${sources.length + 1}'
        : rawLabel.substring(0, rawLabel.length > 60 ? 60 : rawLabel.length);
    sources.add(
      ElrcRecordingSource(
        contentId: id,
        label: kind == ElrcCameraKind.screen ? '屏幕画面' : safeLabel,
        uri: uri,
        kind: kind,
      ),
    );
  }
  return ElrcRecordingSources(sources, unavailable);
}
