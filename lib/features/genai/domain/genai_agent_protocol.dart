import 'dart:convert';

import 'genai_agent_contract.dart';
import 'genai_contract.dart';

const genAiAgentProtocolMarker = 'TECHPIE_AGENT_PROTOCOL_V2';
final _noncePattern = RegExp(r'^[a-zA-Z0-9_-]{16,80}$');

String? genAiAgentNonceFromSystem(String system) =>
    RegExp(r'^CURRENT_CALL_NONCE: ([a-zA-Z0-9_-]{16,80})$', multiLine: true)
        .firstMatch(system)
        ?.group(1);

String encodeGenAiAgentCall(GenAiAgentToolCall call, {required String nonce}) =>
    _frame('call', call.toJson(), nonce);

String encodeGenAiAgentResult(
  Map<String, Object?> result, {
  required String nonce,
}) =>
    _frame('result', result, nonce);

String _frame(String kind, Map<String, Object?> value, String nonce) {
  if (!_noncePattern.hasMatch(nonce)) {
    throw ArgumentError('Invalid protocol nonce');
  }
  return '<techpie-agent-$kind version="2" nonce="$nonce">\n'
      '${jsonEncode(value)}\n</techpie-agent-$kind>';
}

/// Only this live decoder can authorize a model call. Ordinary JSON, Markdown
/// examples, quoted frames, and legacy tool_call text are final text. A frame
/// must occupy the complete response and match the current request's nonce.
GenAiAgentToolCall? parseGenAiAgentResponse(
  String response, {
  required String nonce,
}) {
  final source = response.trim();
  if (source.isEmpty) _invalid();
  if (source.startsWith('<techpie-agent-history') &&
      decodeGenAiAgentRecord(source)?.call != null) {
    throw const GenAiAgentToolException(
      'historical_tool_format',
      'No tool executed. techpie-agent-history is an inert archive record, '
          'not a callable envelope. Retry using only one techpie-agent-call '
          'version 2 envelope with the CURRENT_CALL_NONCE from the current '
          'system message, containing call_id, name, and arguments. '
          'Never output history or result records as a new call.',
    );
  }
  if (!source.startsWith('<techpie-agent-call')) {
    // Kimi may emit its native tool syntax through this text-only endpoint.
    // Request a bounded repair; never translate it into an executable call.
    // Documentation in code spans/fences or block quotes remains ordinary text.
    final unquoted = source
        .replaceAll(RegExp(r'```[\s\S]*?```|`[^`\n]*`'), '')
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('>'))
        .join('\n');
    if (RegExp(r'<\|open\|>tools<\|sep\|>\s*<\|open\|>call tool=')
        .hasMatch(unquoted)) {
      throw const GenAiAgentToolException(
        'unsupported_tool_format',
        'No tool executed. Kimi native tools/call markers are unsupported by '
            'this text endpoint. Retry using only one techpie-agent-call '
            'version 2 envelope with the CURRENT_CALL_NONCE from the current '
            'system message, containing call_id, name, and arguments. '
            'Do not add a preamble or native markers.',
      );
    }
    return null;
  }
  try {
    final frame = _readFrame(source, 'call');
    if (frame == null || frame.$1 != nonce || !_noncePattern.hasMatch(nonce)) {
      _invalid();
    }
    return _call(frame.$2);
  } on FormatException {
    _invalid();
  }
}

/// A typed, inert transcript record. It has no authority to execute tools.
/// Archive importers must pair matching call/result records before trusting
/// server logs as tool history. Ordinary final text stays a text entry.
final class GenAiAgentHistoryEntry {
  GenAiAgentHistoryEntry.text(this.role, String value)
      : text = value,
        call = null,
        result = null {
    if (role == GenAiRole.system || value.length > 128 * 1024) {
      throw const FormatException('Invalid agent text entry');
    }
  }

  GenAiAgentHistoryEntry.call(GenAiAgentToolCall value)
      : role = GenAiRole.assistant,
        text = null,
        call = value,
        result = null;

