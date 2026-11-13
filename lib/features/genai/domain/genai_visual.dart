import 'dart:convert';

/// A parsed `techpie-visual` fence: an optional display title plus the raw
/// self-contained HTML source. The title is plain text, never markup, and only
/// comes from explicit fence metadata; the HTML document's own `<title>` is not
/// consulted for it.
final class GenAiVisual {
  const GenAiVisual({required this.source, this.title});

  /// Parses a fence body and its already-isolated info string. Invalid or
  /// absent metadata is not an error: the source stays renderable and only the
  /// title is unavailable.
  factory GenAiVisual.parse(String source, {String? info}) =>
      GenAiVisual(source: source, title: parseTitle(info));

  /// Fence language marker. Kept here so syntax and domain agree.
  static const language = 'techpie-visual';

  /// Bounds a hostile or accidental label without rejecting a useful one. The
  /// prompt asks for 4-12 Chinese characters; this is a safety ceiling, not a
  /// validation rule.
  static const maxTitleRunes = 80;

  final String source;
  final String? title;

  /// Reads only a non-empty string `title` from an optional JSON object. Any
  /// other shape, malformed JSON or empty value is ignored.
  static String? parseTitle(String? info) {
    final candidate = info?.trim();
    if (candidate == null || candidate.isEmpty || !candidate.startsWith('{')) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(candidate);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final title = decoded['title'];
    if (title is! String) return null;
    final normalized = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    final runes = normalized.runes.toList();
    return runes.length <= maxTitleRunes
        ? normalized
        : '${String.fromCharCodes(runes.take(maxTitleRunes))}…';
  }
}
