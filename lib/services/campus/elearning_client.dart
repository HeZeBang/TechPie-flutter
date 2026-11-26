import '../ids/campus_http.dart';
import 'campus_errors.dart';
import 'campus_session.dart';
import 'eams_html_parser.dart';

class ElearningClient {
  ElearningClient(this.session);
  final CampusSession session;
  static const _api = '/learn/api/public/v1';
  static String _course(String id) => 'courses/${segment(id)}';
  static String _content(String course, String content) =>
      '${_course(course)}/contents/${segment(content)}';
  static const _nested = {
    'availability': {'available'},
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

  Future<Map<String, dynamic>> _get(
    String path,
    Set<String> fields, {
    Map<String, String>? query,
    bool list = false,
  }) =>
      session.run((wire) async {
        final data = jsonObject(await wire.request('$_api/$path', query: query));
        if (!list) {
          if (data['id'] is! String) throw CampusRequestException.invalid;
          return _select(data, fields);
        }
        final rows = data['results'];
        if (rows is! List || !rows.every((r) => r is Map<String, dynamic>)) {
          throw CampusRequestException.invalid;
        }
        final paging = data['paging'];
        return {
          'results': [for (final item in rows.cast<Map<String, dynamic>>()) _select(item, fields)],
          if (paging is Map<String, dynamic>) 'paging': _select(paging, {'nextPage', 'prevPage'}),
        };
      });

  Future<Map<String, dynamic>> getMe() => _get('users/me', {'id'});
  Future<Map<String, dynamic>> getMyCourses(String userId, {int limit = 100, int offset = 0}) =>
      _get(
        'users/${segment(userId)}/courses',
        {'courseId', 'courseRoleId', 'availability'},
        list: true,
        query: {'limit': '$limit', 'offset': '$offset'},
      );
  Future<Map<String, dynamic>> getCourse(String courseId) =>
      _get(_course(courseId), {'id', 'courseId', 'name', 'termId', 'availability'});
  Future<Map<String, dynamic>> getCourseContents(
    String courseId, {
    int limit = 100,
    bool recursive = false,
  }) =>
      _get(
        '${_course(courseId)}/contents',
        _contents,
        list: true,
        query: {'limit': '$limit', 'recursive': '$recursive'},
      );
  Future<Map<String, dynamic>> getContentChildren(
    String courseId,
    String contentId, {
    int limit = 100,
  }) =>
      _get(
        '${_content(courseId, contentId)}/children',
        _contents,
        list: true,
        query: {'limit': '$limit'},
      );
  Future<Map<String, dynamic>> getAttachments(String courseId, String contentId) => _get(
        '${_content(courseId, contentId)}/attachments',
        {'id', 'fileName', 'mimeType', 'size'},
        list: true,
      );
  Future<List<int>> downloadAttachment(String courseId, String contentId, String attachmentId) =>
      session.run((wire) async {
        final r = await wire.request(
          '$_api/${_content(courseId, contentId)}/attachments/${segment(attachmentId)}/download',
        );
        checkStatus(r);
        return r.data ?? [];
      });
  Future<Map<String, dynamic>> getGradebookColumns(String courseId) => _get(
        '${_course(courseId)}/gradebook/columns',
        {'id', 'name', 'displayName', 'contentId', 'grading', 'score', 'primaryDisplay'},
        list: true,
        query: {'limit': '100'},
      );
  Future<Map<String, dynamic>> getMyGrades(String courseId, String userId) => _get(
        '${_course(courseId)}/gradebook/users/${segment(userId)}',
        {'columnId', 'score', 'text', 'status', 'displayGrade'},
        list: true,
      );
  Future<Map<String, dynamic>> getCourseGroups(String courseId) =>
      _get('${_course(courseId)}/groups', {'id', 'name', 'description'}, list: true);
  Future<Map<String, dynamic>> getTerms() =>
      _get('terms', {'id', 'name', 'availability'}, list: true, query: {'limit': '100'});
  Future<String> getWebHtml(String path, {Map<String, String>? query}) => session.run((wire) async {
        final r = await wire.request(path, query: query);
        checkStatus(r);
        final source = CampusHttp.text(r);
        if (EamsHtmlParser.isLoginPage(source)) throw CampusRequestException.expired;
        return source;
      });
}
