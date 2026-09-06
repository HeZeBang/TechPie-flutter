import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/elrc_course.dart';
import '../models/elrc_recording.dart';
import 'elrc_error.dart';
import 'elrc_session_service.dart';
import 'elrc_snapshot_catalog.dart';

const elrcCourseInfoPath = '/learn/v1/course/recording/video/info';
const elrcVideoInfoPath = '/rman/v1/search/new/relation/videos';
const elrcFileInfoPath = '/rman/v1/entity/download/fileinfo';

class ElrcRequest {
  const ElrcRequest(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class ElrcResponse {
  const ElrcResponse(this.status, this.body, {this.headers = const {}});
  final int status;
  final String body;
  final Map<String, List<String>> headers;
}

typedef ElrcTransport = Future<ElrcResponse> Function(ElrcRequest request);

/// Independent from LoggingHttpClient: no response bodies or media addresses
/// are ever passed to the app logger. Transport is replaceable for tests.
class ElrcClient {
  ElrcClient(
    this.session, {
    ElrcTransport? transport,
    this.catalog,
    this.timeout = const Duration(seconds: 20),
  }) : _transport = transport {
    session.addListener(_sessionChanged);
    _generation = session.generation;
  }
  final ElrcSessionService session;
  final ElrcSnapshotCatalog? catalog;
  final ElrcTransport? _transport;
  final Duration timeout;
  final _connections = <HttpClient>{};
  int _generation = 0;
  bool _disposed = false;

  void _sessionChanged() {
    if (_generation == session.generation) return;
    _generation = session.generation;
    for (final client in _connections.toList()) {
      client.close(force: true);
    }
  }

  Future<ElrcResponse> _send(ElrcRequest input) async {
    final client = HttpClient()..connectionTimeout = timeout;
    _connections.add(client);
    try {
      return await (() async {
        final request = await client.openUrl(input.method, input.uri);
        request.followRedirects = false;
        input.headers.forEach(request.headers.set);
        if (input.body != null) request.write(input.body);
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 4 * 1024 * 1024) {
            throw const ElrcException(ElrcErrorKind.invalidResponse);
          }
          bytes.addAll(chunk);
        }
        final headers = <String, List<String>>{};
        response.headers.forEach((name, values) => headers[name.toLowerCase()] = values);
        return ElrcResponse(
          response.statusCode,
          utf8.decode(bytes),
          headers: headers,
        );
      })()
          .timeout(timeout);
    } finally {
      _connections.remove(client);
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _request(
    ElrcCourse course,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final generation = session.generation;
    if (_disposed) throw const ElrcException(ElrcErrorKind.staleSession);
    session.check(generation);
    final uri = Uri.https('elrc.shanghaitech.edu.cn', path, query);
    try {
      final response = await (_transport ?? _send)(
        ElrcRequest(
          body == null ? 'GET' : 'POST',
          uri,
          {
            'Origin': elrcOrigin,
            'Referer': course.recordingUri.toString(),
            'Accept': '*/*',
            'Accept-Language': 'zh-CN,zh;q=0.8,en-US;q=0.7',
            if (body != null) 'Content-Type': 'application/json; charset=utf-8',
          },
          body == null ? null : jsonEncode(body),
        ),
      ).timeout(timeout);
      session.check(generation);
      if (response.status == 401) {
        throw const ElrcException(ElrcErrorKind.forbidden);
      }
      if (response.status == 403) {
        throw const ElrcException(ElrcErrorKind.forbidden);
      }
      if (response.status >= 500 || response.status == 408 || response.status == 429) {
        throw const ElrcException(ElrcErrorKind.network);
      }
      if (response.status >= 300 && response.status < 400) {
        throw const ElrcException(ElrcErrorKind.unsafeAddress);
      }
      if (response.status < 200 || response.status >= 300) {
        throw const ElrcException(ElrcErrorKind.invalidResponse);
      }
      final text = response.body.replaceFirst('\uFEFF', '').trimLeft();
      if (text.startsWith('<')) {
        throw const ElrcException(ElrcErrorKind.forbidden);
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const ElrcException(ElrcErrorKind.invalidResponse);
      }
      final status = decoded['status'];
      if (status == 401) throw const ElrcException(ElrcErrorKind.forbidden);
      if (status == 403) throw const ElrcException(ElrcErrorKind.forbidden);
      if (path == elrcCourseInfoPath) {
        if ((status != 0 && status != 200) || decoded['data'] is! Map<String, dynamic>) {
          throw const ElrcException(ElrcErrorKind.invalidResponse);
        }
      } else if ((decoded.containsKey('success') && decoded['success'] != true) ||
          decoded['data'] == null) {
        throw const ElrcException(ElrcErrorKind.invalidResponse);
      }
      return decoded;
    } on ElrcException {
      rethrow;
    } on FormatException {
      throw const ElrcException(ElrcErrorKind.invalidResponse);
    } catch (_) {
      session.check(generation);
      throw const ElrcException(ElrcErrorKind.network);
    }
  }

  Future<ElrcCourseSnapshot?> _snapshot(ElrcCourse course) async {
    final generation = session.generation;
    if (_disposed) throw const ElrcException(ElrcErrorKind.staleSession);
    session.check(generation);
    try {
      final result = await catalog?.find(course);
      session.check(generation);
      return result;
    } on ElrcException {
      rethrow;
    } catch (_) {
      session.check(generation);
      throw const ElrcException(ElrcErrorKind.invalidResponse);
    }
  }

  Future<ElrcRecordingOutline> getOutline(ElrcCourse course) async {
    final snapshot = await _snapshot(course);
    if (snapshot != null) return snapshot.outline;
    return _getRemoteOutline(course);
  }

  /// Fetch a missing catalog entry without credentials or redirects.
  Future<ElrcRecordingOutline> _getRemoteOutline(ElrcCourse course) async {
    final response = await _request(
      course,
      elrcCourseInfoPath,
      query: {
        'courseId': course.id,
        if (course.reviewId != null) 'id': course.reviewId!,
        if (course.schoolYear != null) 'schoolYear': course.schoolYear!,
        if (course.semester != null) 'semester': course.semester!,
      },
    );
    try {
      return parseElrcRecordingOutline(
        response['data'] as Map<String, dynamic>,
        expectedCourseId: course.id,
        fallbackCourseNo: course.courseNo,
      );
    } on FormatException {
      throw const ElrcException(ElrcErrorKind.invalidResponse);
    }
  }

  Future<ElrcRecordingSources> getSources(
    ElrcCourse course,
    ElrcRecordingLesson lesson,
  ) async {
    final generation = session.generation;
    if (lesson.courseId != course.id) {
      throw const ElrcException(ElrcErrorKind.invalidResponse);
    }
    try {
      final snapshot = await _snapshot(course);
      if (snapshot != null) {
        final sources = snapshot.playbacks[lesson.id];
        if (sources == null) {
          throw const ElrcException(ElrcErrorKind.invalidResponse);
        }
        if (sources.sources.isEmpty) {
          throw const ElrcException(ElrcErrorKind.noPlayableSource);
        }
        return sources;
      }
      final response = await _request(
        course,
        elrcVideoInfoPath,
        body: lesson.toVideoQuery(),
      );
      session.check(generation);
      final data = response['data'];
      if (data is! Map<String, dynamic>) throw const FormatException();
      final videos = parseElrcVideoItems(data['data']);
      if (videos.isEmpty) throw const ElrcException(ElrcErrorKind.noRecording);
      final files = await _request(
        course,
        elrcFileInfoPath,
        body: videos.map((item) => item['contentId_']).toList(),
      );
      session.check(generation);
      final sources = parseElrcRecordingSources(videos, files['data']);
      if (sources.sources.isEmpty) {
        throw const ElrcException(ElrcErrorKind.noPlayableSource);
      }
      return sources;
    } on FormatException {
      throw const ElrcException(ElrcErrorKind.invalidResponse);
    }
  }

  Future<Map<String, String>> playbackHeaders(
    ElrcCourse course,
    Uri media,
  ) async {
    final generation = session.generation;
    session.check(generation);
    if (parseElrcMediaUri(media.toString()) == null) {
      throw const ElrcException(ElrcErrorKind.unsafeAddress);
    }
    return {'Referer': course.recordingUri.toString()};
  }

  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    for (final client in _connections.toList()) {
      client.close(force: true);
    }
  }
}