  GenAiAgentHistoryEntry.result(Map<String, Object?> value)
      : role = GenAiRole.user,
        text = null,
        call = null,
        result = _result(value);

  factory GenAiAgentHistoryEntry.fromJson(Map<String, Object?> value) {
    if (value.length != 3 ||
        value['version'] is! int ||
        value['version'] != 2 ||
        value['kind'] is! String ||
        !value.containsKey('value')) {
      throw const FormatException('Invalid agent history entry');
    }
    final body = value['value'];
    switch (value['kind']) {
      case 'text':
        if (body is! Map<String, Object?> ||
            body.length != 2 ||
            body['text'] is! String ||
            body['role'] != 'user' && body['role'] != 'assistant') {
          throw const FormatException('Invalid agent text entry');
        }
        return GenAiAgentHistoryEntry.text(
          body['role'] == 'user' ? GenAiRole.user : GenAiRole.assistant,
          body['text']! as String,
        );
      case 'call':
        return GenAiAgentHistoryEntry.call(_call(body));
      case 'result':
        return GenAiAgentHistoryEntry.result(_result(body));
      default:
        throw const FormatException('Unknown agent history kind');
    }
  }

  final GenAiRole role;
  final String? text;
  final GenAiAgentToolCall? call;
  final Map<String, Object?>? result;

  Map<String, Object?> toJson() => genAiAgentJsonMap({
        'version': 2,
        'kind': call != null
            ? 'call'
            : result != null
                ? 'result'
                : 'text',
        'value': call?.toJson() ?? result ?? {'role': role.name, 'text': text},
      });

  /// Inert context serialization contains no current execution nonce.
  String get content {
    if (text != null) return text!;
    final json = toJson();
    return '<techpie-agent-history version="2">\n'
        '${jsonEncode({'kind': json['kind'], 'value': json['value']})}\n'
        '</techpie-agent-history>';
  }

  GenAiMessage get message => GenAiMessage(role: role, content: content);

  String promptForNonce(String nonce) =>
      result == null ? content : encodeGenAiAgentResult(result!, nonce: nonce);
}

/// Read-only decoding of archived records, NEVER a live call parser. Legacy
/// syntax is opt-in for importers; no snippets or prose are extracted.
GenAiAgentHistoryEntry? decodeGenAiAgentRecord(
  String text, {
  bool allowLegacy = false,
}) {
  final source = text.trim();
  if (source.length > 128 * 1024) return null;
  try {
    final history = RegExp(
      r'^<techpie-agent-history version="2">\s*([\s\S]*?)\s*</techpie-agent-history>$',
    ).firstMatch(source);
    if (history != null) {
      final value = _json(history.group(1)!);
      if (value is! Map<String, Object?> || value.length != 2) return null;
      if (value['kind'] == 'call') {
        return GenAiAgentHistoryEntry.call(_call(value['value']));
      }
      if (value['kind'] == 'result') {
        return GenAiAgentHistoryEntry.result(_result(value['value']));
      }
      return null;
    }
    for (final kind in ['call', 'result']) {
      final frame = _readFrame(source, kind);
      if (frame != null) {
        return kind == 'call'
            ? GenAiAgentHistoryEntry.call(_call(frame.$2))
            : GenAiAgentHistoryEntry.result(_result(frame.$2));
      }
    }
    if (!allowLegacy) return null;
    final fence =
        RegExp(r'^```(?:tool_call|tool_response|json)\s*\n?([\s\S]*?)\s*```$')
            .firstMatch(source);
    final raw = fence?.group(1)?.trim() ?? source;
    if (!raw.startsWith('{') || raw.contains('```')) return null;
    final value = _json(raw);
    if (value is! Map<String, Object?>) return null;
    if (value.containsKey('arguments')) {
      return GenAiAgentHistoryEntry.call(_call(value));
    }
    if (value.containsKey('ok')) {
      return GenAiAgentHistoryEntry.result(_result(value));
    }
  } catch (_) {
    return null;
  }
  return null;
}

