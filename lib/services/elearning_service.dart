import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;

import '../models/assignment.dart';
import '../models/elearning_models.dart';
import 'campus/campus_errors.dart';
import 'campus/campus_session.dart';
import 'campus/elearning_client.dart';
import 'storage_service.dart';

class ElearningService {
  ElearningService(this.client, {this.storage}) : _owner = client.session.identity() {
    final saved = storage?.blackboardIndex;
    if (saved == null) return;
    if (saved['owner'] != _key || _owner.ids == null || _owner.user == null) {
      unawaited(storage!.clearBlackboardIndex());
      return;
    }
    try {
      cachedCourses = _sortCachedCourses(
        _rows(saved['courses']).map(BlackboardCourse.fromJson).toList(),
      );
      cachedAnnouncements =
          _rows(saved['announcements']).map(BlackboardAnnouncement.fromJson).toList();
    } on TypeError {
      cachedCourses = [];
      cachedAnnouncements = [];
      unawaited(storage!.clearBlackboardIndex());
    }
  }
  final ElearningClient client;
  final StorageService? storage;
  CampusIdentity _owner;
  int _version = 0;
  bool _disposed = false;
  Future<List<BlackboardCourse>>? _loading;
  List<BlackboardCourse>? _loadedCourses;
  List<Map<String, dynamic>> _lastTermRows = const [];
  Map<String, String> _courseTermIds = const {};
  List<BlackboardCourse> cachedCourses = [];
  List<BlackboardAnnouncement> cachedAnnouncements = [];
  static List<Map<String, dynamic>> _rows(Object? v) =>
      (v as List? ?? []).cast<Map<String, dynamic>>();
  String get _key => sha256.convert(utf8.encode(jsonEncode([_owner.user, _owner.ids]))).toString();

  Future<void> accountChanged() {
    final owner = client.session.identity();
    if (_owner == owner) return Future.value();
    _owner = owner;
    _version++;
    _loading = null;
    _loadedCourses = null;
    _lastTermRows = const [];
    _courseTermIds = const {};
    cachedCourses = [];
    cachedAnnouncements = [];
    return storage?.clearBlackboardIndex() ?? Future.value();
  }

  void dispose() {
    _disposed = true;
    _version++;
  }

  void _check(int version) {
    unawaited(accountChanged());
    if (_disposed || version != _version) throw CampusRequestException.expired;
  }

  Future<void> _save() async {
    await storage?.saveBlackboardIndex({
      'owner': _key,
      'courses': cachedCourses.map((v) => v.toJson()).toList(),
      'announcements': cachedAnnouncements.map((v) => v.toJson()).toList(),
    });
  }

  Future<List<BlackboardCourse>> courses({bool refresh = false}) {
    unawaited(accountChanged());
    if (!refresh && _loadedCourses != null) {
      return Future.value(_loadedCourses!);
    }
    final pending = _loading;
    if (pending != null) return pending;
    final version = _version;
    return _loading = _courses(version).whenComplete(() {
      if (version == _version) _loading = null;
    });
  }

  static int? _parseBlackboardNumericId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    final direct = int.tryParse(trimmed);
    if (direct != null) return direct;
    final match = RegExp(r'_(\d+)_').firstMatch(trimmed);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static int? _termDurationSortKey(Map<String, dynamic> row) {
    final duration = row['duration'] as Map?;
    final dt = _deadlineTime(duration?['start']) ?? _deadlineTime(duration?['end']);
    return dt == null ? null : dt.year * 100 + dt.month;
  }

  static List<BlackboardCourse> _sortCachedCourses(List<BlackboardCourse> courses) {
    final entries = [
      for (var i = 0; i < courses.length; i++) (course: courses[i], index: i),
    ]..sort((a, b) {
        final byTerm = compareBlackboardTermNames(a.course.term, b.course.term);
        return byTerm != 0 ? byTerm : a.index.compareTo(b.index);
      });
    return [for (final e in entries) e.course];
  }

