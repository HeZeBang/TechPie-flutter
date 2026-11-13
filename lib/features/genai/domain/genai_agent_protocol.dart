import 'dart:convert';

import 'genai_agent_contract.dart';
import 'genai_contract.dart';

const genAiAgentProtocolMarker = 'TECHPIE_AGENT_PROTOCOL_V5';

/// The final system guide carries the response contract once per exchange.
String genAiAgentResponseContract(String nonce) =>
    '''CURRENT_CALL_NONCE: $nonce
Choose one response:
Tool: <techpie-call nonce="$nonce">{"name":"listed_tool","arguments":{}}</techpie-call>
Answer or clarification: ordinary Markdown. When quoting protocol syntax or action-shaped JSON, use <techpie-final nonce="$nonce">Markdown</techpie-final> so examples stay inert.
Executable calls require the exact current nonce and one listed tool; no surrounding prose, code fences, native function-call syntax or invented IDs. Wait for the result before continuing. If a tool is needed, call it instead of ending with a promise to act.''';

final _noncePattern = RegExp(r'^[a-zA-Z0-9_-]{16,80}$');

String? genAiAgentNonceFromSystem(String system) => RegExp(
  r'^CURRENT_CALL_NONCE: ([a-zA-Z0-9_-]{16,80})$',
  multiLine: true,
).firstMatch(system)?.group(1);

String encodeGenAiAgentCall(GenAiAgentToolCall call, {required String nonce}) =>
    _frame('call', call.toJson(), nonce);

String encodeGenAiAgentResult(Map<String, Object?> result, {required String nonce}) =>
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

/// Version 4 removes model-authored call IDs and JSON escaping of final prose.
String encodeGenAiAgentFinal(String text, {required String nonce}) =>
    '<techpie-final nonce="$nonce">\n$text\n</techpie-final>';

String encodeGenAiCompactCall(
  String name,
  Map<String, Object?> arguments, {
  required String nonce,
}) =>
    '<techpie-call nonce="$nonce">\n'
    '${jsonEncode({'name': name, 'arguments': arguments})}\n</techpie-call>';

/// Accept only an entire frame, optionally wrapped in one Markdown fence.
/// Formatting normalization never searches prose for executable snippets.
String _unfence(String source) {
  final text = source.trim();
  final fence = RegExp(r'^```(?:xml|json|text)?[ \t]*\r?\n([\s\S]*)\r?\n```$').firstMatch(text);
  return fence == null ? text : fence.group(1)!.trim();
}

({String kind, String nonce, String body, bool legacy})? _decisionFrame(String source) {
  final match = RegExp(
    r'^<(techpie-(?:agent-)?(?:call|final))\s+([^<>]+)>([\s\S]*)</\1\s*>$',
  ).firstMatch(_unfence(source));
  if (match == null) {
    // A provider-confirmed end of response can terminate a final answer. This
    // normalization never closes tool calls, guesses a nonce, or extracts calls
    // from prose. A partial closing tag or a second envelope still needs repair.
    final open = RegExp(r'^<techpie-final\s+([^<>]+)>([\s\S]*)$').firstMatch(_unfence(source));
    if (open == null) return null;
    final header = _decisionHeader('techpie-final', open[1]!);
    final body = open[2]!.trim();
    if (header == null || RegExp(r'</?techpie-').hasMatch(body)) return null;
    return (kind: 'final', nonce: header.nonce, body: body, legacy: false);
  }
  final header = _decisionHeader(match.group(1)!, match.group(2)!);
  if (header == null) return null;
  return (
    kind: header.kind,
    nonce: header.nonce,
    body: match.group(3)!.trim(),
    legacy: header.legacy,
  );
}

({String kind, String nonce, bool legacy})? _decisionHeader(String tag, String attributes) {
  final values = <String, String>{};
  final attribute = RegExp(r'''([a-z_]+)\s*=\s*(["'])([^"']*)\2''');
  var end = 0;
  for (final item in attribute.allMatches(attributes)) {
    if (attributes.substring(end, item.start).trim().isNotEmpty ||
        values.containsKey(item.group(1))) {
      return null;
    }
    values[item.group(1)!] = item.group(3)!;
    end = item.end;
  }
  final legacy = tag.startsWith('techpie-agent-');
  if (attributes.substring(end).trim().isNotEmpty ||
      values.length != (legacy ? 2 : 1) ||
      legacy && values['version'] != '3' ||
      !_noncePattern.hasMatch(values['nonce'] ?? '')) {
    return null;
  }
  return (kind: tag.endsWith('-call') ? 'call' : 'final', nonce: values['nonce']!, legacy: legacy);
}

GenAiAgentDecision parseGenAiAgentDecision(
  String response, {
  required String nonce,
  bool allowPlain = true,
}) => (GenAiAgentFinalStream(nonce, allowPlain: allowPlain)..add(response)).finish();

