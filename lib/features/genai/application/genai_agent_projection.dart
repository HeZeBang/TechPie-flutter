import 'dart:convert';

import '../domain/genai_agent_contract.dart';
import '../domain/genai_agent_protocol.dart';
import '../domain/genai_context_source.dart';
import '../domain/genai_contract.dart';

/// Canonical entries remain complete for UI/recovery/retrieval. Only past wire
/// context is shortened. Primary receipts must be saved in chatInfo; retrieved
/// excerpts can instead reference their existing, content-addressed source records.
GenAiMessage genAiAgentContextMessage(
  GenAiAgentHistoryEntry entry,
  int budget, {
  bool includeImages = true,
}) {
  final original = entry.message;
  final result = entry.result;
  if (result == null || original.content.length <= budget || result['ok'] != true) {
    return includeImages ? original : GenAiMessage(role: original.role, content: original.content);
  }
  final recordId = genAiContextSourceId(original);
  final text = jsonEncode(result['result']);
  final characters = text.runes.toList();
  GenAiAgentHistoryEntry project(int count) => GenAiAgentHistoryEntry.result({
        ...result,
        'result': {
          'kind': 'techpie_tool_result_reference_v1',
          'record_id': recordId,
          'characters': characters.length,
          if (count > 0) 'preview': String.fromCharCodes(characters.take(count)),
          'partial': true,
          'read_with': 'read_conversation_records',
        },
      });
  // JSON escaping also consumes the wire budget. Never split a Unicode scalar.
  var low = 0;
  var high = characters.length;
  while (low < high) {
    final middle = (low + high + 1) ~/ 2;
    if (project(middle).content.length <= budget) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  final projected = project(low);

  return GenAiMessage(
    role: original.role,
    content: projected.content,
    imageUrls: includeImages ? original.imageUrls : const [],
  );
}

/// Execution success does not depend on how much evidence fits in model context.
Map<String, Object?> genAiToolReceipt(GenAiAgentToolCall call, GenAiToolResult result) {
  if (result.isError) {
    final message = result.structuredContent?['message'] ??
        result.content
            .where((b) => b['type'] == 'text')
            .map((b) => b['text'])
            .whereType<String>()
            .join('\n');
    return genAiToolError(
      call,
      result.structuredContent?['code'] is String
          ? result.structuredContent!['code']! as String
          : 'tool_error',
      message is String && message.isNotEmpty ? message : 'The tool failed.',
    );
  }
  return genAiAgentJsonMap(
    {'call_id': call.id, 'name': call.name, 'ok': true, 'result': result.recordValue},
  );
}

Map<String, Object?> genAiToolError(GenAiAgentToolCall? call, String code, String message) =>
    genAiAgentJsonMap({
      'call_id': call?.id,
      'name': call?.name,
      'ok': false,
      'error': {'code': code, 'message': message},
    });

final genAiVisualGuideTool = GenAiAgentTool(
  name: 'get_visual_guide',
  description:
      'Read the host authoring guide before creating or revising an interactive visual. Reuse it while available in context.',
  inputSchema: const {
    'type': 'object',
    'properties': <String, Object?>{},
    'additionalProperties': false,
  },
  prepare: (_, context) async => GenAiAgentPreparedTool(
    execute: () async {
      context.checkActive();
      // A compact receipt recovers the selection; constant instructions are injected.
      return {'capability': 'inline_visuals'};
    },
  ),
);

/// Retrieval copies evidence already saved in this conversation. Persist only
/// exact source slices; the current model step still receives the full receipt
/// in transient context. Never compact primary tool outcomes this way.
Map<String, Object?> genAiCompactRetrievedReceipt(
  Map<String, Object?> receipt,
  Iterable<GenAiMessage> sources,
) {
  if (receipt['ok'] != true || !genAiHistoryToolNames.contains(receipt['name'])) return receipt;
  final index = {for (final source in sources) genAiContextSourceId(source): source.content};
  final decoded = <String, List<int>>{};
  Object? compact(Object? value) {
    if (value is List) return value.map(compact).toList();
    if (value is! Map) return value;
    final source = index[value['record_id']];
    final offset = value['offset'];
    final text = value['text'];
    if (source != null && offset is int && text is String && offset >= 0) {
      final runes = decoded.putIfAbsent(value['record_id'] as String, () => source.runes.toList());
      final length = text.runes.length;
      if (offset + length <= runes.length &&
          String.fromCharCodes(runes.sublist(offset, offset + length)) == text) {
        return <String, Object?>{
          for (final entry in value.entries)
            if (entry.key != 'text') entry.key as String: entry.value,
          'text_ref': {'kind': 'techpie_excerpt_v1', 'length': length},
        };
      }
    }
    return {for (final entry in value.entries) entry.key as String: compact(entry.value)};
  }

  return {...receipt, 'result': compact(receipt['result'])};
}

/// Expand only content-addressed slices from existing school records. Missing
/// or modified sources are a history gap, never silently substituted evidence.
Map<String, Object?> genAiRestoreRetrievedReceipt(
  Map<String, Object?> receipt,
  Iterable<GenAiMessage> sources,
) {
  if (receipt['ok'] != true || !genAiHistoryToolNames.contains(receipt['name'])) return receipt;
  final index = {for (final source in sources) genAiContextSourceId(source): source.content};
  final decoded = <String, List<int>>{};
  Object? restore(Object? value) {
    if (value is List) return value.map(restore).toList();
    if (value is! Map) return value;
    final ref = value['text_ref'];
    if (ref is Map && ref['kind'] == 'techpie_excerpt_v1') {
      final source = index[value['record_id']];
      final offset = value['offset'];
      final length = ref['length'];
      if (source == null || offset is! int || length is! int || offset < 0 || length < 0) {
        throw const FormatException('Missing retrieval source');
      }
      final runes = decoded.putIfAbsent(value['record_id'] as String, () => source.runes.toList());
      if (offset + length > runes.length) throw const FormatException('Invalid retrieval slice');
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key != 'text_ref') entry.key as String: entry.value,
        'text': String.fromCharCodes(runes.sublist(offset, offset + length)),
      };
    }
    return {for (final entry in value.entries) entry.key as String: restore(entry.value)};
  }

  return {...receipt, 'result': restore(receipt['result'])};
}