  Future<List<BlackboardCourse>> _courses(int version) async {
    final user = await client.getMe();
    _check(version);
    final memberships =
        _rows((await client.getMyCourses(user['id'] as String, allPages: true))['results']);
    _check(version);
    final termRows = _rows((await client.getTerms(allPages: true))['results']);
    final terms = <String, String>{};
    final termDurationKeys = <String, int>{};
    for (final row in termRows) {
      final termId = row['id']?.toString() ?? '';
      if (termId.isEmpty) continue;
      final name = row['name'] as String?;
      if (name != null) terms[termId] = name;
      final durationKey = _termDurationSortKey(row);
      if (durationKey != null) termDurationKeys[termId] = durationKey;
    }
    final entries = <({
      BlackboardCourse course,
      bool hasTerm,
      int? sortKey,
      int? numericTermId,
      int index,
    })>[];
    final courseTermIds = <String, String>{};
    for (final id in {
      for (final m in memberships)
        if ((m['availability'] as Map?)?['available'] != 'No') m['courseId'] as String,
    }) {
      _check(version);
      try {
        final row = await client.getCourse(id);
        if ((row['availability'] as Map?)?['available'] == 'No') continue;
        final termId = row['termId'] as String? ?? '';
        courseTermIds[id] = termId;
        final course = BlackboardCourse.fromJson({...row, 'term': terms[termId] ?? ''});
        final trimmedTerm = course.term.trim();
        final hasTerm = trimmedTerm.isNotEmpty && trimmedTerm != '其他学期';
        entries.add((
          course: course,
          hasTerm: hasTerm,
          sortKey: parseBlackboardTermSortKey(course.term) ?? termDurationKeys[termId],
          numericTermId: _parseBlackboardNumericId(termId),
          index: entries.length,
        ),);
      } on CampusRequestException catch (e) {
        if (e.kind != CampusErrorKind.forbidden && e.kind != CampusErrorKind.notFound) rethrow;
      }
    }
    _check(version);
    entries.sort((a, b) {
      if (a.hasTerm != b.hasTerm) return a.hasTerm ? -1 : 1;
      final keyA = a.sortKey;
      final keyB = b.sortKey;
      if (keyA != null && keyB != null && keyA != keyB) {
        return keyB.compareTo(keyA);
      }
      if ((keyA != null) != (keyB != null)) return keyA != null ? -1 : 1;
      final numA = a.numericTermId;
      final numB = b.numericTermId;
      if (numA != null && numB != null && numA != numB) {
        return numB.compareTo(numA);
      }
      return a.index.compareTo(b.index);
    });
    final courses = [for (final entry in entries) entry.course];
    _lastTermRows = termRows;
    _courseTermIds = courseTermIds;
    _loadedCourses = List.unmodifiable(courses);
    cachedCourses = courses;
    await _save();
    _check(version);
    return _loadedCourses!;
  }

  Future<List<BlackboardContent>> contents(String course, [String? parent]) async {
    final data = parent == null
        ? await client.getCourseContents(course, allPages: true)
        : await client.getContentChildren(course, parent, allPages: true);
    return [
      for (final row in _rows(data['results']))
        BlackboardContent(
          row['id'] as String,
          row['title'] as String? ?? '',
          _plain(row['body']),
          row['hasChildren'] == true ||
              (row['contentHandler'] as Map?)?['id'] == 'resource/x-bb-folder',
          (row['contentHandler'] as Map?)?['id'] == 'resource/x-bb-assignment',
        ),
    ];
  }

  Future<List<BlackboardAttachment>> attachments(String course, String content) async => [
        for (final row
            in _rows((await client.getAttachments(course, content, allPages: true))['results']))
          BlackboardAttachment(row['id'] as String, row['fileName'] as String? ?? 'attachment'),
      ];

  Future<List<int>> downloadBytes(
    String course,
    String content,
    BlackboardAttachment attachment,
  ) async {
    unawaited(accountChanged());
    final version = _version;
    final bytes = await client.downloadAttachment(course, content, attachment.id);
    _check(version);
    return bytes;
  }

  Uri web(String path, Map<String, String> query) =>
      client.session.origin.resolve(path).replace(queryParameters: query);
  Uri assignmentUrl(String course, String content) => web(
        '/webapps/assignment/uploadAssignment',
        {'content_id': content, 'course_id': course, 'mode': 'view'},
      );
  static String _plain(Object? text) =>
      html.parseFragment(text?.toString() ?? '').text?.trim() ?? '';

  Future<List<BlackboardGrade>> grades(String course) async {
    final version = _version;
    final user = await client.getMe();
    _check(version);
    final columns = _rows((await client.getGradebookColumns(course, allPages: true))['results']);
    _check(version);
    final byId = {
      for (final result in _rows(
        (await client.getMyGrades(course, user['id'] as String, allPages: true))['results'],
      ))
        result['columnId']: result,
    };
    _check(version);
    return [for (final col in columns) _grade(course, col, byId[col['id']])];
  }

  Uri myGradesUrl(String course) => web('/webapps/bb-mygrades-BBLEARN/myGrades', {
        'course_id': course,
        'stream_name': 'mygrades',
      });

