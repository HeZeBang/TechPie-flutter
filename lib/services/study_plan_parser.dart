import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../models/study_plan.dart';

typedef PlanPages = ({String page, String detail, bool full});

String _normalizeHeader(String raw) => raw.replaceAll(RegExp(r'\s+'), '');

List<String> _expandRowWithRowspans(
  List<Element> cells,
  Map<int, ({String text, int remaining})> rowspans,
) {
  final next = <int, ({String text, int remaining})>{};
  final logical = <String>[];
  var cellIdx = 0;
  var col = 0;

  void consumeCarried() {
    while (rowspans.containsKey(col)) {
      final span = rowspans.remove(col)!;
      logical.add(span.text);
      if (span.remaining > 1) {
        next[col] = (text: span.text, remaining: span.remaining - 1);
      }
      col++;
    }
  }

  while (cellIdx < cells.length) {
    consumeCarried();
    final cell = cells[cellIdx++];
    final text = cell.text.trim();
    final colspan = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
    final rowspan = int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1;
    final spanCols = colspan < 1 ? 1 : colspan;
    for (var k = 0; k < spanCols; k++) {
      final cellText = k == 0 ? text : '';
      logical.add(cellText);
      if (rowspan > 1) {
        next[col] = (text: cellText, remaining: rowspan - 1);
      }
      col++;
    }
  }
  if (rowspans.isNotEmpty) {
    final remainingCols = rowspans.keys.toList()..sort();
    for (final c in remainingCols) {
      while (col < c) {
        logical.add('');
        col++;
      }
      final span = rowspans.remove(c)!;
      logical.add(span.text);
      if (span.remaining > 1) {
        next[col] = (text: span.text, remaining: span.remaining - 1);
      }
      col++;
    }
  }
  rowspans
    ..clear()
    ..addAll(next);
  return logical;
}

