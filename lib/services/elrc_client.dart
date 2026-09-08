import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

const _origin = 'https://elrc.shanghaitech.edu.cn';
const _courseList = '/learn/v1/course/video/review/1';
const _courseInfo = '/learn/v1/course/recording/video/info';
const _videoInfo = '/rman/v1/search/new/relation/videos';
const _fileInfo = '/rman/v1/entity/download/fileinfo';

class ElrcCourse {
  const ElrcCourse(
    this.name,
    this.courseId, {
    this.reviewId,
    this.courseNo,
    this.schoolYear,
    this.semester,
    this.description = '',
  });

  final String name;
  final String courseId;
  final String? reviewId;
  final String? courseNo;
  final String? schoolYear;
  final String? semester;
  final String description;

  Uri get referer => Uri.https(
        'elrc.shanghaitech.edu.cn',
        '/learn/videoreview/$courseId',
        {
          if (reviewId != null) 'id': reviewId!,
          if (schoolYear != null) 'schoolYear': schoolYear!,
          if (semester != null) 'semester': semester!,
        },
      );
}

class ElrcLesson {
  ElrcLesson({
    required this.courseId,
    required this.courseNo,
    required this.week,
    required this.weekDay,
    required this.weekDate,
    required this.section,
    required List<String> scheduleIds,
  }) : scheduleIds = List.unmodifiable(scheduleIds);

  final String courseId;
  final String courseNo;
  final String week;
  final String weekDay;
  final String weekDate;
  final String section;
  final List<String> scheduleIds;

  String get title => '第$week周 $weekDay · $section节';

  Map<String, Object> get query => {
        'courseId': courseId,
        'courseNo': courseNo,
        'week': week,
        'weekDay': weekDay,
        'section': section,
        'scheduleIds': scheduleIds,
      };
}

class ElrcSource {
  const ElrcSource(this.label, this.uri);

  final String label;
  final Uri uri;
}

class ElrcException implements Exception {
  const ElrcException(this.message, {this.needsLogin = false});

  final String message;
  final bool needsLogin;

  @override
  String toString() => message;
}

enum _EnvelopeKind { status, success }

class ElrcClient {
  ElrcClient(this.webView);

  final WebViewController webView;
  Completer<_Response>? _pending;
  var _requestId = 0;
  var _disposed = false;

  Future<void> initialize() => webView.addJavaScriptChannel(
        'TechPieElrc',
        onMessageReceived: (message) {
          if (_disposed || message.message.length > 5 * 1024 * 1024) return;
          try {
            final Object? value = jsonDecode(message.message);
            final pending = _pending;
            if (value is! Map<String, dynamic> ||
                value['id'] != _requestId ||
                value['status'] is! num ||
                value['body'] is! String ||
                pending == null ||
                pending.isCompleted) {
              return;
            }
            pending.complete(
              _Response(
                (value['status'] as num).toInt(),
                value['body'] as String,
              ),
            );
          } on FormatException {
            return;
          }
        },
      );

  Future<List<ElrcCourse>> courses() async {
    final result = <String, ElrcCourse>{};
    for (var page = 1; page <= 400; page++) {
      final data = _object(
        await _request(
          _courseList,
          kind: _EnvelopeKind.status,
          query: {
            'type': '1',
            'page': '$page',
            'size': '50',
            'courseTime': '1',
            'playType': '0',
            'orderBy': 'course_name',
          },
        ),
      );
      final total = data['total'];
      final size = data['size'];
      if (data['page'] != page || total is! int || total < 0 || size is! int || size < 1) {
        throw const ElrcException('课程列表格式发生变化');
      }

      final rows = _items(data['results']);
      final previousCount = result.length;
      for (final value in rows) {
        final row = _object(value);
        final name = _requiredText(row['courseName']);
        final id = _requiredText(row['courseId']);
        final number = _optional(row['courseNumber']);
        final serial = _optional(row['serialNumber']);
        final term = _optional(row['showSemester']);
        final course = ElrcCourse(
          name,
          id,
          reviewId: _optional(row['id']),
          courseNo: number,
          schoolYear: _optional(row['schoolYear']),
          semester: _optional(row['semester']),
          description: [number, serial, term]
              .whereType<String>()
              .where((part) => part.isNotEmpty)
              .join(' · '),
        );
        result.putIfAbsent(course.referer.toString(), () => course);
      }
      if (page * size >= total) {
        return List.unmodifiable(result.values);
      }
      if (rows.isEmpty || result.length == previousCount) {
        throw const ElrcException('课程列表分页异常');
      }
    }
    throw const ElrcException('课程列表分页异常');
  }