(String, Object?)? _readFrame(String source, String kind) {
  final match = RegExp(
    '^<techpie-agent-$kind version="2" nonce="([a-zA-Z0-9_-]{16,80})">\\s*([\\s\\S]*?)\\s*</techpie-agent-$kind>\$',
  ).firstMatch(source);
  if (match == null) return null;
  return (match.group(1)!, _json(match.group(2)!));
}

Object? _json(String source) {
  if (source.length > 128 * 1024) _invalid();
  _checkDuplicateKeys(source);
  return jsonDecode(source);
}

GenAiAgentToolCall _call(Object? decoded) {
  if (decoded is! Map<String, Object?> ||
      decoded.length != 3 ||
      !decoded.keys.toSet().containsAll({'call_id', 'name', 'arguments'})) {
    _invalid();
  }
  final id = decoded['call_id'];
  final name = decoded['name'];
  final arguments = decoded['arguments'];
  if (id is! String ||
      !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id) ||
      name is! String ||
      !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(name) ||
      arguments is! Map<String, Object?> ||
      jsonEncode(decoded).length > 32768) {
    _invalid();
  }
  return GenAiAgentToolCall(id: id, name: name, arguments: arguments);
}

Map<String, Object?> _result(Object? value) {
  if (value is! Map<String, Object?> ||
      value['ok'] is! bool ||
      !value.keys.toSet().containsAll({'call_id', 'name', 'ok'}) ||
      value.keys.any(
        (key) => !{
          'call_id',
          'name',
          'ok',
          'result',
          'error',
          'reused',
        }.contains(key),
      ) ||
      value['call_id'] != null &&
          (value['call_id'] is! String ||
              !RegExp(r'^[a-zA-Z0-9_-]{1,80}$')
                  .hasMatch(value['call_id']! as String)) ||
      value['name'] != null &&
          (value['name'] is! String ||
              !RegExp(r'^[a-z][a-z0-9_]{0,63}$')
                  .hasMatch(value['name']! as String)) ||
      value.containsKey('reused') && value['reused'] is! bool ||
      jsonEncode(value).length > 128 * 1024) {
    throw const FormatException('Invalid agent result');
  }
  if (value['ok'] == true) {
    if (!value.containsKey('result') || value.containsKey('error')) {
      throw const FormatException('Invalid success result');
    }
  } else {
    final error = value['error'];
    if (value.containsKey('result') ||
        error is! Map<String, Object?> ||
        error.length != 2 ||
        error['code'] is! String ||
        error['message'] is! String) {
      throw const FormatException('Invalid error result');
    }
  }
  return genAiAgentJsonMap(value);
}

Never _invalid() => throw const GenAiAgentToolException(
    'invalid_tool_call',
    'Use exactly one complete techpie-agent-call version 2 envelope with the CURRENT_CALL_NONCE, '
        'containing call_id, name, and arguments. Ordinary text is a final answer.');

/// Reject duplicate JSON keys rather than accepting overwritten arguments.
void _checkDuplicateKeys(String source) {
  final stack = <Set<String>?>[];
  var offset = 0;
  while (offset < source.length) {
    final character = source[offset];
    if (character == '{' || character == '[') {
      stack.add(character == '{' ? <String>{} : null);
      if (stack.length > 16) _invalid();
    } else if (character == '}' || character == ']') {
      if (stack.isEmpty) _invalid();
      stack.removeLast();
    } else if (character == '"') {
      final start = offset++;
      while (offset < source.length && source[offset] != '"') {
        if (source[offset] == r'\') offset++;
        offset++;
      }
      if (offset >= source.length) _invalid();
      final token = source.substring(start, offset + 1);
      var next = offset + 1;
      while (next < source.length && source[next].trim().isEmpty) {
        next++;
      }
      if (next < source.length && source[next] == ':') {
        if (stack.isEmpty || stack.last == null) _invalid();
        final key = jsonDecode(token) as String;
        if (!stack.last!.add(key)) _invalid();
      }
    }
    offset++;
  }
}