GenAiAgentDecision _completeDecision(String response, String nonce, {required bool allowPlain}) {
  final frame = _decisionFrame(response);
  if (frame != null && frame.nonce != nonce) {
    throw const GenAiAgentToolException(
      'wrong_nonce',
      'Use CURRENT_CALL_NONCE, not an identity copied from history.',
    );
  }
  if (frame == null) {
    if (RegExp(r'<\|(?:open|tool_call)|"tool_calls"\s*:').hasMatch(response)) {
      throw const GenAiAgentToolException(
        'native_tool_format',
        'Native function-call syntax is not supported by this text endpoint. '
            'Rewrite the intended call using techpie-call with name and arguments. '
            'No tool executed from this response; previously completed tools remain completed.',
      );
    }
    if (allowPlain && _isPlainAnswer(response)) {
      return GenAiAgentDecision(text: response.trim());
    }
    throw const GenAiAgentToolException(
      'invalid_agent_response',
      'Use ordinary Markdown for the answer, or one complete current-nonce tool call with no surrounding prose. '
          'Previously completed tools remain completed.',
    );
  }
  if (frame.kind == 'final' && !frame.legacy) {
    if (frame.body.isEmpty) {
      throw const GenAiAgentToolException('empty_answer', 'The final answer is empty.');
    }
    return GenAiAgentDecision(text: frame.body);
  }
  Object? value;
  try {
    value = _json(frame.body);
  } on FormatException {
    throw const GenAiAgentToolException(
      'invalid_json',
      'Invalid JSON body. Use double-quoted keys and strings, with no trailing commas.',
    );
  }
  if (frame.kind == 'call') {
    if (!frame.legacy) {
      if (value is! Map<String, Object?> ||
          value.length != 2 ||
          !value.keys.toSet().containsAll({'name', 'arguments'})) {
        _invalid();
      }
      value = {'call_id': nonce, ...value};
    }
    return GenAiAgentDecision(call: _call(value));
  }
  if (value is Map<String, Object?> &&
      value.length == 1 &&
      value['text'] is String &&
      (value['text']! as String).trim().isNotEmpty) {
    return GenAiAgentDecision(text: value['text']! as String);
  }
  throw const GenAiAgentToolException('invalid_final', 'Expected a nonempty final answer.');
}

/// Plain text has no execution authority. Keep suspected control output on the
/// recovery path; never reinterpret a malformed call as a successful answer.
/// Explicit final envelopes can still quote protocol examples or contain JSON.
bool _isPlainAnswer(String source) {
  final text = _unfence(source);
  if (text.isEmpty ||
      RegExp(
        r'</?techpie-(?!visual\b)|</?(?:tool_call|function_calls|invoke)\b|<\||\|>|```(?:tool_call|tool_response)\b',
        caseSensitive: false,
      ).hasMatch(text) ||
      RegExp(r'"(?:tool_calls|function_call)"\s*:').hasMatch(text)) {
    return false;
  }
  // Unframed JSON with action keys is ambiguous, including truncated JSON.
  if (RegExp(r'^[{\[]').hasMatch(text) &&
      RegExp(r'"(?:name|arguments|function|tool|recipient)"\s*:').hasMatch(text)) {
    return false;
  }
  return true;
}

/// Preserve a rejected candidate without executing its visual/code blocks.
String genAiUnverifiedAgentSource(String source) {
  var fence = '```';
  while (source.contains(fence)) {
    fence += '`';
  }
  return '${fence}text\n$source\n$fence';
}

/// Read-only rendering of saved finals, including previous protocol versions.
String? decodeGenAiAgentFinal(String source, {bool allowPlain = false}) {
  final frame = _decisionFrame(source);
  if (frame == null) return allowPlain && _isPlainAnswer(source) ? source.trim() : null;
  if (frame.kind != 'final') return null;
  try {
    return parseGenAiAgentDecision(source, nonce: frame.nonce).text;
  } catch (_) {
    return null;
  }
}

/// A typed, inert transcript record. It has no authority to execute tools.
/// Archive importers must pair matching call/result records before trusting
/// server logs as tool history. Ordinary final text stays a text entry.
final class GenAiAgentHistoryEntry {
  GenAiAgentHistoryEntry.text(this.role, String value) : text = value, call = null, result = null {
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
    return '<techpie-history>\n'
        '${jsonEncode(call != null ? {'call': call!.toJson()} : {'result': result})}\n'
        '</techpie-history>';
  }

  GenAiMessage get message =>
      GenAiMessage(role: role, content: content, imageUrls: genAiGeneratedImages(result).toList());
}