  Future<BlackboardReceiptPage> submissionReceipts(String course) async {
    unawaited(accountChanged());
    final version = _version;
    final stream = myGradesUrl(course);
    final grades = html.parse(await client.getWebHtml(stream.toString()));
    _check(version);
    final link = grades.querySelector('#submissionReceipts a[href]');
    final count = int.tryParse(link?.text.trim() ?? '');
    if (count == null || count < 0) throw CampusRequestException.invalid;
    if (count == 0) return const BlackboardReceiptPage(0, []);
    final url = stream.resolve(link!.attributes['href']!);
    if (url.userInfo.isNotEmpty ||
        !url.isScheme('https') ||
        url.origin != stream.origin ||
        url.path != '/webapps/gradebook/do/instructor/viewAttemptReceipts' ||
        url.queryParameters['course_id'] != course ||
        (url.queryParameters['user_id'] ?? '').isEmpty ||
        (url.queryParameters['is_stream'] ?? '').isEmpty) {
      throw CampusRequestException.invalid;
    }
    final detail = html.parse(await client.getWebHtml(url.toString()));
    _check(version);
    final table = detail.querySelector('table#listContainer_datatable');
    if (table == null) throw CampusRequestException.invalid;
    final headings = table.querySelectorAll('thead th').map((h) => h.text.trim()).toList();
    final indexes = [
      for (final alternatives in const [
        ['确认编号', 'Confirmation Number'],
        ['课程作业', 'Coursework'],
        ['日期', 'Date'],
        ['提交', 'Submission'],
        ['大小', 'Size'],
      ])
        headings.indexWhere(alternatives.contains),
    ];
    if (indexes.contains(-1)) throw CampusRequestException.invalid;
    final receipts = <BlackboardReceipt>[];
    for (final row in table.querySelectorAll('tbody > tr')) {
      final cells = row.children;
      if (cells.length != headings.length) continue;
      final number = cells[indexes[0]].text.trim();
      final assignment = cells[indexes[1]].text.trim();
      if (number.isEmpty || assignment.isEmpty) continue;
      receipts.add(
        BlackboardReceipt(
          number,
          assignment,
          cells[indexes[2]].text.trim(),
          cells[indexes[3]].text.trim(),
          cells[indexes[4]].text.trim(),
        ),
      );
    }
    if (receipts.isEmpty) throw CampusRequestException.invalid;
    return BlackboardReceiptPage(count, receipts);
  }

  BlackboardGrade _grade(String course, Map<String, dynamic> col, Map<String, dynamic>? mark) {
    final display = mark?['displayGrade'] as Map?;
    return BlackboardGrade(
      col['id'] as String,
      (col['displayName'] ?? col['name'] ?? '').toString(),
      (display?['text'] ?? display?['score'] ?? mark?['score'] ?? mark?['text'] ?? '').toString(),
      ((col['score'] as Map?)?['possible'] ?? '').toString(),
      (mark?['status'] ?? '').toString(),
      mark?['id'] == null
          ? null
          : web('/webapps/gradebook/do/student/viewAttempts', {
              'method': 'list',
              'course_id': course,
              'outcome_definition_id': col['id'] as String,
              'outcome_id': mark!['id'] as String,
            }),
    );
  }

  Future<List<BlackboardGroup>> groups(String course) async => [
        for (final row in _rows((await client.getCourseGroups(course, allPages: true))['results']))
          BlackboardGroup(row['name'] as String? ?? '', _plain(row['description'])),
      ];

  static List<BlackboardAnnouncement> parseAnnouncements(String source) {
    final doc = html.parse(source);
    final items = doc.querySelectorAll(
      '#announcementList > li, li.announcement, .announcementInfo, article.announcement',
    );
    return [
      for (final item
          in items.where((item) => !items.any((other) => other != item && other.contains(item))))
        if (item.querySelector('h3,h2,.announcementTitle') case final heading?)
          BlackboardAnnouncement(
            heading.text.trim(),
            item.querySelector('.vtbegenerated,.announcementBody,.details')?.text.trim() ?? '',
          ),
    ];
  }

  Future<List<BlackboardAnnouncement>> announcements([String? course]) async {
    final version = _version;
    final items = parseAnnouncements(
      await client.getWebHtml(
        '/webapps/blackboard/execute/announcement',
        query: {
          'method': 'search',
          'context': course == null ? 'mybb' : 'course_entry',
          'handle': course == null ? 'my_announcements' : 'announcements_entry',
          if (course != null) ...{'course_id': course, 'mode': 'view'},
        },
      ),
    );
    _check(version);
    if (course == null) {
      cachedAnnouncements = [
        for (final a in items)
          BlackboardAnnouncement(a.title, a.text.length > 180 ? a.text.substring(0, 180) : a.text),
      ];
      await _save();
    }
    _check(version);
    return items;
  }

