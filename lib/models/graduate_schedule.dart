import 'dart:convert';

import 'course_table.dart';

const graduateTableId = 'graduate';
const graduateSemesterPrefix = 'graduate:';

/// The read-only loadKbxx response, reduced to course/calendar fields. It never
/// contains the student profile, login initialization, CSRF tokens or cookies.
class GraduateSchedule {
  GraduateSchedule._(this.data);
  final Map<String, dynamic> data;

  factory GraduateSchedule.fromJson(Map<String, dynamic> raw) {
    for (final key in ['results', 'xkjgList', 'ntkmdList']) {
      if (raw[key] is! List) throw FormatException('研究生课表缺少 $key 列表');
    }
    final periods =
        raw['skjcList'] is String ? jsonDecode(raw['skjcList'] as String) : raw['skjcList'];
    if (periods is! List) throw const FormatException('研究生课表节次格式变化');
    const fields = [
      'XNXQDM',
      'XNXQMC',
      'KCDM',
      'KCMC',
      'BJDM',
      'BJMC',
      'JSXM',
      'RKJS',
      'JASMC',
      'PKSJDD',
      'PKSJDDMS',
      'XQ',
      'KSJCDM',
      'JSJCDM',
      'ZCMC',
      'RQ',
      'rqs',
      'JCFADM',
      'JCFAMC',
      'BYBZ',
    ];
    Map<String, dynamic> select(Map<dynamic, dynamic> row, List<String> keys) => {
          for (final key in keys)
            if (row.containsKey(key)) key: row[key],
        };
    return GraduateSchedule._({
      for (final key in ['results', 'xkjgList', 'ntkmdList'])
        key: (raw[key] as List).map((r) => select(r as Map, fields)).toList(),
      'skjcList':
          periods.map((r) => select(r as Map, ['DM', 'MC', 'KSSJ', 'JSSJ', 'JCFADM'])).toList(),
      'mrjcfadm': raw['mrjcfadm'],
      'currentTerm': raw['currentTerm'],
      'currentTermName': raw['currentTermName'],
      'rqpkjgallList': (raw['rqpkjgallList'] as List? ?? const [])
          .map((r) => select(r as Map, ['bjdm', 'kssj', 'jssj', 'rq', 'rqs']))
          .toList(),
    });
  }

