import 'dart:convert';

bool _isToolObject(dynamic value) =>
    value is Map &&
    ((value['function'] is Map && (value['function'] as Map).containsKey('name')) ||
        (value.containsKey('name') && value.containsKey('arguments')));

bool looksLikeToolProtocol(String text) =>
    text.contains('<tool_call>') ||
    (RegExp(r'^\s*[\[{]\s*(?:[\[{" ]|$)').hasMatch(text) &&
        RegExp(r'"tool_calls"\s*:|"function"\s*:\s*\{|"name"\s*:\s*"[^"\n]+"\s*,\s*"arguments"\s*:')
            .hasMatch(text));

/// Only missing outer array/wrapper closures may be added. Calls, arguments,
/// strings and comma-separated values must already be complete.
dynamic _repairWrapper(String text, List<String> stack, bool quoted) {
  final shape = stack.join();
  if (quoted || !['[', '{', '{['].contains(shape)) return null;
  try {
    final suffix = stack.reversed.map((c) => c == '[' ? ']' : '}').join();
    final value = jsonDecode(text + suffix);
    final calls = value is Map ? value['tool_calls'] : value;
    if (value is Map && (value.length != 1 || !value.containsKey('tool_calls'))) return null;
    if (calls is! List || calls.isEmpty || !calls.every(_isToolObject)) return null;
    return value;
  } on FormatException {
    return null;
  }
}

/// Parses outer containers atomically, never salvaging a truncated inner call.
/// Validates declared names and object arguments, not full JSON Schema.
List<Map<String, dynamic>> parseGenaiToolCalls(String text, Set<String> allowed, dynamic choice) {
  final values = <dynamic>[];
  final xml = text.contains('<tool_call>');
  final blocks = xml
      ? RegExp(r'<tool_call>\s*([\s\S]*?)\s*</tool_call>')
          .allMatches(text)
          .map((m) => m[1]!)
          .toList()
      : [text];
  if (xml && blocks.length != '<tool_call>'.allMatches(text).length) {
    throw const FormatException('工具调用未完成');
  }
  for (final block in blocks) {
    var cursor = 0;
    while (cursor < block.length) {
      final start = block.indexOf(RegExp(r'[\[{]'), cursor);
      if (start < 0) break;
      final stack = <String>[];
      var quoted = false;
      var escaped = false;
      var end = -1;
      for (var i = start; i < block.length; i++) {
        final c = block[i];
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (c == '\\') {
            escaped = true;
          } else if (c == '"') {
            quoted = false;
          }
          continue;
        }
        if (c == '"') {
          quoted = true;
          continue;
        }
        if (c == '{' || c == '[') stack.add(c);
        if (c == '}' || c == ']') {
          if (stack.isEmpty || (stack.removeLast() == '{' ? c != '}' : c != ']')) break;
          if (stack.isEmpty) {
            end = i + 1;
            break;
          }
        }
      }
      dynamic repaired;
      if (end < 0) {
        if (xml || looksLikeToolProtocol(block.substring(start))) {
          repaired = _repairWrapper(block.substring(start), stack, quoted);
          if (repaired == null) throw const FormatException('工具调用 JSON 未完成');
          end = block.length;
        } else {
          break;
        }
      }
      final segment = block.substring(start, end);
      try {
        final value = repaired ?? jsonDecode(segment);
        if (value is Map && value.containsKey('tool_calls')) {
          if (value['tool_calls'] is! List) throw const FormatException('tool_calls 必须是数组');
          values.addAll(value['tool_calls'] as List);
        } else if (_isToolObject(value) || (xml && value is Map && value.containsKey('name'))) {
          values.add(value);
        } else if (value is List && value.any(_isToolObject)) {
          values.addAll(value);
        } else if (xml) {
          throw const FormatException('工具调用格式不对');
        }
      } on FormatException {
        if (xml || looksLikeToolProtocol(segment)) rethrow;
      }
      cursor = end;
    }
  }
  final calls = <Map<String, dynamic>>[];
  for (final raw in values) {
    if (raw is! Map) throw const FormatException('工具调用必须是对象');
    final function = raw['function'] is Map ? raw['function'] as Map : raw;
    final name = function['name'];
    if (name is! String || !allowed.contains(name)) throw const FormatException('工具名称不在本次请求中');
    dynamic args = function['arguments'] ?? <String, dynamic>{};
    if (args is String) args = jsonDecode(args);
    if (args is! Map<String, dynamic>) throw const FormatException('工具参数必须是 JSON 对象');
    calls.add({
      'id': raw['id'] is String && (raw['id'] as String).isNotEmpty
          ? raw['id']
          : 'call_${DateTime.now().microsecondsSinceEpoch}_${calls.length}',
      'type': 'function',
      'function': {'name': name, 'arguments': jsonEncode(args)},
    });
  }
  final selected = choice is Map
      ? (choice['function'] is Map ? choice['function']['name'] : choice['name'])
      : null;
  if ((choice == 'required' && calls.isEmpty) ||
      (selected != null &&
          (calls.isEmpty || calls.any((c) => c['function']['name'] != selected)))) {
    throw const FormatException('GenAI 未返回指定工具调用');
  }
  return calls;
}

/// Aggregate native tool deltas by index before validating their full arguments.
class GenaiToolAccumulator {
  final _calls = <int, Map<String, dynamic>>{};
  bool get isNotEmpty => _calls.isNotEmpty;
  void add(dynamic fragments) {
    if (fragments == null) return;
    if (fragments is! List) throw const FormatException('工具增量必须是数组');
    for (var position = 0; position < fragments.length; position++) {
      final fragment = fragments[position];
      if (fragment is! Map) throw const FormatException('工具增量格式不对');
      final index = fragment['index'] ?? position;
      if (index is! int || index < 0) throw const FormatException('工具序号不对');
      final call = _calls.putIfAbsent(
        index,
        () => {
          'type': 'function',
          'function': <String, dynamic>{'name': '', 'arguments': ''},
        },
      );
      if (fragment['id'] is String && (fragment['id'] as String).isNotEmpty) {
        call['id'] = fragment['id'];
      }
      final function = fragment['function'];
      if (function is! Map) continue;
      for (final field in ['name', 'arguments']) {
        dynamic value = function[field];
        if (value == null) continue;
        if (field == 'arguments' && value is Map) value = jsonEncode(value);
        if (value is! String) throw const FormatException('工具增量字段格式不对');
        final target = call['function'] as Map<String, dynamic>;
        target[field] = (target[field] as String) + value;
      }
    }
  }

  List<Map<String, dynamic>> result() =>
      [for (final index in (_calls.keys.toList()..sort())) _calls[index]!];
}