  static DateTime? _deadlineTime(Object? raw) {
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw > 1e12 ? raw.toInt() : raw.toInt() * 1000);
    }
    if (raw is! String || raw.trim().isEmpty) return null;
    final time = raw.trim().replaceFirst(' ', 'T');
    return DateTime.tryParse(
      RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(time) ? time : '$time+08:00',
    )?.toLocal();
  }

  Future<Map<String, String>?> _deadlineStatuses(String course) async {
    try {
      final page = html.parse(await client.getWebHtml(myGradesUrl(course).toString()));
      final grades = page.querySelector('#streamDetailMainBodyRight');
      if (grades == null) return null;
      return {
        // My Grades uses the numeric part of the REST gradebook column ID.
        for (final row in grades.querySelectorAll('.sortable_item_row[id]'))
          if (row.querySelector(r'.gradeStatus img[src$="needs_grading.png"]') != null)
            '_${row.id}_1': 'Submitted'
          else if (row.classes.contains('graded_item_row'))
            '_${row.id}_1': 'Graded',
      };
    } on CampusRequestException catch (e) {
      switch (e.kind) {
        case CampusErrorKind.notLoggedIn:
        case CampusErrorKind.idsNotBound:
        case CampusErrorKind.sessionExpired:
          rethrow;
        default:
          return null;
      }
    }
  }

  Future<List<Assignment>> deadlines() async {
    unawaited(accountChanged());
    final version = _version, now = DateTime.now();
    final staleCutoff = now.subtract(const Duration(days: 30));
    final events = await client.getCalendarEvents(
      now.subtract(const Duration(days: 14)),
      end: now.add(const Duration(days: 180)),
    );
    final result =
        <String, ({String title, String course, DateTime due, String status, String? url})>{};
    final calendarEntries = <(String, String, int)>{};
    // A null value means the student's submission status could not be checked.
    final submissionStatuses = <String, String?>{};
    for (final event in events) {
      final due = _deadlineTime(event['end'] ?? event['start']);
      if (due == null || due.isBefore(staleCutoff)) continue;
      final source = event['itemSourceId']?.toString() ?? '';
      final course = event['calendarName'] as String? ?? '';
      final title = event['title'] as String? ?? '';
      final seconds = due.millisecondsSinceEpoch ~/ 1000;
      final id = source.isNotEmpty ? source : "${event['calendarId'] ?? ''}:$title:$seconds";
      result[id] = (
        title: title,
        course: course,
        due: due,
        status: event['attemptable'] == true && now.isBefore(due) ? 'Open' : 'Closed',
        url: source.isEmpty
            ? null
            : client.session.origin
                .resolve(
                  '/webapps/calendar/launch/attempt/_blackboard.platform.gradebook2.GradableItem-${segment(source)}',
                )
                .toString(),
      );
      calendarEntries.add((course, title, seconds));
    }
    _check(version);
    final courseList = await courses();
    final expiredTerms = <String>{};
    for (final term in _lastTermRows) {
      final id = term['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final available = (term['availability'] as Map?)?['available'];
      final end = _deadlineTime((term['duration'] as Map?)?['end']);
      if (available == 'No' || (end != null && end.isBefore(staleCutoff))) {
        expiredTerms.add(id);
      }
    }
    for (final course in courseList) {
      final termId = _courseTermIds[course.id] ?? '';
      if (termId.isNotEmpty && expiredTerms.contains(termId)) continue;
      _check(version);
      List<Map<String, dynamic>> columns;
      try {
        columns = _rows((await client.getGradebookColumns(course.id, allPages: true))['results']);
      } on CampusRequestException catch (e) {
        if (e.kind == CampusErrorKind.forbidden || e.kind == CampusErrorKind.notFound) continue;
        rethrow;
      }
      Future<Map<String, String>?>? courseStatuses;
      for (final col in columns) {
        final id = col['id'] as String;
        final due = _deadlineTime((col['grading'] as Map?)?['due']);
        final title = (col['name'] ?? col['displayName'] ?? '').toString();
        if (!result.containsKey(id)) {
          if (due == null || due.isBefore(staleCutoff)) continue;
          if (calendarEntries.contains((course.name, title, due.millisecondsSinceEpoch ~/ 1000))) {
            continue;
          }
          final content = col['contentId'] as String?;
          result[id] = (
            title: title,
            course: course.name,
            due: due,
            status: now.isBefore(due) ? 'Open' : 'Closed',
            url: content == null ? null : assignmentUrl(course.id, content).toString(),
          );
        }
        final statuses = await (courseStatuses ??= _deadlineStatuses(course.id));
        if (statuses == null) {
          submissionStatuses[id] = null;
        } else if (statuses[id] case final status?) {
          submissionStatuses[id] = status;
        }
      }
    }
    _check(version);
    return [
      for (final MapEntry(key: id, value: item) in result.entries)
        Assignment(
          id: id,
          platform: 'blackboard',
          title: item.title,
          course: item.course,
          due: item.due,
          status: submissionStatuses.containsKey(id) ? submissionStatuses[id] : item.status,
          url: item.url,
        ),
    ];
  }
}
