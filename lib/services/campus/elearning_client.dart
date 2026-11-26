import 'dart:convert';

import '../ids/campus_http.dart';
import 'campus_errors.dart';
import 'campus_session.dart';
import 'eams_html_parser.dart';

class ElearningClient {
  ElearningClient(this.session);
  final CampusSession session;
  static const _api = '/learn/api/public/v1';
  static const _maxPages = 20;
  static String _course(String id) => 'courses/${segment(id)}';
  static String _content(String course, String content) =>
      '${_course(course)}/contents/${segment(content)}';
  static const _nested = {
    'availability': {'available'},
    'duration': {'type', 'start', 'end'},
    'contentHandler': {'id'},
    'grading': {'due', 'type', 'attemptsAllowed'},
    'score': {'possible', 'decimalPlaces'},
    'primaryDisplay': {'type'},
    'displayGrade': {'scaleType', 'score', 'text'},
  };

  static Map<String, dynamic> _select(Map<String, dynamic> item, Set<String> fields) {
    final result = <String, dynamic>{};
    for (final key in fields) {
      if (!item.containsKey(key)) continue;
      final value = item[key];
      if (value is Map<String, dynamic> && _nested.containsKey(key)) {
        result[key] = _select(value, _nested[key]!);
      } else if (value == null || value is num || value is bool || value is String) {
        result[key] = value;
      } else if (key == 'children' && value is List) {
        result[key] = value.map((child) {
          if (child is! Map<String, dynamic>) throw CampusRequestException.invalid;
          return _select(child, fields);
        }).toList();
      }
    }
    return result;
  }

  static const _contents = {
    'id',
    'parentId',
    'title',
    'body',
    'position',
    'hasChildren',
    'children',
    'contentHandler',
    'availability',
    'created',
    'modified',
  };

  static Map<String, dynamic> _selectPage(
    Map<String, dynamic> data,
    Set<String> fields,
  ) {
    final rows = data['results'];
    if (rows is! List || !rows.every((r) => r is Map<String, dynamic>)) {
      throw CampusRequestException.invalid;
    }
    final paging = data['paging'];
    return {
      'results': [for (final item in rows.cast<Map<String, dynamic>>()) _select(item, fields)],
      if (paging is Map<String, dynamic>) 'paging': _select(paging, {'nextPage', 'prevPage'}),
    };
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Set<String> fields, {
    Map<String, String>? query,
    bool list = false,
    bool allPages = false,
  }) =>
      session.run((wire) async {
        final fullPath = '$_api/$path';
        final firstData = jsonObject(await wire.request(fullPath, query: query));
        if (!list) {
          if (firstData['id'] is! String) throw CampusRequestException.invalid;
          return _select(firstData, fields);
        }
        final firstPage = _selectPage(firstData, fields);
        if (!allPages) return firstPage;

        final collected = <Map<String, dynamic>>[
          ...(firstPage['results'] as List<Map<String, dynamic>>),
        ];
        final baseUri = wire.origin.resolve(fullPath);
        final firstFullUri = query == null || query.isEmpty
            ? baseUri
            : baseUri.replace(queryParameters: {...baseUri.queryParameters, ...query});
        final seen = <String>{'${firstFullUri.path}?${firstFullUri.query}'};
        var currentPage = firstPage;

        for (var pageIndex = 1; pageIndex < _maxPages; pageIndex++) {
          final paging = currentPage['paging'];
          final nextPage = paging is Map<String, dynamic> ? paging['nextPage'] : null;
          if (nextPage is! String || nextPage.isEmpty) {
            return {'results': collected};
          }
          final nextUri = wire.origin.resolve(nextPage);
          if (nextUri.origin != wire.origin.origin || nextUri.path != baseUri.path) {
            throw const CampusRequestException(CampusErrorKind.rejected, '不支持的分页地址');
          }
          final key = '${nextUri.path}?${nextUri.query}';
          if (!seen.add(key)) {
            return {'results': collected};
          }
          final nextData = jsonObject(await wire.request(nextPage));
          currentPage = _selectPage(nextData, fields);
          collected.addAll(currentPage['results'] as List<Map<String, dynamic>>);
        }
        final trailingPaging = currentPage['paging'];
        return {
          'results': collected,
          if (trailingPaging is Map<String, dynamic>) 'paging': trailingPaging,
        };
      });

  static Map<String, String>? _paginationQuery({
    int? limit,
    int? offset,
    Map<String, String>? extra,
  }) {
    final map = <String, String>{
      ...?extra,
      if (limit != null) 'limit': '$limit',
      if (offset != null) 'offset': '$offset',
    };
    return map.isEmpty ? null : map;
  }

  Future<Map<String, dynamic>> getMe() => _get('users/me', {'id'});

