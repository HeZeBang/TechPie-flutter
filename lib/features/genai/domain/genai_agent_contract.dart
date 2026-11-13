import 'dart:convert';

import 'genai_cancellation.dart';
import 'genai_context_usage.dart';
import 'genai_failure.dart';

typedef GenAiAgentPrepare =
    Future<GenAiAgentPreparedTool> Function(
      Map<String, Object?> arguments,
      GenAiAgentToolContext context,
    );

typedef GenAiAgentApproval =
    Future<bool> Function(
      GenAiAgentTool tool,
      GenAiAgentToolCall call,
      GenAiAgentPreparedTool prepared,
    );

/// A closed, application-owned capability. Preparation may read data but must
/// never book, charge, or otherwise mutate state before approval.
final class GenAiAgentTool {
  GenAiAgentTool({
    required this.name,
    required this.description,
    required Map<String, Object?> inputSchema,
    Map<String, Object?>? outputSchema,
    Map<String, Object?> annotations = const {},
    required this.prepare,
    this.maxApprovalsPerRun,
  }) : inputSchema = genAiAgentJsonMap(inputSchema),
       outputSchema = outputSchema == null ? null : genAiAgentJsonMap(outputSchema),
       annotations = genAiAgentJsonMap(annotations) {
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(name) ||
        description.trim().isEmpty ||
        inputSchema['type'] != 'object' ||
        (outputSchema != null && outputSchema['type'] != 'object') ||
        (maxApprovalsPerRun != null && maxApprovalsPerRun! <= 0)) {
      throw ArgumentError('Invalid agent tool definition');
    }
  }

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?>? outputSchema;

  /// Descriptive MCP-style hints only; these never grant execution permission.
  final Map<String, Object?> annotations;
  final GenAiAgentPrepare prepare;

  /// Host policy, never a model argument. Denied requests also consume the
  /// budget; changing call IDs or arguments cannot start a bulk approval loop.
  final int? maxApprovalsPerRun;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
    if (outputSchema != null) 'outputSchema': outputSchema,
    if (annotations.isNotEmpty) 'annotations': annotations,
  };
}

/// MCP-style result envelope, independent of TechPie's durable turn protocol.
/// Both the structured value and its text fallback are immutable snapshots.
final class GenAiToolResult {
  GenAiToolResult({
    List<Map<String, Object?>> content = const [],
    Map<String, Object?>? structuredContent,
    this.isError = false,
  }) : content = List.unmodifiable(content.map(genAiAgentJsonMap)),
       structuredContent = structuredContent == null ? null : genAiAgentJsonMap(structuredContent);

  factory GenAiToolResult.fromValue(Object? value) {
    final data = value is Map<String, Object?> ? value : <String, Object?>{'value': value};
    return GenAiToolResult(
      content: [
        {'type': 'text', 'text': jsonEncode(data)},
      ],
      structuredContent: data,
    );
  }

  final List<Map<String, Object?>> content;
  final Map<String, Object?>? structuredContent;
  final bool isError;

  Map<String, Object?> toJson() => {
    'content': content,
    if (structuredContent != null) 'structuredContent': structuredContent,
    'isError': isError,
  };

  /// Keep existing campus receipts compact and readable by older clients.
  Map<String, Object?> get recordValue {
    final data = structuredContent;
    final onlyFallback =
        content.isEmpty ||
        (content.length == 1 &&
            content.single['type'] == 'text' &&
            content.single['text'] == jsonEncode(data));
    if (data != null && onlyFallback) return data;
    return {if (data != null) 'structuredContent': data, 'content': content};
  }
}

final class GenAiAgentPreparedTool {
  GenAiAgentPreparedTool({
    required Future<Object?> Function() execute,
    this.requiresApproval = false,
    this.onApproved,
    this.summary,
    this.executionTimeout,
    this.effectKey,
    Map<String, Object?> details = const {},
  }) : _execute = execute,
       details = genAiAgentJsonMap(details);

  final Future<Object?> Function() _execute;

  /// Native services can keep returning domain JSON; normalize exactly once at
  /// the execution boundary. No MCP connection or transport is involved.
  Future<GenAiToolResult> execute() async {
    final value = await _execute();
    return value is GenAiToolResult ? value : GenAiToolResult.fromValue(value);
  }

  /// Host notification after the user accepts, before execution starts.
  final void Function()? onApproved;
  final bool requiresApproval;
  final String? summary;
  final Duration? executionTimeout;

