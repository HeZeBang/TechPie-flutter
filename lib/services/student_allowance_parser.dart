import 'package:html/dom.dart';
import 'package:html/parser.dart';

import '../models/student_allowance.dart';

const _invalidReport = FormatException('Unrecognized student allowance table');
const _noRecords = {
  '暂无数据',
  '暂无记录',
  '无数据',
  '无记录',
  '没有查询到数据',
  '没有查询到相关数据',
  '没有符合条件的数据',
  '未查询到相关数据',
};

/// Extracts only the monthly and aggregate amounts from the school's table.
/// Identity metadata precedes the headers; the links and their inline scripts
/// are outside the report contract and are never read or executed.
StudentAllowanceReport parseStudentAllowanceReport(String html) {
  final document = parse(html);
  for (final node in document.querySelectorAll('script,style,template,noscript')) {
    node.remove();
  }

  for (final table in document.querySelectorAll('table')) {
    final rows = <List<Element>>[
      for (final child in table.children)
        if (child.localName == 'tr')
          child.children
        else if (const {'thead', 'tbody', 'tfoot'}.contains(child.localName))
          for (final row in child.children)
            if (row.localName == 'tr') row.children,
    ];
    final headerIndex = rows.indexWhere(
      (row) => _isHeader(row) && _label(row.first) == '发放月份',
    );
    if (headerIndex != -1) return _parseTable(rows, headerIndex);
  }
  if (_isNoRecords(document.body?.text ?? '')) {
    return StudentAllowanceReport(months: const [], total: null);
  }
  // Login prompts, server errors and unfamiliar layouts must not look like
  // a successful query with zero income. Never attach the HTML to the error.
  throw _invalidReport;
}

bool _isHeader(List<Element> row) => row.isNotEmpty && row.every((cell) => cell.localName == 'th');

String _label(Element cell) => cell.text.replaceAll(RegExp(r'\s'), '');

bool _isNoRecords(String text) =>
    _noRecords.contains(text.trim().replaceFirst(RegExp(r'[。！!]$'), ''));

StudentAllowanceReport _parseTable(List<List<Element>> rows, int headerIndex) {
  final header = rows[headerIndex];
  if (header.length < 2 || _label(header.last) != '合计' || headerIndex + 1 >= rows.length) {
    throw _invalidReport;
  }
  final categoryCount = header.length - 2;
  final subheader = rows[headerIndex + 1];
  final totalStart = categoryCount * 3;
  if (!_isHeader(subheader) || subheader.length != totalStart + 4) {
    throw _invalidReport;
  }
  final labels = <String>[];
  for (var i = 0; i < categoryCount; i++) {
    final group = header[i + 1];
    final label = group.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final offset = i * 3;
    if (group.attributes['colspan'] != '3' ||
        label.isEmpty ||
        _label(subheader[offset]) != '应发' ||
        _label(subheader[offset + 1]) != '实发') {
      throw _invalidReport;
    }
    // The observed names are benefit types, not person names. Do not show a
    // long numeric identifier if the upstream headings ever include one.
    labels.add(RegExp(r'\d{6,}').hasMatch(label) ? '津贴类别 ${i + 1}' : label);
  }
  // The source's final colspan doesn't include all four totals. Use the
  // explicit subheader columns, not the declared width of the aggregate group.
  if (_label(subheader[totalStart]) != '应发' ||
      _label(subheader[totalStart + 1]) != '扣款' ||
      _label(subheader[totalStart + 2]) != '扣税' ||
      _label(subheader[totalStart + 3]) != '实发') {
    throw _invalidReport;
  }

  final months = <StudentAllowanceEntry>[];
  StudentAllowanceEntry? total;
  for (final row in rows.skip(headerIndex + 2)) {
    if (row.isEmpty || (row.length == 1 && _isNoRecords(row.first.text))) continue;
    if (row.length != subheader.length + 1 || row.skip(1).any((cell) => cell.localName != 'td')) {
      throw _invalidReport;
    }
    final label = _label(row.first);
    final month = label == '合计' ? null : _readMonth(label);
    final entry = StudentAllowanceEntry(
      month: month,
      categories: [
        for (var i = 0; i < labels.length; i++)
          StudentAllowanceCategory(
            label: labels[i],
            grossFen: _readFen(row[i * 3 + 1]),
            netFen: _readFen(row[i * 3 + 2]),
          ),
      ],
      grossFen: _readFen(row[totalStart + 1]),
      deductionsFen: _readFen(row[totalStart + 2]),
      taxFen: _readFen(row[totalStart + 3]),
      netFen: _readFen(row[totalStart + 4]),
    );
    if (month == null) {
      if (total != null) throw _invalidReport;
      total = entry;
    } else {
      months.add(entry);
    }
  }
  months.sort((a, b) => b.month!.compareTo(a.month!));
  return StudentAllowanceReport(months: months, total: total);
}

final _monthPattern = RegExp(r'^(\d{4})(?:年(\d{1,2})月|-(\d{1,2}))$');

DateTime _readMonth(String label) {
  final match = _monthPattern.firstMatch(label);
  if (match == null) throw _invalidReport;
  final year = int.parse(match[1]!);
  final month = int.parse((match[2] ?? match[3])!);
  if (year < 1 || month < 1 || month > 12) throw _invalidReport;
  return DateTime.utc(year, month);
}

final _amountPattern = RegExp(r'^([+\-−]?)(\d+|\d{1,3}(?:,\d{3})+)(?:\.(\d{1,2}))?$');

int? _readFen(Element cell) {
  final text = cell.text.trim();
  if (text.isEmpty || const {'-', '--', '—'}.contains(text)) return null;
  final match = _amountPattern.firstMatch(text);
  if (match == null) throw _invalidReport;
  final whole = match[2]!.replaceAll(',', '');
  if (whole.length > 12) throw _invalidReport;
  final fen = int.parse(whole) * 100 + int.parse((match[3] ?? '').padRight(2, '0'));
  return match[1] == '-' || match[1] == '−' ? -fen : fen;
}