StudyPlanSnapshot parseStudyPlan(PlanPages pages) {
  final roots = <PlanCategoryProgress>[];
  final stack = <(int, PlanCategoryProgress)>[];
  double? required, completed;
  var empty = false;
  final codePattern = RegExp(r'^[A-Za-z]{1,10}[- ]?\d[\w.\-]*$');
  for (final source in [pages.page, if (pages.detail.isNotEmpty) pages.detail]) {
    final doc = html.parse(source);
    empty |= RegExp('未绑定|未设置培养|暂无培养|没有培养|未制定培养|无培养方案|没有找到培养')
        .hasMatch(doc.body?.text ?? '');
    for (final table in doc.querySelectorAll('table')) {
      var headers = <String>[];
      var inPlan = false;
      final rowspans = <int, ({String text, int remaining})>{};
      for (final row
          in table
              .querySelectorAll('tr')
              .where((r) => r.parent == table || r.parent?.parent == table)) {
        final cells = row.children
            .where((c) => c.localName == 'td' || c.localName == 'th')
            .toList();
        if (cells.isEmpty || cells.any((c) => c.querySelector('table') != null)) continue;
        final v = cells.map((c) => c.text.trim()).toList();
        final logical = _expandRowWithRowspans(cells, rowspans);
        if (v.first.replaceAll(RegExp(r'\s'), '').contains('要求学分/完成学分/实修学分') && v.length >= 2) {
          final parts = v[1].split('/');
          if (parts.length >= 2) {
            required = double.tryParse(parts[0].trim());
            completed = double.tryParse(parts[1].trim());
          }
          continue;
        }
        final headerRow = logical.map(_normalizeHeader).toList();
        if (headerRow.contains('课程名称') ||
            headerRow.contains('课程代码') ||
            (headerRow.contains('要求学分') && headerRow.contains('完成学分'))) {
          headers = headerRow;
          inPlan = true;
          rowspans.clear();
          continue;
        }
        if (!inPlan) continue;
        String field(List<String> names) {
          final idx = headers.indexWhere(names.contains);
          return idx < 0 || idx >= logical.length ? '' : logical[idx];
        }

        final code = logical.indexWhere(codePattern.hasMatch);
        if (code >= 0 && code + 1 < logical.length) {
          final raw = field(['修读状态', '状态', '是否通过']);
          final remark = field(['备注']);
          final status = _status(raw, remark);
          final requiredFlag = field(['是否必修', '课程性质', '必修']);
          final item = PlanCourseItem(
            logical[code],
            field(['课程名称']).isEmpty ? logical[code + 1] : field(['课程名称']),
            double.tryParse(field(['学分', '要求学分'])),
            field(['建议修读学期', '建议学期', '开课学期', '修读学期']),
            switch (requiredFlag) {
              '必修' || '是' => true,
              '选修' || '否' => false,
              _ => null,
            },
            field(['开课院系', '开课部门', '开课单位']),
            status,
          );
          final category = field(['课程类别', '课程分类', '模块名称']);
          if (category.isNotEmpty &&
              category != logical[code] &&
              (stack.isEmpty || stack.last.$2.name != category)) {
            final existing = roots.where((c) => c.name == category).firstOrNull;
            final group = existing ?? PlanCategoryProgress(category, 0);
            if (existing == null) roots.add(group);
            stack
              ..clear()
              ..add((0, group));
          }
          if (stack.isEmpty) {
            final group = PlanCategoryProgress('课程明细', 0);
            roots.add(group);
            stack.add((0, group));
          }
          if (!stack.last.$2.courses.any((c) => c.code == item.code && c.name == item.name)) {
            stack.last.$2.courses.add(item);
          }
          continue;
        }
        // EAMS uses spanning cells for modules in the same table as courses.
        final name = v.first;
        if (name.isEmpty || name.contains('无记录') || name.contains('暂无记录')) continue;
        final hasCredits =
            v.length >= 4 && v.skip(1).take(3).any((n) => double.tryParse(n) != null);
        if (!hasCredits &&
            cells.first.attributes['colspan'] == null &&
            !row.attributes.containsKey('data-depth')) {
          continue;
        }
        if (name == '合计' || name == '总计') {
          if (v.length > 2) {
            required ??= double.tryParse(v[1]);
            completed ??= double.tryParse(v[2]);
          }
          continue;
        }
        final level = _indent(row, cells.first);
        while (stack.isNotEmpty && stack.last.$1 >= level) {
          stack.removeLast();
        }
        final req = hasCredits ? double.tryParse(v[1]) : null;
        final done = hasCredits ? double.tryParse(v[2]) : null;
        final actual = hasCredits ? double.tryParse(v[3]) : null;
        final state = v.skip(4).join(' ');
        final met = RegExp('未完成|缺|未通过|否').hasMatch(state)
            ? false
            : RegExp('完成|达标|通过|是').hasMatch(state)
            ? true
            : req == null || done == null
            ? null
            : done >= req;
        final group = PlanCategoryProgress(
          name,
          stack.length,
          requiredCredits: req,
          completed: done,
          actual: actual,
          met: met,
        );
        (stack.isEmpty ? roots : stack.last.$2.children).add(group);
        stack.add((level, group));
      }
    }
  }
  if (roots.isEmpty && required == null && !empty) {
    throw const FormatException('无法识别教务系统返回的培养计划');
  }
  return StudyPlanSnapshot(roots, required, completed, DateTime.now());
}

int _indent(Element row, Element cell) {
  final explicit = int.tryParse(row.attributes['data-depth'] ?? '');
  if (explicit != null) return explicit;
  final css = RegExp(r'padding-left:\s*(\d+)').firstMatch(cell.attributes['style'] ?? '');
  if (css != null) return int.parse(css[1]!);
  final section = RegExp(r'^(\d+(?:\.\d+)*)[、.\s]').firstMatch(cell.text.trim());
  if (section != null) return section[1]!.split('.').length - 1;
  return cell.text.length - cell.text.trimLeft().length;
}

PlanCourseStatus _status(String value, String remark) {
  final s = '$value $remark';
  if (RegExp('在读|在修|修读中|正在修读').hasMatch(s)) return PlanCourseStatus.studying;
  if (RegExp('未通过|不及格').hasMatch(s)) return PlanCourseStatus.failed;
  if (RegExp('未修|未完成|否').hasMatch(s)) return PlanCourseStatus.pending;
  if (RegExp('已通过|通过|已完成|是').hasMatch(s)) return PlanCourseStatus.passed;
  return PlanCourseStatus.unknown;
}