/// Read-only decoding of archived records, NEVER a live call parser. Legacy
/// syntax is opt-in for importers; no snippets or prose are extracted.
GenAiAgentHistoryEntry? decodeGenAiAgentRecord(String text, {bool allowLegacy = false}) {
  final source = text.trim();
  if (source.length > 128 * 1024) return null;
  try {
    final compact = RegExp(
      r'^<techpie-history>\s*([\s\S]*?)\s*</techpie-history>$',
    ).firstMatch(source);
    if (compact != null) {
      final value = _json(compact.group(1)!);
      if (value is! Map<String, Object?> || value.length != 1) return null;
      if (value.containsKey('call')) return GenAiAgentHistoryEntry.call(_call(value['call']));
      if (value.containsKey('result')) {
        return GenAiAgentHistoryEntry.result(_result(value['result']));
      }
      return null;
    }
    final decision = _decisionFrame(source);
    if (decision?.kind == 'call') {
      return GenAiAgentHistoryEntry.call(
        parseGenAiAgentDecision(source, nonce: decision!.nonce).call!,
      );
    }
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
    final fence = RegExp(
      r'^```(?:tool_call|tool_response|json)\s*\n?([\s\S]*?)\s*```$',
    ).firstMatch(source);
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
  final decoded = jsonDecode(source);
  _checkDuplicateKeys(source);
  return decoded;
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
        (key) => !{'call_id', 'name', 'ok', 'result', 'error', 'reused'}.contains(key),
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
  'Call body must contain only name (a listed tool) and arguments (a JSON object). ',
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

/// Stream ordinary Markdown while withholding a possibly split closing tag.
/// Only whole-response validation commits the answer or authorizes execution.
final class GenAiAgentFinalStream {
  GenAiAgentFinalStream(this.nonce, {this.allowPlain = true});
  final bool allowPlain;
  final String nonce;
  final _source = StringBuffer();
  String _buffer = '';
  bool _started = false;
  bool _plain = false;
  bool _ignored = false;
  bool _fenced = false;
  _LegacyFinalStream? _legacy;

  String get source => _source.toString();

  /// The same normalization and header grammar govern preview and commitment.
  /// A preview is provisional; callers must discard it on validation failure.
  GenAiAgentDecision finish() => _completeDecision(source, nonce, allowPlain: allowPlain);

  String add(String chunk) {
    _source.write(chunk);
    if (_ignored) return '';
    if (_plain) return chunk;
    if (_legacy != null) return _legacy!.add(chunk);
    _buffer += chunk;
    if (!_started) {
      _buffer = _buffer.trimLeft();
      // Stream ordinary prose immediately. Ambiguous markup/JSON prefixes stay
      // buffered until the complete response can be classified safely.
      if (allowPlain &&
          !_fenced &&
          _buffer.isNotEmpty &&
          !const ['<', '`', '{', '['].contains(_buffer[0])) {
        _plain = true;
        final value = _buffer;
        _buffer = '';
        return value;
      }
      if (!_fenced && _buffer.startsWith('`')) {
        final newline = _buffer.indexOf('\n');
        if (newline < 0) return '';
        if (!RegExp(r'^```(?:xml|json|text)?[ \t]*\r?$').hasMatch(_buffer.substring(0, newline))) {
          if (allowPlain) {
            _plain = true;
            final value = _buffer;
            _buffer = '';
            return value;
          }
          _ignored = true;
          return '';
        }
        _fenced = true;
        _buffer = _buffer.substring(newline + 1).trimLeft();
      }
      final end = _buffer.indexOf('>');
      if (end < 0) return '';
      final match = RegExp(
        r'^<(techpie-(?:agent-)?(?:call|final))\s+([^<>]+)>$',
      ).firstMatch(_buffer.substring(0, end + 1));
      final header = match == null ? null : _decisionHeader(match[1]!, match[2]!);
      if (header == null || header.kind != 'final' || header.nonce != nonce) {
        _ignored = true;
        return '';
      }
      _started = true;
      _buffer = _buffer.substring(end + 1);
      if (header.legacy) {
        _legacy = _LegacyFinalStream();
        return _legacy!.add(_buffer);
      }
    }
    // A literal closing marker may appear in an explanation/code example.
    // Hold a possible terminal suffix, then release it if more body follows.
    final closing = RegExp(r'</techpie-final\s*>\s*(?:`{1,3}\s*)?$').firstMatch(_buffer);
    int keepFrom;
    if (closing != null) {
      keepFrom = closing.start;
    } else {
      const close = '</techpie-final';
      var keep = 0;
      for (var i = 1; i <= close.length && i <= _buffer.length; i++) {
        if (_buffer.endsWith(close.substring(0, i))) keep = i;
      }
      final spaced = RegExp(r'</techpie-final\s*$').firstMatch(_buffer);
      keepFrom = spaced?.start ?? _buffer.length - keep;
    }
    final value = _buffer.substring(0, keepFrom);
    _buffer = _buffer.substring(keepFrom);
    return value;
  }
}

/// Incremental display decoder. Execution and completion still require the
/// strict whole-response parser; a rejected preview is cleared by the runner.
final class _LegacyFinalStream {
  _LegacyFinalStream();
  static final _prefix = RegExp(r'^\s*\{\s*"text"\s*:\s*"');
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
