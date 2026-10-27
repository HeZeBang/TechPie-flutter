import 'dart:convert';

import 'genai_agent_contract.dart';
import 'genai_contract.dart';

const genAiAgentProtocolMarker = 'TECHPIE_AGENT_PROTOCOL_V3';
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
  return '<techpie-agent-$kind version="3" nonce="$nonce">\n'
      '${jsonEncode(value)}\n</techpie-agent-$kind>';
}

/// A complete live decision. Historical records are decoded separately and
/// never reach this execution boundary.
final class GenAiAgentDecision {
  const GenAiAgentDecision({this.call, this.text});
  final GenAiAgentToolCall? call;
  final String? text;
}

String encodeGenAiAgentFinal(String text, {required String nonce}) =>
    _frame('final', {'text': text}, nonce);

GenAiAgentDecision parseGenAiAgentDecision(String response, {required String nonce}) {
  final source = response.trim();
  for (final kind in ['call', 'final']) {
    final prefix = '<techpie-agent-$kind version="3" nonce="$nonce">';
    final suffix = '</techpie-agent-$kind>';
    if (!source.startsWith(prefix) || !source.endsWith(suffix)) continue;
    try {
      final value = _json(source.substring(prefix.length, source.length - suffix.length).trim());
      if (!_noncePattern.hasMatch(nonce)) break;
      if (kind == 'call') return GenAiAgentDecision(call: _call(value));
      if (value is Map<String, Object?> &&
          value.length == 1 &&
          value['text'] is String &&
          (value['text']! as String).trim().isNotEmpty) {
        return GenAiAgentDecision(text: value['text']! as String);
      }
    } on FormatException {
      break;
    }
  }
  throw const GenAiAgentToolException(
    'invalid_agent_response',
    'This response was not accepted; previously completed tools remain completed. '
        'techpie-agent-final version 3 envelope with CURRENT_CALL_NONCE. '
        'Call JSON contains call_id, name, arguments; final JSON contains text. '
        'No prose outside the envelope. A final must answer, clarify, or explain a blocker.',
  );
}

/// Read-only rendering of a saved final; never an execution capability.
String? decodeGenAiAgentFinal(String source) {
  final header = RegExp(r'^<techpie-agent-final version="3" nonce="([a-zA-Z0-9_-]{16,80})">')
      .firstMatch(source.trim());
  if (header == null) return null;
  try {
    return parseGenAiAgentDecision(source, nonce: header.group(1)!).text;
  } catch (_) {
    return null;
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
    if (role == GenAiRole.system || value.length > 4 * 1024 * 1024) {
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

  GenAiMessage get message => GenAiMessage(
        role: role,
        content: content,
        imageUrls: genAiGeneratedImages(result).toList(),
      );

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
        RegExp(r'^```(?:tool_call|tool_response|json)\s*\n?([\s\S]*?)\s*```$').firstMatch(source);
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
    '^<techpie-agent-$kind version="[23]" nonce="([a-zA-Z0-9_-]{16,80})">\\s*([\\s\\S]*?)\\s*</techpie-agent-$kind>\$',
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
              !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(value['call_id']! as String)) ||
      value['name'] != null &&
          (value['name'] is! String ||
              !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(value['name']! as String)) ||
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
      'Use exactly one complete techpie-agent-call version 3 envelope with the CURRENT_CALL_NONCE, '
          'containing call_id, name, and arguments. For a final answer use a techpie-agent-final version 3 envelope containing text.',
    );

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

/// Incremental display decoder. Execution and completion still require the
/// strict whole-response parser; a rejected preview is cleared by the runner.
final class GenAiAgentFinalStream {
  GenAiAgentFinalStream(String nonce)
      : _prefix = RegExp(
          '^\\s*<techpie-agent-final version="3" nonce="$nonce">\\s*\\{\\s*"text"\\s*:\\s*"',
        );
  final RegExp _prefix;
  String _header = '';
  bool _started = false;
  bool _done = false;
  bool _escape = false;
  String? _unicode;
  String _pendingSurrogate = '';

  String add(String chunk) {
    if (_done) return '';
    if (!_started) {
      _header += chunk;
      final match = _prefix.firstMatch(_header);
      if (match == null) {
        // Calls and malformed prose are buffered only for whole-frame validation.
        if (_header.length > 256) {
          _done = true;
          _header = '';
        }
        return '';
      }
      chunk = _header.substring(match.end);
      _header = '';
      _started = true;
    }
    final output = StringBuffer(_pendingSurrogate);
    _pendingSurrogate = '';
    for (final unit in chunk.codeUnits) {
      final c = String.fromCharCode(unit);
      if (_unicode != null) {
        _unicode = '${_unicode!}$c';
        if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(_unicode!)) {
          _done = true;
          break;
        }
        if (_unicode!.length == 4) {
          output.writeCharCode(int.parse(_unicode!, radix: 16));
          _unicode = null;
        }
      } else if (_escape) {
        _escape = false;
        if (c == 'u') {
          _unicode = '';
          continue;
        }
        final decoded = const {
          '"': '"',
          r'\': r'\',
          '/': '/',
          'n': '\n',
          'r': '\r',
          't': '\t',
          'b': '\b',
          'f': '\f',
        }[c];
        if (decoded == null) {
          _done = true;
          break;
        }
        output.write(decoded);
      } else if (c == r'\') {
        _escape = true;
      } else if (c == '"' || unit < 32) {
        _done = true;
        break;
      } else {
        output.write(c);
      }
    }
    var value = output.toString();
    if (value.isNotEmpty &&
        value.codeUnitAt(value.length - 1) >= 0xd800 &&
        value.codeUnitAt(value.length - 1) <= 0xdbff) {
      _pendingSurrogate = value.substring(value.length - 1);
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}

/// Only successful image-tool receipts contribute visual context. Plain model
/// text and failed/pending operations cannot smuggle image URLs into a request.
Iterable<String> genAiGeneratedImages(Map<String, Object?>? receipt) sync* {
  if (receipt?['name'] != 'generate_image' || receipt?['ok'] != true) return;
  final result = receipt?['result'];
  if (result is! Map || result['status'] != 'generated' || result['images'] is! List) return;
  for (final value in result['images'] as List) {
    if (value is! String) continue;
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'genaipic.shanghaitech.edu.cn' &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.path.startsWith('/sys/common/static/')) {
      yield value;
    }
  }
}

/// Recovery identity for one image request, including default-equivalent args.
/// The host-created scope is shared by retry branches, never chosen by the model.
String genAiMutationReceiptKey(GenAiAgentToolCall call, {String? turnId}) {
  if (call.name != 'generate_image' || turnId == null || turnId.isEmpty) {
    return '${call.name}:raw:${genAiCanonicalJson(call.arguments)}';
  }
  final args = <String, Object?>{
    'width': 1024,
    'height': 1024,
    'quality': 'low',
    ...call.arguments,
    if (call.arguments['prompt'] is String) 'prompt': (call.arguments['prompt']! as String).trim(),
  };
  return 'generate_image:turn:${jsonEncode(turnId)}:raw:${genAiCanonicalJson(args)}';
}
