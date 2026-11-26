import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

class EamsHtmlParser {
  static bool isLoginPage(String source) {
    if (!source.contains('<') ||
        (!source.contains('统一身份认证') &&
            !source.contains('execution') &&
            !source.contains('ids.shanghaitech.edu.cn') &&
            !source.contains('authserver'))) {
      return false;
    }
    final doc = html.parse(source);
    if (doc.querySelector('input[name="execution"]') != null) return true;
    final title = doc.querySelector('title')?.text ?? '';
    if (title.contains('统一身份认证')) return true;
    final hasLoginForm = doc.querySelector(
          'input[type="password"], input[name="username"], #casLoginForm, #pwdFromId',
        ) !=
        null;
    if (hasLoginForm &&
        doc
            .querySelectorAll('h1, h2, h3, .auth_title, title')
            .any((e) => e.text.contains('统一身份认证'))) {
      return true;
    }
    if (doc.querySelector('form[action*="authserver"]') != null && hasLoginForm) {
      return true;
    }
    final redirects = [
      ...doc.querySelectorAll('form[action]').map((e) => e.attributes['action']!),
      ...doc
          .querySelectorAll('meta[http-equiv]')
          .where((e) => e.attributes['http-equiv']!.toLowerCase() == 'refresh')
          .map((e) => e.attributes['content'] ?? ''),
      ...doc.querySelectorAll('script').map((e) => e.text).where((s) => s.contains('location')),
    ];
    return redirects.any(
      (s) => RegExp(r'//ids\.shanghaitech\.edu\.cn(?:[:/]|$)', caseSensitive: false).hasMatch(s),
    );
  }

  static List<Map<String, String>> gridTable(String source) {
    final table = html.parse(source).querySelector('table.gridtable');
    if (table == null) return [];
    final rows = <Element>[];
    for (final child in table.children) {
      if (child.localName == 'tr') {
        rows.add(child);
      } else if (child.localName == 'thead' ||
          child.localName == 'tbody' ||
          child.localName == 'tfoot') {
        rows.addAll(child.children.where((e) => e.localName == 'tr'));
      }
    }
    final header = rows.indexWhere(
      (r) =>
          r.parent?.localName == 'thead' ||
          r.children.any((c) => c.localName == 'th') ||
          r.classes.contains('gridhead'),
    );
    if (header < 0) return [];
    List<String> cells(Element row, {required bool normalizeWhitespace}) => row.children
        .where((e) => e.localName == 'td' || e.localName == 'th')
        .map(
          (e) => normalizeWhitespace
              ? e.text.replaceAll(RegExp(r'\s+'), ' ').trim()
              : e.text.trim(),
        )
        .toList();
    final rawNames = cells(rows[header], normalizeWhitespace: true);
    final seen = <String>{};
    final names = <String>[
      for (var i = 0; i < rawNames.length; i++)
        if (rawNames[i].isEmpty || !seen.add(rawNames[i])) '__col_$i' else rawNames[i],
    ];
    return [
      for (final row in rows.skip(header + 1).map((r) => cells(r, normalizeWhitespace: false)))
        if (row.length == names.length) Map.fromIterables(names, row),
    ];
  }

  static Map<String, String> options(String source, {String? name}) {
    final doc = html.parseFragment(source);
    final selects = doc.querySelectorAll('select');
    final options = name == null
        ? doc.querySelectorAll('option[value]')
        : selects
            .where((s) => s.attributes['name'] == name)
            .expand((s) => s.querySelectorAll('option[value]'));
    return {
      for (final o in options)
        if (o.attributes['value']!.isNotEmpty) o.attributes['value']!: o.text.trim(),
    };
  }

  static Map<String, String> hiddenInputs(String source) => {
        for (final e in html.parse(source).querySelectorAll('input[name]'))
          if (e.attributes['type']?.toLowerCase() == 'hidden')
            e.attributes['name']!: e.attributes['value'] ?? '',
      };
}