  /// Host-derived normalized identity, including expanded defaults, for a
  /// mutation. Never use a model-provided call ID here.
  final String? effectKey;
  final Map<String, Object?> details;
}

final class GenAiAgentToolContext {
  const GenAiAgentToolContext({required this.cancellation, required bool Function() isCurrent})
    : _isCurrent = isCurrent;

  final GenAiCancellation cancellation;
  final bool Function() _isCurrent;

  /// Call immediately before dispatching every request, especially mutations.
  void checkActive() {
    cancellation.throwIfCancelled();
    if (!_isCurrent()) {
      cancellation.cancel(GenAiFailureKind.accountChanged);
      cancellation.throwIfCancelled();
    }
  }
}

final class GenAiAgentToolCall {
  GenAiAgentToolCall({
    required this.id,
    required this.name,
    required Map<String, Object?> arguments,
  }) : arguments = genAiAgentJsonMap(arguments);

  final String id;
  final String name;
  final Map<String, Object?> arguments;

  Map<String, Object?> toJson() => {'call_id': id, 'name': name, 'arguments': arguments};
}

/// Messages are deliberately authored by the adapter, never raw exceptions,
/// credentials, request headers, or server response bodies.
final class GenAiAgentToolException implements Exception {
  const GenAiAgentToolException(this.code, this.message, {this.effectNotDispatched = false});

  /// Only a trusted adapter may assert this, before making any external change.
  /// It permits fresh confirmation in a later user request, never automatic retry.
  final bool effectNotDispatched;
  final String code;
  final String message;
}

final class GenAiAgentToolRegistry {
  GenAiAgentToolRegistry(Iterable<GenAiAgentTool> tools) {
    for (final tool in tools) {
      if (_tools.containsKey(tool.name)) {
        throw ArgumentError('Duplicate agent tool: ${tool.name}');
      }
      _tools[tool.name] = tool;
    }
    if (_tools.length > 32) throw ArgumentError('Too many agent tools');
  }

  final _tools = <String, GenAiAgentTool>{};
  List<GenAiAgentTool> get tools => List.unmodifiable(_tools.values);
  GenAiAgentTool? operator [](String name) => _tools[name];

  void validate(GenAiAgentToolCall call) {
    final tool = _tools[call.name];
    if (tool == null) {
      throw const GenAiAgentToolException('unknown_tool', 'Choose a listed tool.');
    }
    _validate(call.arguments, tool.inputSchema, 'arguments', 0);
  }

  void validateResult(GenAiAgentToolCall call, GenAiToolResult result) {
    final schema = _tools[call.name]?.outputSchema;
    if (schema == null || result.isError) return;
    try {
      _validate(result.structuredContent, schema, 'result', 0);
    } on GenAiAgentToolException {
      throw const GenAiAgentToolException(
        'invalid_tool_result',
        'The tool completed but returned data outside its declared output schema.',
      );
    }
  }

  static Never _invalid(String path, String reason) =>
      throw GenAiAgentToolException('invalid_arguments', '$path $reason');

  static void _validate(Object? value, Map<String, Object?> schema, String path, int depth) {
    if (depth > 12) _invalid(path, 'is too deeply nested.');
    final enumeration = schema['enum'];
    if (enumeration is List && !enumeration.contains(value)) {
      _invalid(path, 'must be one of the listed values.');
    }
    switch (schema['type']) {
      case 'object':
        if (value is! Map<String, Object?>) {
          _invalid(path, 'must be an object.');
        }
        final properties = schema['properties'];
        final fields = properties is Map<String, Object?> ? properties : const <String, Object?>{};
        final required = schema['required'];
        if (required is List) {
          for (final key in required) {
            if (!value.containsKey(key)) _invalid('$path.$key', 'is required.');
          }
        }
        for (final entry in value.entries) {
          final child = fields[entry.key];
          if (child is! Map<String, Object?>) {
            _invalid('$path.${entry.key}', 'is not an allowed argument.');
          }
          _validate(entry.value, child, '$path.${entry.key}', depth + 1);
        }
      case 'array':
        if (value is! List) _invalid(path, 'must be an array.');
        final minimum = schema['minItems'];
        final maximum = schema['maxItems'];
        if (minimum is int && value.length < minimum || maximum is int && value.length > maximum) {
          _invalid(path, 'has an invalid number of items.');
        }
        final items = schema['items'];
        if (items is! Map<String, Object?>) {
          _invalid(path, 'has no item schema.');
        }
        for (var index = 0; index < value.length; index++) {
          _validate(value[index], items, '$path[$index]', depth + 1);
        }
      case 'string':
        if (value is! String) _invalid(path, 'must be a string.');
        final minimum = schema['minLength'];
        final maximum = schema['maxLength'];
        if (minimum is int && value.length < minimum || maximum is int && value.length > maximum) {
          _invalid(path, 'has an invalid length.');
        }
        final pattern = schema['pattern'];
        if (pattern is String && !RegExp(pattern).hasMatch(value)) {
          _invalid(path, 'has an invalid format.');
        }
      case 'integer':
      case 'number':
        if (value is! num || !value.isFinite || schema['type'] == 'integer' && value is! int) {
          _invalid(path, 'must be a finite ${schema['type']}.');
        }
        final minimum = schema['minimum'];
        final maximum = schema['maximum'];
        if (minimum is num && value < minimum || maximum is num && value > maximum) {
          _invalid(path, 'is outside the allowed range.');
        }
      case 'boolean':
        if (value is! bool) _invalid(path, 'must be a boolean.');
      default:
        _invalid(path, 'uses an unsupported schema type.');
    }
  }
}

