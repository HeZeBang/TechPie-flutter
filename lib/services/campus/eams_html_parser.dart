import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

class EamsHtmlParser {
  static bool isLoginPage(String source) {
    if (source.contains('统一身份认证')) return true;
    if (!source.contains('<') ||
        (!source.contains('execution') && !source.contains('ids.shanghaitech.edu.cn'))) {
      return false;
    }
    final doc = html.parse(source);
    if (doc.querySelector('input[name="execution"]') != null) return true;
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
    final rows = table.querySelectorAll('tr');
    final header = rows.indexWhere(
      (r) =>
          r.parent?.localName == 'thead' ||
          r.querySelector('th') != null ||
          r.classes.contains('gridhead'),
    );
    if (header < 0) return [];
    List<String> cells(Element row) => row.children
        .where((e) => ['td', 'th'].contains(e.localName))
        .map((e) => e.text.trim())
        .toList();
    final names = cells(rows[header]);
    return [
      for (final row in rows.skip(header + 1).map(cells))
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