  Future<List<ElrcLesson>> lessons(ElrcCourse course) async {
    final data = _object(
      await _request(
        _courseInfo,
        kind: _EnvelopeKind.status,
        referer: course.referer,
        query: {
          'courseId': course.courseId,
          if (course.reviewId != null) 'id': course.reviewId!,
          if (course.schoolYear != null) 'schoolYear': course.schoolYear!,
          if (course.semester != null) 'semester': course.semester!,
        },
      ),
    );
    if (_requiredText(data['courseId']) != course.courseId) {
      throw const ElrcException('返回的课程与所选课程不一致');
    }
    final result = <String, ElrcLesson>{};
    for (final weekValue in _items(data['recordingVideoInfoShows'])) {
      final week = _object(weekValue);
      for (final detailValue in _items(week['recordInfoDetailList'])) {
        final detail = _object(detailValue);
        final live = detail['courseLiveInfo'] == null
            ? <String, dynamic>{}
            : _object(detail['courseLiveInfo']);
        final nestedCourseId = _text(live['courseId']);
        if (nestedCourseId.isNotEmpty && nestedCourseId != course.courseId) {
          throw const ElrcException('课次与所选课程不一致');
        }
        final schedules = <String>{};
        final liveSchedule = _text(live['scheduleId']);
        if (liveSchedule.isNotEmpty) schedules.add(liveSchedule);
        for (final value in _items(detail['videoInfoList'])) {
          final scheduleId = _text(_object(value)['scheduleId']);
          if (scheduleId.isNotEmpty) schedules.add(scheduleId);
        }
        final lesson = ElrcLesson(
          courseId: nestedCourseId.isEmpty ? course.courseId : nestedCourseId,
          courseNo: _first([
            live['courseNo'],
            detail['courseNo'],
            detail['course_number'],
            detail['courseNumber'],
            data['courseNo'],
            data['course_number'],
            data['courseNumber'],
            course.courseNo,
          ]),
          week: _text(week['week']),
          weekDay: _text(detail['weekDay']),
          weekDate: _text(detail['weekDate']),
          section: _text(detail['section']),
          scheduleIds: schedules.toList(),
        );
        if (lesson.courseNo.isEmpty ||
            lesson.week.isEmpty ||
            lesson.weekDay.isEmpty ||
            lesson.section.isEmpty ||
            lesson.scheduleIds.isEmpty) {
          continue;
        }
        result[jsonEncode([
          lesson.courseId,
          lesson.courseNo,
          lesson.week,
          lesson.weekDay,
          lesson.section,
          lesson.scheduleIds,
        ])] = lesson;
      }
    }
    if (result.isEmpty) throw const ElrcException('这门课程暂无录播课次');
    return List.unmodifiable(result.values);
  }

  Future<List<ElrcSource>> sources(
    ElrcCourse course,
    ElrcLesson lesson,
  ) async {
    if (lesson.courseId != course.courseId) {
      throw const ElrcException('课次与所选课程不一致');
    }

    final videoPage = _object(
      await _request(
        _videoInfo,
        kind: _EnvelopeKind.success,
        body: lesson.query,
        referer: course.referer,
      ),
    );
    final videos = <String, Map<String, dynamic>>{};
    for (final value in _items(videoPage['data'])) {
      final video = _object(value);
      final contentId = _requiredText(video['contentId_']);
      if (videos.containsKey(contentId)) {
        throw const ElrcException('视频标识重复');
      }
      videos[contentId] = video;
    }
    if (videos.isEmpty) throw const ElrcException('这个课次暂无视频');

    final files = <String, Map<String, dynamic>>{};
    for (final value in _items(
      await _request(
        _fileInfo,
        kind: _EnvelopeKind.success,
        body: videos.keys.toList(),
        referer: course.referer,
      ),
    )) {
      final file = _object(value);
      final contentId = _requiredText(file['contentId']);
      if (files.containsKey(contentId)) {
        throw const ElrcException('视频文件标识重复');
      }
      files[contentId] = file;
    }

    final result = <ElrcSource>[];
    var index = 0;
    for (final entry in videos.entries) {
      final video = entry.value;
      final file = files[entry.key];
      if (file == null) {
        throw const ElrcException('视频信息与文件信息不一致');
      }
      final address = _address(file);
      if (address == null) {
        throw const ElrcException('没有可播放的视频地址');
      }
      final name = _first([
        video['seat'],
        file['seat'],
        video['name'],
        video['name_'],
        file['entityName'],
      ]);
      result.add(
        ElrcSource(
          _sourceLabel(name, index),
          _mediaUri(address),
        ),
      );
      index++;
    }
    return List.unmodifiable(result);
  }