enum GenAiAgentEventKind {
  modelStarted,
  contextCompacted,
  contextUsage,
  reasoningDelta,
  answerDelta,
  toolProposed,
  approvalRequired,
  toolStarted,
  toolFinished,
  protocolError,
  completed,
  failed,
  cancelled,
}

final class GenAiAgentEvent {
  const GenAiAgentEvent({
    required this.kind,
    required this.turn,
    this.call,
    this.prepared,
    this.result,
    this.text,
    this.failure,
    this.partialText,
    this.contextUsage,
  });

  final GenAiAgentEventKind kind;
  final int turn;
  final GenAiAgentToolCall? call;
  final GenAiAgentPreparedTool? prepared;
  final Map<String, Object?>? result;
  final String? text;
  final GenAiFailure? failure;

  /// Inert, explicitly unverified output retained after format recovery fails.
  final String? partialText;
  final GenAiContextUsage? contextUsage;
}

/// Tool names that can change state outside the app. Kept in one place so the
/// effect warning and the session ledger cannot drift apart.
const genAiMutationToolNames = {'generate_image', 'reserve_court'};

/// Warning classification, name-only on purpose. A finished `reserve_court`
/// receipt may describe an external effect (including an unknown outcome)
/// whatever its arguments say, so this never inspects them.
bool genAiIsMutationToolName(String? name) => name != null && genAiMutationToolNames.contains(name);

/// Ledger classification, which is stricter than the warning: a court tool is
/// only a mutation receipt when it actually books a slot. Read-only
/// `reserve_court` actions stay retryable because they changed nothing.
bool genAiRecordsMutationReceipt(String name, Map<String, Object?> arguments) =>
    name == 'generate_image' || name == 'reserve_court' && arguments['action'] == 'book';

/// Explicit non-execution outcomes must not become cross-request duplicate locks.
/// Recognize the legacy court adapter shape as well as user cancellation.
bool genAiMutationDidNotExecute(Map<String, Object?> receipt) {
  if ((receipt['error'] as Map?)?['code'] == 'approval_denied') return true;
  final value = receipt['result'];
  return receipt['name'] == 'reserve_court' &&
      receipt['ok'] == true &&
      value is Map &&
      value['success'] == false &&
      value['status'] == 'rejected';
}

/// True when a mutation-capable tool finished successfully, or with an unknown
/// outcome that may still have been dispatched. Proposed, pending, rejected,
/// cancelled, and failed events never count as external effects.
bool genAiHasExternalEffect(GenAiAgentEvent event) {
  if (event.kind != GenAiAgentEventKind.toolFinished) return false;
  if (!genAiIsMutationToolName(event.call?.name)) return false;
  final result = event.result;
  if (result == null || genAiMutationDidNotExecute(result)) return false;
  if (result['ok'] == true) return true;
  final error = result['error'];
  return error is Map && error['code'] == 'outcome_unknown';
}

/// Deep immutable JSON snapshots prevent changes during an approval wait.
Map<String, Object?> genAiAgentJsonMap(Map<String, Object?> value) =>
    _freeze(jsonDecode(jsonEncode(value)))! as Map<String, Object?>;

Object? _freeze(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, child) => MapEntry(key, _freeze(child))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

String genAiCanonicalJson(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${genAiCanonicalJson(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(genAiCanonicalJson).join(',')}]';
  return jsonEncode(value);
}
