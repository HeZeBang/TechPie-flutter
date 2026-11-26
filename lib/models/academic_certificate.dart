import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

enum CertificateKind {
  transcript('成绩单', '/eams/teach/grade/transcript/stdPrinterApply'),
  ranking('绩点与排名', '/eams/teach/grade/stat/studentGpaApply'),
  average('平均分证明', '/eams/stdAverageApply');

  const CertificateKind(this.label, this.path);
  final String label, path;
  Uri get entry => Uri.https('eams.shanghaitech.edu.cn', '$path.action');
  String get entity => path.split('/').last;
  bool get usesBlankEditor => this != CertificateKind.ranking;
  String get submitPath =>
      usesBlankEditor ? '$path!save.action' : '$path!apply.action';
}

class CertificateDownload {
  const CertificateDownload(this.label, this.url, this.method, this.fields);
  final String label, url, method;
  final Map<String, String> fields;
}

class AcademicCertificate {
  const AcademicCertificate(this.fields, [this.downloads = const []]);
  final Map<String, String> fields;
  final List<CertificateDownload> downloads;
}

class CertificateField {
  const CertificateField(
    this.name,
    this.label,
    this.value,
    this.options,
    this.required, {
    this.omitWhenEmpty = false,
    this.readOnly = false,
    this.multiline = false,
  });
  final String name, label, value;
  final Map<String, String> options;
  final bool required, omitWhenEmpty, readOnly, multiline;
}

class CertificateForm {
  const CertificateForm(this.action, this.hidden, this.fields);
  final String action;
  final Map<String, String> hidden;
  final List<CertificateField> fields;
  Map<String, String> values(Map<String, String> input) {
    final result = {...hidden};
    for (final f in fields) {
      final value = f.readOnly ? f.value : input[f.name] ?? f.value;
      if ((f.required && value.trim().isEmpty) ||
          (value.isNotEmpty &&
              f.options.isNotEmpty &&
              !f.options.containsKey(value))) {
        throw FormatException('请检查${f.label}');
      }
      if (!f.omitWhenEmpty || value.isNotEmpty) result[f.name] = value;
    }
    return result;
  }
}