  String _sourceLabel(String name, int index) {
    final normalized = name.toLowerCase();
    if (normalized.contains('tchpan') || name.contains('全景')) {
      return '全景画面';
    }
    if (normalized.contains('screen') || name.contains('屏幕')) {
      return '屏幕画面';
    }
    if (normalized == 'tch' ||
        normalized.contains('teacher') ||
        name.contains('教师') ||
        name.contains('近景')) {
      return '教师画面';
    }
    return name.isEmpty ? '机位 ${index + 1}' : name;
  }

  Future<Object?> _request(
    String path, {
    required _EnvelopeKind kind,
    Map<String, String>? query,
    Object? body,
    Uri? referer,
  }) async {
    final response = await _send(
      Uri.https('elrc.shanghaitech.edu.cn', path, query),
      body,
      referer ?? Uri.parse('$_origin/learn/videoreview?type=1'),
    );
    final responseBody = response.body.replaceFirst('\uFEFF', '');
    if (response.status == 401 || responseBody.trimLeft().startsWith('<')) {
      throw const ElrcException('ELRC 登录已失效', needsLogin: true);
    }
    if (response.status == 403) throw const ElrcException('没有访问权限');
    if (response.status == 0 ||
        response.status == 408 ||
        response.status == 429 ||
        response.status >= 500) {
      throw const ElrcException('ELRC 网络连接失败');
    }
    if (response.status < 200 || response.status >= 300) {
      throw ElrcException('ELRC 请求失败（${response.status}）');
    }
    try {
      final Object? decoded = jsonDecode(responseBody);
      final envelope = _object(decoded);
      return switch (kind) {
        _EnvelopeKind.status => _readStatusData(envelope),
        _EnvelopeKind.success => _readSuccessData(envelope),
      };
    } on FormatException {
      throw const ElrcException('ELRC 返回格式发生变化');
    }
  }

  Object? _readStatusData(Map<String, dynamic> envelope) {
    final status = envelope['status'];
    if (status != null && status is! num) {
      throw const ElrcException('ELRC 返回格式发生变化');
    }
    if (status is num && status != 0 && status != 200) {
      if (status == 401) {
        throw const ElrcException('ELRC 登录已失效', needsLogin: true);
      }
      if (status == 403) throw const ElrcException('没有访问权限');
      final message = _text(envelope['message']);
      throw ElrcException(message.isEmpty ? 'ELRC 请求失败' : message);
    }
    if (!envelope.containsKey('data') || !_hasData(envelope['data'])) {
      throw const ElrcException('ELRC 返回格式发生变化');
    }
    return envelope['data'];
  }

  Object? _readSuccessData(Map<String, dynamic> envelope) {
    final success = envelope['success'];
    if (success != null && success is! bool) {
      throw const ElrcException('ELRC 返回格式发生变化');
    }
    if (success == false) throw const ElrcException('ELRC 请求失败');
    if (!envelope.containsKey('data') || !_hasData(envelope['data'])) {
      throw const ElrcException('ELRC 返回格式发生变化');
    }
    return envelope['data'];
  }

