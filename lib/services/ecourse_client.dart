import 'dart:convert';

import '../models/assignment.dart';
import 'http_client.dart';

class EcourseSessionExpired implements Exception {
  const EcourseSessionExpired();
}

class EcourseClient {
  const EcourseClient(this.http);

  static const platform = 'ecourse';
  static const host = 'ecourse.shanghaitech.edu.cn';
  static const origin = 'https://$host';
  static final coursesUri = Uri.https(host, '/api/my-courses');

  final LoggingHttpClient http;

  Future<List<Assignment>> fetchAssignments(String cookies) async {
    final courses = await _fetchPages(coursesUri, 'courses', cookies);
    final assignments = <String, Assignment>{};
    final visitedCourses = <int>{};
    for (final course in courses) {
      final courseId = _readId(course['id']);
      if (!visitedCourses.add(courseId)) continue;
      final courseName = course['name'];

      final homeworks = await _fetchPages(
        Uri.https(host, '/api/courses/$courseId/homework-activities'),
        'homework_activities',
        cookies,
      );
      for (final homework in homeworks) {
        final endTime = homework['end_time'];
        final rawDue =
            endTime is String && endTime.trim().isNotEmpty ? endTime : homework['deadline'];
        if (rawDue == null || rawDue == '') continue;
        final due = rawDue is String ? DateTime.tryParse(rawDue.trim()) : null;
        final title = homework['title'];
        if (due == null || title is! String || title.trim().isEmpty) {
          throw const FormatException('E 云课堂返回了无效的作业数据');
        }

        final id = '$courseId:${_readId(homework['id'])}';
        assignments[id] = Assignment(
          id: id,
          platform: platform,
          title: title,
          course: courseName is String ? courseName : '',
          due: due.toLocal(),
          status: homework['submitted'] == true ? 'Submitted' : null,
        );
      }
    }
    return assignments.values.toList();
  }

  Future<List<Map<String, dynamic>>> _fetchPages(
    Uri uri,
    String key,
    String cookies,
  ) async {
    final items = <Map<String, dynamic>>[];
    for (var page = 1;; page++) {
      final response = await http.readOnlyGet(
        uri.replace(queryParameters: {'page': '$page', 'page_size': '20'}),
        headers: {'Accept': 'application/json', 'Cookie': cookies},
      );
      if (response.statusCode == 401 ||
          const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        throw const EcourseSessionExpired();
      }
      if (response.statusCode != 200) {
        throw const FormatException('无法读取 E 云课堂列表');
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final rawRows = json is Map<String, dynamic> ? json[key] : null;
      if (json is! Map<String, dynamic> ||
          rawRows is! List<Object?> ||
          !rawRows.every((item) => item is Map<String, dynamic>)) {
        throw const FormatException('E 云课堂返回了无效的列表');
      }
      final rows = rawRows.cast<Map<String, dynamic>>();
      final pages = json['pages'];
      if (pages != null &&
          (pages is! int ||
              pages < 0 ||
              (rows.isNotEmpty && json['page'] != page) ||
              (rows.isEmpty && page < pages))) {
        throw const FormatException('E 云课堂返回了无效的分页信息');
      }
      items.addAll(rows);
      if (pages is! int || page >= pages) return items;
    }
  }

  int _readId(Object? value) {
    final id = value is int
        ? value
        : value is String
            ? int.tryParse(value)
            : null;
    if (id == null || id <= 0) {
      throw const FormatException('E 云课堂返回了无效的编号');
    }
    return id;
  }
}
