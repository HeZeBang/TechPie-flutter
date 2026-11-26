import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../models/assignment.dart';
import '../../models/course_table.dart';
import 'eams_html_parser.dart';

typedef ScheduleEntry = ({String table, String project, String semester});
typedef _JsArg = ({String value, bool isStringLiteral});
typedef _TaskActivityMatch = ({int start, int end, List<_JsArg> args});

class EamsScheduleParser {
  static ScheduleEntry entry(String source) {
    final doc = html.parse(source);
    String? field(String name) {
      final element = doc.querySelector('[name="$name"]');
      return (element?.localName == 'select'
                  ? element?.querySelector('option[selected]') ?? element?.querySelector('option')
                  : element)
              ?.attributes['value'] ??
          RegExp('addInput\\(\\s*form\\s*,\\s*["\']${RegExp.escape(name)}["\']\\s*,\\s*["\']([^"\']+)')
              .firstMatch(source)
              ?.group(1);
    }

    final table = field('ids');
    if (table == null || table.isEmpty) throw const FormatException('无法读取本科课表编号');
    return (
      table: table,
      project: field('project.id') ?? '1',
      semester: field('semester.id') ??
          RegExp(r'''empty\s*:\s*["']false["']\s*,\s*value\s*:\s*["']([^"']+)''')
              .firstMatch(source)
              ?.group(1) ??
          '',
    );
  }