Uri? _onEams(CertificateKind kind, String? href) {
  if (href == null || href.isEmpty) return null;
  final target = Uri.tryParse(href);
  if (target == null) return null;
  final uri = kind.entry.resolveUri(target);
  return uri.isScheme('https') &&
          uri.host == kind.entry.host &&
          uri.port == 443 &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

String _cleanLabel(String? raw) =>
    (raw ?? '').trim().replaceAll(RegExp(r'^[\s*]+|[\s*:：]+$'), '');

String _textWithoutControls(dom.Element root) {
  final buf = StringBuffer();
  void walk(dom.Node node) {
    if (node is dom.Text) {
      buf.write(node.text);
      return;
    }
    if (node is dom.Element) {
      if (const {'input', 'select', 'textarea', 'button', 'script', 'style'}
          .contains(node.localName)) {
        return;
      }
      for (final child in node.nodes) {
        walk(child);
      }
    }
  }

  walk(root);
  return _cleanLabel(buf.toString().replaceAll(RegExp(r'\s+'), ' '));
}

String? _labelForId(dom.Document doc, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final l in doc.querySelectorAll('label')) {
    if (l.attributes['for'] == id) {
      final text = _textWithoutControls(l);
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}

String? _wrappingLabel(dom.Element e, dom.Element stopAt) {
  var cur = e.parent;
  while (cur != null && cur != stopAt) {
    if (cur.localName == 'label') {
      final text = _textWithoutControls(cur);
      if (text.isNotEmpty) return text;
    }
    cur = cur.parent;
  }
  return null;
}

String? _tableRowLabel(dom.Element e, dom.Element form) {
  dom.Element? cell;
  var cur = e.parent;
  while (cur != null && cur != form) {
    if (cell == null && (cur.localName == 'td' || cur.localName == 'th')) {
      cell = cur;
    } else if (cur.localName == 'tr' && cell != null) {
      final cells = cur.children
          .where((c) => c.localName == 'td' || c.localName == 'th')
          .toList();
      final idx = cells.indexOf(cell);
      for (var i = idx - 1; i >= 0; i--) {
        final text = _cleanLabel(cells[i].text.replaceAll(RegExp(r'\s+'), ' '));
        if (text.isNotEmpty) return text;
      }
      break;
    }
    cur = cur.parent;
  }
  return null;
}

String? _resolveFieldLabel(dom.Element e, dom.Document doc, dom.Element form) {
  final candidates = [
    _labelForId(doc, e.attributes['id']),
    _wrappingLabel(e, form),
    _cleanLabel(e.attributes['aria-label']),
    _cleanLabel(e.attributes['title']),
    _cleanLabel(e.attributes['placeholder']),
    _tableRowLabel(e, form),
  ];
  for (final candidate in candidates) {
    if (candidate != null && candidate.isNotEmpty) return candidate;
  }
  return null;
}

String _resolveRadioOptionLabel(dom.Element r, dom.Document doc, dom.Element form) {
  final candidates = [
    _labelForId(doc, r.attributes['id']),
    _wrappingLabel(r, form),
    _cleanLabel(r.attributes['aria-label']),
    _cleanLabel(r.attributes['title']),
  ];
  for (final candidate in candidates) {
    if (candidate != null && candidate.isNotEmpty) return candidate;
  }
  final parent = r.parent;
  if (parent != null) {
    final nodes = parent.nodes;
    final idx = nodes.indexOf(r);
    if (idx >= 0) {
      for (var i = idx + 1; i < nodes.length; i++) {
        final next = nodes[i];
        if (next is dom.Element) {
          if (next.localName == 'input') break;
          final t = _cleanLabel(next.text);
          if (t.isNotEmpty) return t;
        } else if (next is dom.Text) {
          final t = _cleanLabel(next.text);
          if (t.isNotEmpty) return t;
        }
      }
    }
  }
  return (r.attributes['value'] ?? '').trim();
}

CertificateForm? parseCertificateForm(CertificateKind kind, String source) {
  final doc = html.parse(source);
  for (final f in doc.querySelectorAll('form[action]')) {
    final action = _onEams(kind, f.attributes['action']);
    final method = f.attributes['method']?.trim().toLowerCase();
    if (action == null ||
        action.path != kind.submitPath ||
        (method != null && method.isNotEmpty && method != 'post')) {
      continue;
    }
    final hidden = <String, String>{};
    final items = <Object>[];
    final names = <String>{};
    final radioGroups = <String, List<dom.Element>>{};
    var unsupported = false;
    for (final e in f.querySelectorAll('input,select,textarea,button')) {
      if (e.attributes.containsKey('disabled')) continue;
      final type = (e.attributes['type'] ?? 'text').toLowerCase();
      if (e.localName == 'button' ||
          (e.localName == 'input' &&
              const {'submit', 'button', 'reset', 'image'}.contains(type))) {
        continue;
      }
      final name = e.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      if (type == 'hidden') {
        if (!names.add(name)) {
          unsupported = true;
          break;
        }
        hidden[name] = e.attributes['value'] ?? '';
        continue;
      }
      if (e.localName == 'input' && type == 'radio') {
        if (names.contains(name)) {
          unsupported = true;
          break;
        }
        final group = radioGroups[name];
        if (group == null) {
          radioGroups[name] = [e];
          items.add(name);
        } else {
          group.add(e);
        }
        continue;
      }
      if (!names.add(name) || radioGroups.containsKey(name)) {
        unsupported = true;
        break;
      }
      // Script-driven fields, uploads and multiple choices use the original form.
      if (e.attributes.containsKey('multiple') ||
          (e.localName == 'input' &&
              !const {'text', 'number', 'checkbox'}.contains(type))) {
        unsupported = true;
        break;
      }
      if (e.localName == 'input' && type == 'checkbox') {
        final label = _resolveFieldLabel(e, doc, f);
        if (label == null || label.isEmpty) {
          unsupported = true;
          break;
        }
        final checkedVal = (e.attributes['value'] ?? '').isNotEmpty
            ? e.attributes['value']!
            : 'on';
        final initial = e.attributes.containsKey('checked') ? checkedVal : '';
        items.add(
          CertificateField(name, label, initial, {
            checkedVal: '是',
            '': '否',
          }, e.attributes.containsKey('required'),),
        );
        continue;
      }
      final transcriptType =
          kind == CertificateKind.transcript && name == 'stdPrinterApply.type';
      final allChoices = e.querySelectorAll('option');
      final enabled = allChoices.where(
        (o) =>
            !o.attributes.containsKey('disabled') &&
            !(o.parent?.localName == 'optgroup' &&
                o.parent!.attributes.containsKey('disabled')),
      );
      final choices = enabled.where(
        (o) => !transcriptType || o.text.trim() != '...',
      );
      String optionValue(dom.Element option) =>
          option.attributes['value'] ?? option.text.trim();
      final options = {for (final o in choices) optionValue(o): o.text.trim()};
      final label = _resolveFieldLabel(e, doc, f);
      if (label == null || label.isEmpty) {
        unsupported = true;
        break;
      }
      final selected =
          allChoices
              .where((o) => o.attributes.containsKey('selected'))
              .lastOrNull ??
          enabled.firstOrNull;
      if (e.localName == 'select' && options.isEmpty) return null;
      final unavailable = selected != null && !choices.contains(selected);
      final initial = e.localName == 'select'
          ? (selected == null || unavailable ? '' : optionValue(selected))
          : e.attributes['value'] ?? e.text.trim();
      items.add(
        CertificateField(
          name,
          label,
          initial,
          options,
          transcriptType || e.attributes.containsKey('required'),
          omitWhenEmpty: unavailable && !options.containsKey(''),
          readOnly: e.attributes.containsKey('readonly'),
          multiline: e.localName == 'textarea',
        ),
      );
    }
    if (unsupported) continue;

    final fields = <CertificateField>[];
    for (final entry in items) {
      if (entry is CertificateField) {
        fields.add(entry);
      } else if (entry is String) {
        final radios = radioGroups[entry]!;
        final options = <String, String>{};
        String? selected;
        for (final r in radios) {
          final val = r.attributes['value'] ?? '';
          if (val.isEmpty) continue;
          options[val] = _resolveRadioOptionLabel(r, doc, f);
          if (r.attributes.containsKey('checked')) selected ??= val;
        }
        if (options.isEmpty) {
          unsupported = true;
          break;
        }
        var label = _tableRowLabel(radios.first, f);
        if (label == null || label.isEmpty) {
          var cur = radios.first.parent;
          while (cur != null && cur != f) {
            if (cur.localName == 'fieldset') {
              final legend = _cleanLabel(cur.querySelector('legend')?.text);
              if (legend.isNotEmpty) {
                label = legend;
                break;
              }
            }
            cur = cur.parent;
          }
        }
        label ??= _cleanLabel(radios.first.attributes['aria-label']);
        if (label.isEmpty) label = entry;
        fields.add(
          CertificateField(
            entry,
            label,
            selected ?? options.keys.first,
            options,
            radios.any((r) => r.attributes.containsKey('required')),
          ),
        );
      }
    }
    if (kind.usesBlankEditor &&
        (hidden['${kind.entity}.id'] != '' ||
            !fields.any((f) => f.name == '${kind.entity}.applyReason'))) {
      continue;
    }
    if (!unsupported && fields.isNotEmpty) {
      return CertificateForm(action.toString(), hidden, fields);
    }
  }
  return null;
}

List<AcademicCertificate> parseCertificates(CertificateKind kind, String source) {
  final doc = html.parse(source);
  const display = {
    '成绩单类型',
    '类型',
    '申请类型',
    '申请时间',
    '申请日期',
    '打印类型',
    '排名范围',
    '绩点选择',
    '绩点',
    '申请结果',
    '审核结果',
    '审核状态',
    '状态',
    '统计时间',
    '结果',
    '平均分',
    '证明类型',
    '学年学期',
    '申请状态',
    '打印状态',
    '申请份数',
    '申请原因',
  };
  final result = <AcademicCertificate>[];
  var recognized = false;
  final onclickActionRegex = RegExp(
    r'''['"]([^'"]*(?:downloadAttachment|departPrint|majorPrint)\.action[^'"]*)['"]''',
  );
  for (final table in doc.querySelectorAll('table')) {
    List<String>? headers;
    for (final tr in table.querySelectorAll('tr')) {
      if (tr.parent != table && tr.parent?.parent != table) continue;
      final cells = tr.children.where((e) => e.localName == 'td' || e.localName == 'th').toList();
      final normalizedHeaders =
          cells.map((e) => e.text.replaceAll(RegExp(r'\s+'), '')).toList();
      if (normalizedHeaders.any(display.contains)) {
        headers = normalizedHeaders;
        recognized = true;
        continue;
      }
      if (headers == null || cells.length < headers.length) continue;
      final text = cells.take(headers.length).map((e) => e.text.trim()).toList();
      final record = Map.fromIterables(headers, text)
        ..removeWhere((k, v) => !display.contains(k) || v.isEmpty);
      if (record.isEmpty) continue;
      final downloads = <CertificateDownload>[];
      final seenKeys = <String>{};

      void addDownload(Uri uri, {bool isLink = true, Map<String, String> baseFields = const {}}) {
        final transcript = kind == CertificateKind.transcript &&
            uri.path == '${kind.path}!downloadAttachment.action';
        final ranking = kind == CertificateKind.ranking &&
            ['departPrint', 'majorPrint'].any((a) => uri.path == '${kind.path}!$a.action');
        if (!transcript && !ranking) return;
        final fields = {...baseFields};
        if (ranking && isLink) fields.addAll(uri.queryParameters);
        final downloadUri = ranking && isLink
            ? uri.replace(query: '')
            : transcript && fields.isNotEmpty
                ? uri.replace(queryParameters: {...uri.queryParameters, ...fields})
                : uri;
        final method = ranking ? 'POST' : 'GET';
        final dedupKey = jsonEncode([
          method,
          downloadUri.toString(),
          fields.keys.toList()..sort(),
          for (final k in fields.keys.toList()..sort()) fields[k],
        ]);
        if (!seenKeys.add(dedupKey)) return;
        downloads.add(
          CertificateDownload(
            transcript
                ? '成绩单 PDF'
                : uri.path.contains('departPrint')
                    ? '院系排名 PDF'
                    : '专业排名 PDF',
            downloadUri.toString(),
            method,
            fields,
          ),
        );
      }

      for (final node in tr.querySelectorAll('a[href],form[action]')) {
        final link = node.localName == 'a';
        final uri = _onEams(kind, node.attributes[link ? 'href' : 'action']);
        if (uri == null) continue;
        final fields = <String, String>{};
        if (!link &&
            node
                .querySelectorAll('input[name]')
                .any((e) => e.attributes['type']?.toLowerCase() != 'hidden')) {
          continue;
        }
        for (final e in node.querySelectorAll('input[name]:not([disabled])')) {
          fields[e.attributes['name']!] = e.attributes['value'] ?? '';
        }
        addDownload(uri, isLink: link, baseFields: fields);
      }
      for (final node in tr.querySelectorAll('[onclick]')) {
        final onclick = node.attributes['onclick'] ?? '';
        for (final m in onclickActionRegex.allMatches(onclick)) {
          final uri = _onEams(kind, m.group(1));
          if (uri != null) addDownload(uri);
        }
      }
      result.add(AcademicCertificate(record, downloads));
    }
  }
  if (!recognized && !RegExp('暂无|无记录|没有.*(?:记录|数据)').hasMatch(doc.body?.text ?? '')) {
    throw const FormatException('教务系统的证明记录格式有变');
  }
  return result;
}
