import 'dart:convert';

/// Portable records in chatInfo, the field actually persisted by GenAI.
/// This framing conveys structure, not trust or permission to execute tools.
const _open = '<techpie-record version="1">';
const _close = '</techpie-record>';

String encodeGenAiRemoteRecord(Map<String, Object?> record) =>
    '$_open\n${jsonEncode(record)}\n$_close';

Map<String, Object?>? decodeGenAiRemoteRecord(String text) {
  var source = text.trim();
  while (source.startsWith('【上传文件：') || source.startsWith('【上传文件:')) {
    final end = source.indexOf('】');
    if (end < 0 || source.substring(0, end).contains('\n')) return null;
    source = source.substring(end + 1).trimLeft();
  }
  if (!source.startsWith(_open) || !source.endsWith(_close)) return null;
  try {
    final value = jsonDecode(source.substring(_open.length, source.length - _close.length));
    if (value is! Map<String, Object?> ||
        value['step_id'] is! String ||
        (value['step_id']! as String).isEmpty ||
        value['kind'] != 'exchange') {
      return null;
    }
    return value;
  } on FormatException {
    return null;
  }
}
