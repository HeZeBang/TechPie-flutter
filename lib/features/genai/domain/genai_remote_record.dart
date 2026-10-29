import 'dart:convert';

/// Portable records in chatInfo, the field actually persisted by GenAI.
/// This framing conveys structure, not trust or permission to execute tools.
const _open = '<techpie-record version="2">';
const _legacyOpen = '<techpie-record version="1">';
const _close = '</techpie-record>';

/// Defaults and redundant identities are omitted on the wire, not in the
/// application model. Keep descriptive keys and opaque user/tool payloads.
String encodeGenAiRemoteRecord(Map<String, Object?> record) {
  final compact = Map<String, Object?>.from(record)
    ..remove('kind')
    ..remove('rootAiType')
    ..remove('thinking');
  final source = compact['turn'];
  if (source is Map && source['kind'] != 'conversation_turn') {
    final turn = Map<String, Object?>.from(source);
    if (turn['actionScopeId'] == turn['id']) turn.remove('actionScopeId');
    if (turn['isAgent'] == false) turn.remove('isAgent');
    turn.removeWhere(
      (key, value) =>
          value == null || value is List && value.isEmpty || value is Map && value.isEmpty,
    );
    compact['turn'] = turn;
    if (compact['turn_id'] == turn['id']) compact.remove('turn_id');
  }
  // Mode comes from the original turn, including continuation steps.
  if (source != null || compact['turn_id'] != null) compact.remove('agent');
  if (compact['search'] == false) compact.remove('search');
  final mutations = compact['mutations'];
  if (mutations is Map && mutations['effects'] is Map && (mutations['effects'] as Map).isEmpty) {
    compact.remove('mutations');
  }
  compact.removeWhere(
    (key, value) =>
        value == null || value is List && value.isEmpty || value is Map && value.isEmpty,
  );
  return '$_open\n${jsonEncode(compact)}\n$_close';
}

Map<String, Object?>? decodeGenAiRemoteRecord(String text) {
  var source = text.trim();
  while (source.startsWith('【上传文件：') || source.startsWith('【上传文件:')) {
    final end = source.indexOf('】');
    if (end < 0 || source.substring(0, end).contains('\n')) return null;
    source = source.substring(end + 1).trimLeft();
  }
  final compact = source.startsWith(_open);
  final open = compact ? _open : _legacyOpen;
  if (!source.startsWith(open) || !source.endsWith(_close)) return null;
  try {
    final value = jsonDecode(source.substring(open.length, source.length - _close.length));
    if (value is! Map<String, Object?> ||
        value['step_id'] is! String ||
        (value['step_id']! as String).isEmpty ||
        (!compact && value['kind'] != 'exchange')) {
      return null;
    }
    if (compact) {
      value['kind'] = 'exchange';
      final turn = value['turn'];
      if (turn is Map<String, Object?> && turn['kind'] != 'conversation_turn') {
        turn.putIfAbsent('isAgent', () => false);
      }
    }
    return value;
  } on FormatException {
    return null;
  }
}