  static String _normalizeSchoolYear(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').replaceAll('–', '-');

  static SemesterInfo semesters(ScheduleEntry entry, String source) {
    final years = <String, Map<String, String>>{};
    void add(String id, String year, String term) =>
        (years[_normalizeSchoolYear(year)] ??= {})[term] = id;
    for (final e in EamsHtmlParser.options(source).entries) {
      final m = RegExp(r'(\d{4}\s*[-–]\s*\d{4}).*?([秋春暑123])').firstMatch(e.value);
      if (m != null) add(e.key, m[1]!, m[2]!);
    }
    for (final m in RegExp(
      r'''["']?\bid["']?\s*:\s*["']?(\d+)["']?\s*,\s*["']?schoolYear["']?\s*:\s*["']([^"']+)["']\s*,\s*["']?name["']?\s*:\s*["']([^"']+)["']''',
    ).allMatches(source)) {
      add(m[1]!, m[2]!, m[3]!);
    }
    if (years.isEmpty) throw const FormatException('无法读取学期列表');
    return SemesterInfo(semesters: years, defaultSemester: entry.semester, tableId: entry.table);
  }

  static final _activityHead = RegExp(r'\bnew\s+TaskActivity\s*\(');
  static final _teacherDecl = RegExp(r'\bvar\s+(?:act)?teachers\s*=\s*\[(.*?)\]', dotAll: true);
  static final _teacherName = RegExp(r'''["']?name["']?\s*:\s*["']([^"']+)["']''');
  static final _slot = RegExp(r'\bindex\s*=\s*(\d+)\s*\*\s*unitCount\s*\+\s*(\d+)');
  static final _emptyExam = RegExp(r'暂无考试|无考试安排|没有考试');

  static List<_TaskActivityMatch> _extractTaskActivities(String scripts) {
    final matches = <_TaskActivityMatch>[];
    for (final head in _activityHead.allMatches(scripts)) {
      final parsed = _parseCallArgs(scripts, head.end);
      if (parsed == null) continue;
      matches.add((start: head.start, end: parsed.end, args: parsed.args));
    }
    return matches;
  }

  static ({List<_JsArg> args, int end})? _parseCallArgs(String source, int start) {
    final args = <_JsArg>[];
    final buf = StringBuffer();
    var depth = 1;
    String? quote;
    var escaped = false;
    for (var i = start; i < source.length; i++) {
      final ch = source[i];
      if (quote != null) {
        buf.write(ch);
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        buf.write(ch);
      } else if (ch == '(' || ch == '[' || ch == '{') {
        depth++;
        buf.write(ch);
      } else if (ch == ')' || ch == ']' || ch == '}') {
        if (depth == 1 && ch == ')') {
          final tail = buf.toString();
          if (args.isNotEmpty || tail.trim().isNotEmpty) {
            args.add(_decodeJsArg(tail));
          }
          return (args: args, end: i + 1);
        }
        if (depth <= 1) return null;
        depth--;
        buf.write(ch);
      } else if (ch == ',' && depth == 1) {
        args.add(_decodeJsArg(buf.toString()));
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    return null;
  }

  static _JsArg _decodeJsArg(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length >= 2 &&
        ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
            (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
      final inner = trimmed.substring(1, trimmed.length - 1);
      final out = StringBuffer();
      for (var i = 0; i < inner.length; i++) {
        final ch = inner[i];
        if (ch == r'\' && i + 1 < inner.length) {
          final next = inner[++i];
          switch (next) {
            case 'n':
              out.write('\n');
            case 'r':
              out.write('\r');
            case 't':
              out.write('\t');
            default:
              out.write(next);
          }
        } else {
          out.write(ch);
        }
      }
      return (value: out.toString(), isStringLiteral: true);
    }
    if (trimmed == 'null' || trimmed == 'undefined') {
      return (value: '', isStringLiteral: false);
    }
    return (value: trimmed, isStringLiteral: false);
  }

  static int _locateWeekMask(List<_JsArg> args) {
    final shortBits = RegExp(r'^[01]{3,}$');
    final longBits = RegExp(r'^[01]{10,}$');
    if (args.length > 6 && args[6].isStringLiteral && shortBits.hasMatch(args[6].value)) {
      return 6;
    }
    final longIdx = args.indexWhere((a) => a.isStringLiteral && longBits.hasMatch(a.value), 5);
    if (longIdx >= 0) return longIdx;
    return args.indexWhere((a) => a.isStringLiteral && shortBits.hasMatch(a.value), 5);
  }

  static CourseTable timetable(String source) {
    final doc = html.parse(source);
    final periods = <CoursePeriod>[];
    final clock = RegExp(r'(\d{1,2}:\d{2})\s*[-~～]\s*(\d{1,2}:\d{2})');
    for (final e in doc.querySelectorAll('font,th,td')) {
      if (e.querySelector('font,th,td') != null) continue;
      final match = clock.firstMatch(e.text);
      if (match != null) {
        periods.add(CoursePeriod(index: periods.length + 1, timeRange: '${match[1]}-${match[2]}'));
      }
    }
    final scripts = doc.querySelectorAll('script').map((e) => e.text).join('\n');
    final activities = _extractTaskActivities(scripts);
    final courses = <(String, String, String, String), Map<int, Set<int>>>{};
    for (var i = 0; i < activities.length; i++) {
      final activity = activities[i];
      final args = activity.args;
      final mask = _locateWeekMask(args);
      if (mask < 4) throw const FormatException('无法解析上课周次');
      final name = args[mask - 3].value;
      final room = args[mask - 1].value;
      final weeks = args[mask].value;
      final prefix = scripts.substring(i == 0 ? 0 : activities[i - 1].end, activity.start);
      final decl = _teacherDecl.allMatches(prefix).lastOrNull;
      final teachers = decl == null
          ? <String>{}
          : _teacherName.allMatches(decl[1]!).map((m) => m[1]!).toSet();
      if (teachers.isEmpty && mask >= 5 && args[mask - 5].isStringLiteral) {
        final fallbackTeacher = args[mask - 5].value.trim();
        if (fallbackTeacher.isNotEmpty) teachers.add(fallbackTeacher);
      }
      final key = (name, room, teachers.join(','), weeks);
      final times = courses.putIfAbsent(key, () => {});
      final slots = scripts.substring(
        activity.end,
        i + 1 < activities.length ? activities[i + 1].start : scripts.length,
      );
      for (final slot in _slot.allMatches(slots)) {
        (times[int.parse(slot[1]!) + 1] ??= {}).add(int.parse(slot[2]!) + 1);
      }
    }
    if (activities.isEmpty &&
        !scripts.contains('unitCount') &&
        doc.querySelector('#courseTable,.courseTable') == null &&
        !source.contains('暂无课表')) {
      throw const FormatException('无法读取本科课表');
    }
    return CourseTable(
      periods: periods,
      courses: [
        for (final e in courses.entries)
          EamsCourse(
            name: e.key.$1,
            classroom: e.key.$2,
            teachers: e.key.$3,
            weeks: e.key.$4,
            times: e.value.map((day, p) => MapEntry(day, p.toList()..sort())),
          ),
      ],
    );
  }

  static Map<String, String> batches(String source) {
    final doc = html.parse(source);
    final select = doc.querySelector('select[name="examBatch.id"],select#examBatchId');
    if (select == null && !_emptyExam.hasMatch(source)) {
      throw const FormatException('无法读取考试批次');
    }
    return {
      for (final o in select?.querySelectorAll('option[value]') ?? <Element>[])
        if (o.attributes['value']!.isNotEmpty) o.attributes['value']!: o.text.trim(),
    };
  }

  static List<ExamAssignment> exams(String source, String semester, String batch, String label) {
    final grid = html.parse(source).querySelector('table.gridtable');
    if (grid == null) {
      if (_emptyExam.hasMatch(source)) return [];
      throw const FormatException('无法读取考试安排');
    }
    final headers = grid.querySelectorAll('th').map((e) => e.text.trim()).toList();
    final results = <ExamAssignment>[];
    for (final row in grid.querySelectorAll('tr')) {
      final cells = row.children.where((c) => c.localName == 'td').toList();
      if (cells.length < 4) continue;
      Element? cell(List<String> names, [int fallback = -1]) {
        final column = headers.indexWhere(names.contains);
        final index = column >= 0 ? column : fallback;
        return index < 0 || index >= cells.length ? null : cells[index];
      }

      String value(List<String> names, [int fallback = -1]) =>
          cell(names, fallback)?.text.trim() ?? '';
      final name = value(['课程名称', '课程名'], 1);
      final code = value(['课程代码', '课程序号'], 0);
      final type = value(['考试类型'], 2);
      final dateRaw = value(['考试日期', '日期'], headers.isEmpty ? 3 : -1);
      final timeRaw = value(['考试时间', '时间'], headers.isEmpty ? 4 : -1);
      final dateMatch = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(dateRaw) ??
          RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(timeRaw);
      final date = dateMatch == null
          ? null
          : '${dateMatch[1]}-${dateMatch[2]!.padLeft(2, '0')}-${dateMatch[3]!.padLeft(2, '0')}';
      final directTimes = RegExp(r'\d{1,2}:\d{2}').allMatches(timeRaw).toList();
      final times = directTimes.length >= 2
          ? directTimes
          : RegExp(r'\d{1,2}:\d{2}').allMatches(dateRaw).toList();
      if (date == null || times.length < 2) continue; // Undated exams have no deadline to display.
      DateTime? at(RegExpMatch m) => DateTime.tryParse('$date ${m[0]!.padLeft(5, "0")}');
      final start = at(times.first), end = at(times.last);
      if (start == null || end == null) continue;
      final roomCell = cell(['考试地点', '地点', '考场'], headers.isEmpty ? 5 : -1);
      final room = roomCell?.text.trim() ?? '';
      final status = value(['考试情况', '考试状态']);
      final seat = cell(['座位号', '考试座位', '座位', '座号']);
      final href = (seat?.querySelector('a[href]') ?? roomCell?.querySelector('a[href]'))
          ?.attributes['href'];
      final origin = Uri.parse('https://eams.shanghaitech.edu.cn');
      final url = href == null ? null : origin.resolve(href);
      final safe = url != null &&
              url.scheme == 'https' &&
              url.host == origin.host &&
              url.port == 443 &&
              url.userInfo.isEmpty
          ? url
          : null;
      final roomId =
          safe?.queryParameters['examRoom.id'] ?? safe?.queryParameters['examRoomId'] ?? '';
      final seatNo = seat?.text.trim() ?? '';
      results.add(
        ExamAssignment(
          id: '$semester:$batch:${code.isEmpty ? name : code}:$roomId',
          title: '$name $type'.trim(),
          course: [name, room, label, if (seatNo.isNotEmpty) '座位 $seatNo']
              .where((v) => v.isNotEmpty)
              .join(' · '),
          due: start,
          lateDue: end,
          status: status.isEmpty ? null : status,
          url: safe?.toString(),
          semesterId: semester,
          location: room,
          batchName: label,
        ),
      );
    }
    return results;
  }
}