  Map<String, dynamic> toJson() => data;
  List<Map<String, dynamic>> _rows(String key) => (data[key] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get rows => _rows('results');
  String _text(dynamic value) => value?.toString().trim() ?? '';
  String rawTerm(String semesterId) => semesterId.substring(graduateSemesterPrefix.length);
  bool _inTerm(Map<dynamic, dynamic> row, String term) => _text(row['XNXQDM']) == term;

  SemesterInfo get semesterInfo {
    final labels = <String, String>{};
    for (final row in [...rows, ..._rows('xkjgList'), ..._rows('ntkmdList')]) {
      final id = _text(row['XNXQDM']);
      if (id.isNotEmpty) {
        final name = _text(row['XNXQMC']);
        labels[id] = name.isEmpty ? (labels[id] ?? id) : name;
      }
    }
    final current = _text(data['currentTerm']);
    if (current.isNotEmpty) {
      labels[current] =
          _text(data['currentTermName']).isEmpty ? current : _text(data['currentTermName']);
    }
    if (labels.isEmpty) throw const FormatException('学校没有返回可识别的研究生学期');
    final semesters = <String, Map<String, String>>{};
    for (final entry in labels.entries) {
      final match = RegExp(r'(\d{4})\s*[-—–~～]\s*(\d{4})').firstMatch(entry.value);
      final year = match == null ? entry.value : '${match[1]}-${match[2]}';
      final term = ['秋', '春', '暑'].where(entry.value.contains).firstOrNull ?? entry.value;
      // Keep unknown official labels instead of guessing numeric term codes.
      semesters.putIfAbsent(year, () => {})[term] = '$graduateSemesterPrefix${entry.key}';
    }
    final defaultId = labels.containsKey(current) ? current : (labels.keys.toList()..sort()).last;
    return SemesterInfo(
      semesters: semesters,
      defaultSemester: '$graduateSemesterPrefix$defaultId',
      tableId: graduateTableId,
    );
  }

  Map<String, String> schemesFor(String semesterId) {
    final result = <String, String>{};
    for (final row in rows.where((r) => _inTerm(r, rawTerm(semesterId)))) {
      final id = _text(row['JCFADM']);
      if (id.isNotEmpty) {
        result[id] = _text(row['JCFAMC']).isEmpty ? '节次方案 $id' : _text(row['JCFAMC']);
      }
    }
    if (result.isEmpty) {
      final id = _text(data['mrjcfadm']);
      result[id] = '默认节次方案';
    }
    return result;
  }

  String defaultScheme(String semesterId) {
    final schemes = schemesFor(semesterId);
    final preferred = _text(data['mrjcfadm']);
    return schemes.containsKey(preferred) ? preferred : schemes.keys.first;
  }

  List<Map<String, dynamic>> unarrangedFor(String semesterId) {
    final term = rawTerm(semesterId);
    final arranged = rows.where((r) => _inTerm(r, term)).map((r) => _text(r['BJDM'])).toSet();
    final cancelled = cancelledFor(semesterId).map((r) => _text(r['BJDM'])).toSet();
    return _rows('xkjgList')
        .where(
          (r) =>
              _inTerm(r, term) &&
              !arranged.contains(_text(r['BJDM'])) &&
              !cancelled.contains(_text(r['BJDM'])),
        )
        .toList();
  }

  List<Map<String, dynamic>> cancelledFor(String semesterId) => _rows('ntkmdList')
      .where((r) => _text(r['XNXQDM']).isEmpty || _inTerm(r, rawTerm(semesterId)))
      .toList();

  CourseTable tableFor(String semesterId, String scheme, {DateTime? firstMonday}) {
    final periods = <CoursePeriod>[];
    for (final p in _rows('skjcList')) {
      if (_text(p['JCFADM']) != scheme) continue;
      final index = int.tryParse(_text(p['DM']));
      if (index == null || index < 1) throw const FormatException('无法识别研究生节次编号');
      periods.add(
        CoursePeriod(
          index: index,
          timeRange: '${graduateTime(p['KSSJ'])}-${graduateTime(p['JSSJ'])}',
        ),
      );
    }
    periods.sort((a, b) => a.index.compareTo(b.index));
    final cancelled =
        cancelledFor(semesterId).map((r) => _text(r['BJDM'])).where((id) => id.isNotEmpty).toSet();
    final courses = <EamsCourse>[];
    final anchor = firstMonday ?? firstMondayFor(semesterId);
    for (final row in rows.where((r) => _inTerm(r, rawTerm(semesterId)))) {
      if (_text(row['JCFADM']).isNotEmpty && _text(row['JCFADM']) != scheme) continue;
      if (cancelled.contains(_text(row['BJDM']))) continue;
      final day = int.tryParse(_text(row['XQ']));
      final first = int.tryParse(_text(row['KSJCDM']));
      final last = int.tryParse(_text(row['JSJCDM']));
      if (day == null ||
          day < 1 ||
          day > 7 ||
          first == null ||
          last == null ||
          first < 1 ||
          last < first ||
          last > 100) {
        throw const FormatException('研究生课表的星期或节次无法识别');
      }
      final units = [for (var unit = first; unit <= last; unit++) unit];
      if (units.any((n) => !periods.any((p) => p.index == n))) {
        throw const FormatException('研究生课表的排课与节次方案不匹配');
      }
      final dates = _datesFor(row, semesterId);
      final weeksByDay = <int, Set<int>>{};
      if (anchor != null && dates.isNotEmpty) {
        final monday = DateTime.utc(anchor.year, anchor.month, anchor.day);
        for (final date in dates) {
          final offset = date.difference(monday).inDays;
          if (offset < 0 || offset >= 60 * 7) {
            throw const FormatException('课程日期超出学期范围，请核对第 1 周周一');
          }
          weeksByDay.putIfAbsent(date.weekday, () => {}).add(offset ~/ 7 + 1);
        }
      } else if (_text(row['ZCMC']).isNotEmpty) {
        weeksByDay[day] = graduateWeeks(_text(row['ZCMC'])).toSet();
      } else if (dates.isEmpty) {
        throw const FormatException('研究生课程缺少可识别的周次和日期');
      }
      // Date-only records wait for a confirmed first Monday; they must not be
      // invented as weekly recurring courses. The page exposes the date control.
      for (final entry in weeksByDay.entries) {
        final weeks = entry.value.toList()..sort();
        final bits = List.filled(weeks.last + 1, '0');
        for (final week in weeks) {
          bits[week] = '1';
        }
        courses.add(
          EamsCourse(
            name: _text(row['KCMC']),
            classroom: _text(row['JASMC']),
            teachers: _text(row['JSXM']).isEmpty ? _text(row['RKJS']) : _text(row['JSXM']),
            weeks: bits.join(),
            times: {entry.key: units},
          ),
        );
      }
    }
    return CourseTable(periods: periods, courses: courses);
  }

  List<DateTime> _datesFor(Map<String, dynamic> row, String semesterId) {
    var values = <dynamic>[];
    if (_text(row['RQ']).isNotEmpty) {
      values = [row['RQ']];
    } else if (row['rqs'] is List && (row['rqs'] as List).isNotEmpty) {
      values = row['rqs'] as List;
    } else if (_text(row['BJDM']).isNotEmpty &&
        rows
                .where(
                  (r) =>
                      _inTerm(r, rawTerm(semesterId)) &&
                      r['BJDM'] == row['BJDM'] &&
                      _text(r['KSJCDM']) == _text(row['KSJCDM']) &&
                      _text(r['JSJCDM']) == _text(row['JSJCDM']),
                )
                .length ==
            1) {
      final scheme =
          _text(row['JCFADM']).isEmpty ? defaultScheme(semesterId) : _text(row['JCFADM']);
      final periods = _rows('skjcList').where((p) => _text(p['JCFADM']) == scheme);
      final first = periods.where((p) => _text(p['DM']) == _text(row['KSJCDM'])).firstOrNull;
      final last = periods.where((p) => _text(p['DM']) == _text(row['JSJCDM'])).firstOrNull;
      if (first != null && last != null) {
        for (final record in _rows('rqpkjgallList')) {
          if (record['bjdm'] == row['BJDM'] &&
              graduateTime(record['kssj']) == graduateTime(first['KSSJ']) &&
              graduateTime(record['jssj']) == graduateTime(last['JSSJ'])) {
            if (_text(record['rq']).isNotEmpty) values.add(record['rq']);
            if (record['rqs'] is List) values.addAll(record['rqs'] as List);
          }
        }
      }
    }
    return _parseDates(values);
  }

  List<DateTime> _parseDates(List<dynamic> values) => values
      .map((value) {
        final text = _text(value).replaceAll('/', '-').replaceAllMapped(
              RegExp(r'^(\d{4})(\d{2})(\d{2})$'),
              (m) => '${m[1]}-${m[2]}-${m[3]}',
            );
        final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
        if (match == null) throw const FormatException('研究生课程日期无法识别');
        final year = int.parse(match[1]!);
        final month = int.parse(match[2]!);
        final day = int.parse(match[3]!);
        final date = DateTime.utc(year, month, day);
        if (date.year != year || date.month != month || date.day != day) {
          throw const FormatException('研究生课程日期无效');
        }
        return date;
      })
      .toSet()
      .toList()
    ..sort();

  /// Infer a Monday from consistent dated sessions and their teaching weeks.
  /// Ambiguous or conflicting dates keep the local date picker as a fallback.
  DateTime? firstMondayFor(String semesterId) {
    if (_rows('rqpkjgallList').any((r) => _text(r['rq']).isNotEmpty)) {
      return _firstMondayFromCalendarRecords(semesterId);
    }
    final anchors = <DateTime>{};
    for (final row in rows.where((r) => _inTerm(r, rawTerm(semesterId)))) {
      if (_text(row['ZCMC']).isEmpty) continue;
      final dates = _datesFor(row, semesterId);
      final weeks = graduateWeeks(_text(row['ZCMC']));
      if (dates.isEmpty || dates.length != weeks.length) continue;
      final day = int.tryParse(_text(row['XQ']));
      for (var i = 0; i < dates.length; i++) {
        final date = dates[i];
        if (date.weekday != day) return null;
        anchors.add(date.subtract(Duration(days: (weeks[i] - 1) * 7 + date.weekday - 1)));
      }
    }
    if (anchors.length != 1) return null;
    final date = anchors.single;
    return DateTime(date.year, date.month, date.day);
  }

  /// Match all dated class/clock groups against their possible teaching weeks.
  /// Missing holiday sessions are allowed; a partial date range that fits more
  /// than one Monday stays unknown. At least two independent classes must agree.
  DateTime? _firstMondayFromCalendarRecords(String semesterId) {
    final cancelled = cancelledFor(semesterId).map((r) => _text(r['BJDM'])).toSet();
    final groups = <String, List<Map<String, dynamic>>>{};
    String clockKey(String id, dynamic first, dynamic last) =>
        '$id|${graduateTime(first)}|${graduateTime(last)}';
    for (final row in rows.where((r) => _inTerm(r, rawTerm(semesterId)))) {
      final id = _text(row['BJDM']);
      if (id.isEmpty || cancelled.contains(id) || _text(row['ZCMC']).isEmpty) continue;
      final scheme =
          _text(row['JCFADM']).isEmpty ? defaultScheme(semesterId) : _text(row['JCFADM']);
      final periods = _rows('skjcList').where((p) => _text(p['JCFADM']) == scheme);
      final first = periods.where((p) => _text(p['DM']) == _text(row['KSJCDM'])).firstOrNull;
      final last = periods.where((p) => _text(p['DM']) == _text(row['JSJCDM'])).firstOrNull;
      if (first == null || last == null) continue;
      groups.putIfAbsent(clockKey(id, first['KSSJ'], last['JSSJ']), () => []).add(row);
    }
    final dates = <String, List<DateTime>>{};
    for (final record in _rows('rqpkjgallList')) {
      final id = _text(record['bjdm']);
      if (id.isEmpty || cancelled.contains(id)) continue;
      final key = clockKey(id, record['kssj'], record['jssj']);
      if (!groups.containsKey(key)) continue;
      dates.putIfAbsent(key, () => []).addAll(_parseDates([
            if (_text(record['rq']).isNotEmpty) record['rq'],
            if (record['rqs'] is List) ...(record['rqs'] as List),
          ]),);
    }
    Set<DateTime>? candidates;
    final supportingClasses = <String>{};
    for (final entry in dates.entries) {
      Set<DateTime>? groupCandidates;
      for (final date in entry.value.toSet()) {
        final possible = <DateTime>{};
        for (final row in groups[entry.key]!) {
          // A shifted weekday cannot identify its original teaching week.
          if (int.tryParse(_text(row['XQ'])) != date.weekday) continue;
          for (final week in graduateWeeks(_text(row['ZCMC']))) {
            possible.add(date.subtract(Duration(days: (week - 1) * 7 + date.weekday - 1)));
          }
        }
        if (possible.isEmpty) continue;
        groupCandidates =
            groupCandidates == null ? possible : groupCandidates.intersection(possible);
        if (groupCandidates.isEmpty) return null;
      }
      if (groupCandidates == null) continue;
      supportingClasses.add(_text(groups[entry.key]!.first['BJDM']));
      candidates = candidates == null ? groupCandidates : candidates.intersection(groupCandidates);
      if (candidates.isEmpty) return null;
    }
    if (supportingClasses.length < 2 || candidates?.length != 1) return null;
    final monday = candidates!.single;
    return DateTime(monday.year, monday.month, monday.day);
  }
}

String graduateTime(dynamic raw) {
  final value = raw.toString().trim();
  final compact = value.contains(':') ? value.replaceAll(':', '') : value.padLeft(4, '0');
  if (!RegExp(r'^\d{4}$').hasMatch(compact)) throw const FormatException('研究生节次时间无法识别');
  final hour = int.parse(compact.substring(0, 2));
  final minute = int.parse(compact.substring(2));
  if (hour > 23 || minute > 59) throw const FormatException('研究生节次时间无效');
  return '${compact.substring(0, 2)}:${compact.substring(2)}';
}

List<int> graduateWeeks(String raw) {
  final normalized = raw
      .replaceAll(RegExp(r'[\s第]'), '')
      .replaceAll(RegExp('[，、]'), ',')
      .replaceAll(RegExp('[～~—–]'), '-')
      .replaceAllMapped(RegExp(r'[（(](单|双)周?[）)]'), (m) => m[1]!);
  final result = <int>{};
  for (final piece in normalized.split(',')) {
    final match = RegExp(r'^(\d+)(?:-(\d+))?(?:周)?(单|双)?(?:周)?$').firstMatch(piece);
    if (match == null) throw FormatException('无法识别研究生课表周次：$raw');
    final first = int.parse(match[1]!);
    final last = int.parse(match[2] ?? match[1]!);
    if (first < 1 || last < first || last > 60) throw const FormatException('研究生课表周次范围无效');
    for (var week = first; week <= last; week++) {
      if (match[3] == null || (match[3] == '单' ? week.isOdd : week.isEven)) result.add(week);
    }
  }
  if (result.isEmpty) throw const FormatException('研究生课表周次为空');
  return result.toList()..sort();
}
