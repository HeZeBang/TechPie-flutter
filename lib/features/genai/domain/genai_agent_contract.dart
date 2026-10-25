import 'dart:convert';

import 'genai_cancellation.dart';
import 'genai_context_usage.dart';
import 'genai_contract.dart';
import 'genai_failure.dart';

typedef GenAiAgentPrepare = Future<GenAiAgentPreparedTool> Function(
  Map<String, Object?> arguments,
  GenAiAgentToolContext context,
);

typedef GenAiAgentApproval = Future<bool> Function(
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
    required Map<String, Object?> parameters,
    required this.prepare,
    this.maxApprovalsPerRun,
  }) : parameters = genAiAgentJsonMap(parameters) {
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(name) ||
        description.trim().isEmpty ||
        parameters['type'] != 'object' ||
        (maxApprovalsPerRun != null && maxApprovalsPerRun! <= 0)) {
      throw ArgumentError('Invalid agent tool definition');
    }
  }

  final String name;
  final String description;
  final Map<String, Object?> parameters;
  final GenAiAgentPrepare prepare;

  /// Host policy, never a model argument. Denied requests also consume the
  /// budget; changing call IDs or arguments cannot start a bulk approval loop.
  final int? maxApprovalsPerRun;

  Map<String, Object?> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}

final class GenAiAgentPreparedTool {
  GenAiAgentPreparedTool({
    required this.execute,
    this.requiresApproval = false,
    this.summary,
    this.executionTimeout,
    this.effectKey,
    Map<String, Object?> details = const {},
  }) : details = genAiAgentJsonMap(details);

  final Future<Object?> Function() execute;
  final bool requiresApproval;
  final String? summary;
  final Duration? executionTimeout;

  /// Host-derived normalized identity, including expanded defaults, for a
  /// mutation. Never use a model-provided call ID here.
  final String? effectKey;
  final Map<String, Object?> details;
}

final class GenAiAgentToolContext {
  const GenAiAgentToolContext({
    required this.cancellation,
    required bool Function() isCurrent,
  }) : _isCurrent = isCurrent;

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

  Map<String, Object?> toJson() => {
        'call_id': id,
        'name': name,
        'arguments': arguments,
      };
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
      throw const GenAiAgentToolException(
        'unknown_tool',
        'Choose a listed tool.',
      );
    }
    _validate(call.arguments, tool.parameters, 'arguments', 0);
  }

  static Never _invalid(String path, String reason) =>
      throw GenAiAgentToolException('invalid_arguments', '$path $reason');

  static void _validate(
    Object? value,
    Map<String, Object?> schema,
    String path,
    int depth,
  ) {
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
    this.contextUsage,
    this.history = const [],
  });

  final GenAiAgentEventKind kind;
  final int turn;
  final GenAiAgentToolCall? call;
  final GenAiAgentPreparedTool? prepared;
  final Map<String, Object?>? result;
  final String? text;
  final GenAiFailure? failure;
  final GenAiContextUsage? contextUsage;
  final List<GenAiMessage> history;
}

/// Deep immutable JSON snapshots prevent changes during an approval wait.
Map<String, Object?> genAiAgentJsonMap(Map<String, Object?> value) =>
    _freeze(jsonDecode(jsonEncode(value)))! as Map<String, Object?>;

Object? _freeze(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, Object?>.unmodifiable(
      value.map(
        (key, child) => MapEntry(key, _freeze(child)),
      ),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}