  Future<_Response> _send(Uri uri, Object? body, Uri referer) async {
    if (_disposed) throw const ElrcException('ELRC 页面已关闭');
    if (_pending != null) throw const ElrcException('上一个请求尚未完成');
    final id = ++_requestId;
    final pending = _pending = Completer<_Response>();
    final encodedBody = body == null ? null : jsonEncode(body);
    try {
      await webView.runJavaScript('''
(async () => {
  const id = $id;
  if (location.origin !== ${jsonEncode(_origin)}) {
    TechPieElrc.postMessage(JSON.stringify({id, status: 0, body: ''}));
    return;
  }
  try {
    const response = await fetch(${jsonEncode(uri.toString())}, {
      method: ${jsonEncode(body == null ? 'GET' : 'POST')},
      credentials: 'same-origin',
      redirect: 'error',
      cache: 'no-store',
      referrer: ${jsonEncode(referer.toString())},
      headers: {
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.8,en-US;q=0.7',
        ${encodedBody == null ? '' : "'Content-Type': 'application/json; charset=utf-8',"}
      },
      ${encodedBody == null ? '' : 'body: ${jsonEncode(encodedBody)},'}
    });
    const text = await response.text();
    TechPieElrc.postMessage(JSON.stringify({
      id,
      status: response.status,
      body: text.length <= 4 * 1024 * 1024 ? text : ''
    }));
  } catch (_) {
    TechPieElrc.postMessage(JSON.stringify({id, status: 0, body: ''}));
  }
})();
''');
      return await pending.future.timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw const ElrcException('ELRC 请求超时');
    } on ElrcException {
      rethrow;
    } catch (_) {
      throw const ElrcException('ELRC 网络连接失败');
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  void dispose() {
    _disposed = true;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const ElrcException('ELRC 页面已关闭'));
    }
    _pending = null;
  }
}

class _Response {
  const _Response(this.status, this.body);
  final int status;
  final String body;
}

Map<String, dynamic> _object(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const ElrcException('ELRC 返回格式发生变化');
}

List<dynamic> _items(Object? value) {
  if (value is List<dynamic>) return value;
  throw const ElrcException('ELRC 返回格式发生变化');
}

bool _hasData(Object? value) {
  if (value == null) return false;
  if (value is List<Object?>) return value.isNotEmpty;
  if (value is Map<Object?, Object?>) return value.isNotEmpty;
  return true;
}

String _text(Object? value) {
  if (value is String) return value.trim();
  if (value is num) return value.toString();
  return '';
}

String _requiredText(Object? value) {
  final result = _text(value);
  if (result.isEmpty) {
    throw const ElrcException('ELRC 返回格式发生变化');
  }
  return result;
}

String? _optional(Object? value) {
  if (value == null) return null;
  final result = _text(value);
  if (value is String && result.isEmpty) return null;
  if (result.isEmpty) {
    throw const ElrcException('ELRC 返回格式发生变化');
  }
  return result;
}

String _first(Iterable<Object?> values) {
  for (final value in values) {
    final result = _text(value);
    if (result.isNotEmpty) return result;
  }
  return '';
}

String? _address(Map<String, dynamic> file) {
  for (final group in _items(file['fileGroups'])) {
    for (final value in _items(_object(group)['files'])) {
      final address = _text(_object(value)['downloadAddress']);
      if (address.isNotEmpty) return address;
    }
  }
  for (final value in _items(file['downloadAddress'])) {
    final address = _text(value);
    if (address.isNotEmpty) return address;
  }
  return null;
}

Uri _mediaUri(String address) {
  final normalized = address.trim();
  if (normalized.isEmpty ||
      normalized.codeUnits.any(
        (value) => value <= 0x20 || value == 0x7f || value == 0x5c,
      )) {
    throw const ElrcException('视频地址格式不正确');
  }
  final Uri uri;
  try {
    uri = Uri.parse(_origin).resolve(normalized);
  } on FormatException {
    throw const ElrcException('视频地址格式不正确');
  }
  if (uri.scheme != 'https' ||
      uri.host != 'elrc.shanghaitech.edu.cn' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const ElrcException('视频地址不属于 ELRC');
  }
  if (!uri.path.contains('/bucket-z/') || uri.queryParameters.containsKey('isSysAuth')) {
    return uri;
  }
  return Uri.parse(
    '${uri.toString()}${uri.query.isEmpty ? '?' : '&'}isSysAuth=true',
  );
}