  Future<Map<String, dynamic>> getMyCourses(
    String userId, {
    int limit = 100,
    int offset = 0,
    bool allPages = false,
  }) =>
      _get(
        'users/${segment(userId)}/courses',
        {'courseId', 'courseRoleId', 'availability'},
        list: true,
        allPages: allPages,
        query: {'limit': '$limit', 'offset': '$offset'},
      );

  Future<Map<String, dynamic>> getCourse(String courseId) =>
      _get(_course(courseId), {'id', 'courseId', 'name', 'termId', 'availability'});

  Future<Map<String, dynamic>> getCourseContents(
    String courseId, {
    int limit = 100,
    int? offset,
    bool recursive = false,
    bool allPages = false,
  }) =>
      _get(
        '${_course(courseId)}/contents',
        _contents,
        list: true,
        allPages: allPages,
        query: _paginationQuery(
          limit: limit,
          offset: offset,
          extra: {'recursive': '$recursive'},
        ),
      );

  Future<Map<String, dynamic>> getContentChildren(
    String courseId,
    String contentId, {
    int limit = 100,
    int? offset,
    bool allPages = false,
  }) =>
      _get(
        '${_content(courseId, contentId)}/children',
        _contents,
        list: true,
        allPages: allPages,
        query: _paginationQuery(limit: limit, offset: offset),
      );

  Future<Map<String, dynamic>> getAttachments(
    String courseId,
    String contentId, {
    int? limit,
    int? offset,
    bool allPages = false,
  }) =>
      _get(
        '${_content(courseId, contentId)}/attachments',
        {'id', 'fileName', 'mimeType', 'size'},
        list: true,
        allPages: allPages,
        query: _paginationQuery(limit: limit, offset: offset),
      );

  Future<List<int>> downloadAttachment(String courseId, String contentId, String attachmentId) =>
      session.run((wire) async {
        final r = await wire.request(
          '$_api/${_content(courseId, contentId)}/attachments/${segment(attachmentId)}/download',
        );
        checkStatus(r);
        return r.data ?? [];
      });

  Future<Map<String, dynamic>> getGradebookColumns(
    String courseId, {
    int limit = 100,
    int? offset,
    bool allPages = false,
  }) =>
      _get(
        '${_course(courseId)}/gradebook/columns',
        {'id', 'name', 'displayName', 'contentId', 'grading', 'score', 'primaryDisplay'},
        list: true,
        allPages: allPages,
        query: _paginationQuery(limit: limit, offset: offset),
      );

  Future<Map<String, dynamic>> getMyGrades(
    String courseId,
    String userId, {
    int? limit,
    int? offset,
    bool allPages = false,
  }) =>
      _get(
        '${_course(courseId)}/gradebook/users/${segment(userId)}',
        {'columnId', 'id', 'score', 'text', 'status', 'displayGrade'},
        list: true,
        allPages: allPages,
        query: _paginationQuery(limit: limit, offset: offset),
      );

  Future<Map<String, dynamic>> getCourseGroups(
    String courseId, {
    int? limit,
    int? offset,
    bool allPages = false,
  }) =>
      _get(
        '${_course(courseId)}/groups',
        {'id', 'name', 'description'},
        list: true,
        allPages: allPages,
        query: _paginationQuery(limit: limit, offset: offset),
      );

  Future<Map<String, dynamic>> getTerms({
    int limit = 100,
    int? offset,
    bool allPages = false,
  }) =>
      _get(
        'terms',
        {'id', 'name', 'availability', 'duration'},
        list: true,
        allPages: allPages,
        query: _paginationQuery(limit: limit, offset: offset),
      );

  Future<List<Map<String, dynamic>>> getCalendarEvents(
    DateTime start, {
    DateTime? end,
  }) async {
    final data = await getWebHtml(
      '/webapps/calendar/calendarData/allCourseEvents',
      query: {
        'start': start.millisecondsSinceEpoch.toString(),
        if (end != null) 'end': end.millisecondsSinceEpoch.toString(),
      },
    );
    try {
      final rows = jsonDecode(data);
      if (rows is! List || !rows.every((r) => r is Map<String, dynamic>)) {
        throw CampusRequestException.invalid;
      }
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          _select(row, {
            'end',
            'start',
            'itemSourceId',
            'calendarId',
            'title',
            'calendarName',
            'attemptable',
          }),
      ];
    } on FormatException {
      throw CampusRequestException.invalid;
    }
  }

  Future<String> getWebHtml(String path, {Map<String, String>? query}) => session.run((wire) async {
        final r = await wire.request(path, query: query);
        checkStatus(r);
        final source = CampusHttp.text(r);
        if (EamsHtmlParser.isLoginPage(source)) throw CampusRequestException.expired;
        return source;
      });
}
