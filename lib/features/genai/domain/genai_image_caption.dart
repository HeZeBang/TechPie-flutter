/// A display caption for an image record.
///
/// A non-empty [title] always wins. Otherwise the first punctuation-delimited
/// clause of [prompt] is used so a long prompt does not overflow a gallery
/// tile. The result is capped at roughly 24 display units, where a CJK or other
/// wide character counts as two and a Latin character counts as one: about 12
/// CJK or 24 Latin characters. Whitespace-only input returns an empty string.
String genAiImageCaption(String prompt, {String? title}) {
  final explicit = title?.trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final source = prompt.trim();
  if (source.isEmpty) return '';
  final caption = _firstClause(source).trimRight();
  if (caption.isEmpty) return '';

  final buffer = StringBuffer();
  var width = 0;
  for (final rune in caption.runes) {
    final runeWidth = _displayWidth(rune);
    if (width + runeWidth > _maxCaptionWidth) break;
    buffer.writeCharCode(rune);
    width += runeWidth;
  }
  return buffer.toString().trimRight();
}

const _maxCaptionWidth = 24;
final _clauseEnd = RegExp(r'[。！？；，、：,.!?;:\n\r]');

String _firstClause(String source) {
  final match = _clauseEnd.firstMatch(source);
  return match == null ? source : source.substring(0, match.start);
}

int _displayWidth(int rune) => _isWide(rune) ? 2 : 1;

bool _isWide(int rune) =>
    (rune >= 0x1100 && rune <= 0x115F) ||
    (rune >= 0x2E80 && rune <= 0xA4CF) ||
    (rune >= 0xAC00 && rune <= 0xD7A3) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0xFE30 && rune <= 0xFE4F) ||
    (rune >= 0xFF00 && rune <= 0xFF60) ||
    (rune >= 0xFFE0 && rune <= 0xFFE6) ||
    (rune >= 0x1F300 && rune <= 0x1FAFF) ||
    (rune >= 0x20000 && rune <= 0x3FFFD);
