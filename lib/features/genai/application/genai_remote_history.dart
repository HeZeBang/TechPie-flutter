import 'dart:convert';

import '../domain/genai_agent_contract.dart';
import '../domain/genai_agent_protocol.dart';
import '../domain/genai_context_record.dart';
import '../domain/genai_context_usage.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_remote_record.dart';
import 'genai_chat_service.dart';
import 'genai_conversation_archive.dart';
import 'genai_conversation_turn.dart';
import 'genai_legacy_conversation_import.dart';

/// A disposable projection of GenAI's append-only history. No local archive is
/// consulted. Historical tool records only inform context and prevent replay.
final class GenAiRemoteHistory {
  GenAiRemoteHistory(this.archive);
  final GenAiConversationArchive archive;
}

GenAiRemoteHistory decodeGenAiConversation(String id, List<GenAiSavedTurn> rows) {
  final aliases = _uploadFallbackAliases(rows);
  final turns = <String, GenAiConversationTurn>{};
  final legacy = <GenAiSavedTurn>[];
  final seen = <String>{};
  final explicitlyStopped = <String>{};
  var memory = <String, Object?>{};
  var effects = <String, Object?>{};
  var settings = <String, Object?>{};
  String? title;
  String? leaf;
  DateTime lastMessage = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  void flushLegacy() {
    for (final turn in importGenAiLegacyConversation(legacy)) {
      turn.id = 'legacy-${turns.length}';
      turn.parentId = leaf;
      turns[turn.id] = turn;
      leaf = turn.id;
    }
    legacy.clear();
  }

  void addCall(GenAiConversationTurn turn, GenAiAgentToolCall call) {
    // Missing receipts must never look like unexecuted, freely retryable calls.
    final event = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: turn.agentEvents.length + 1,
      call: call,
      result: {
        'call_id': call.id,
        'name': call.name,
        'ok': false,
        'error': {'code': 'outcome_unknown', 'message': '缺少已保存的工具结果，请先核实状态。'},
      },
    );
    turn.agentEvents[call.id] = event;
    turn.recordAgentActivity(event);
    if (call.name == 'reserve_court' && call.arguments['action'] == 'book') {
      turn.approvalBudget[call.name] = 1;
    }
  }

  for (final row in rows) {
    final extraction = genAiContextExtractionHash(row.prompt);
    if (extraction != null) {
      try {
        final notes = jsonDecode(row.answer);
        if (notes is Map<String, Object?> && notes['items'] is List) memory[extraction] = notes;
      } on FormatException {/* Invalid extraction is re-derived from source. */}
      continue;
    }
    final record = decodeGenAiRemoteRecord(row.prompt);
    if (record == null) {
      legacy.add(row);
      if (row.createdAt != null && row.createdAt!.isAfter(lastMessage)) {
        lastMessage = row.createdAt!;
      }
      continue;
    }
    flushLegacy();
    if (!seen.add(record['step_id']! as String)) continue;
    try {
      if (record['context'] is Map) {
        memory.addAll(Map<String, Object?>.from(record['context']! as Map));
      }
      if (record['mutations'] is Map) {
        effects = {
          'version': 1,
          'effects': {
            ...?effects['effects'] as Map?,
            ...?(record['mutations']! as Map)['effects'] as Map?,
          },
        };
      }
      if (record['title'] is String) title = record['title']! as String;
      for (final raw in record['interrupted'] as List? ?? const []) {
        final stopped = genAiTurnFromArchive(Map<String, Object?>.from(raw as Map));
        // Old clients re-saved misparsed upload rows as interrupted turns.
        // Their canonical exchanges already supply the actual tool outcomes.
        if (aliases.containsKey(stopped.id)) continue;
        stopped.parentId = aliases[stopped.parentId] ?? stopped.parentId;
        stopped.phase = GenAiChatPhase.cancelled;
        for (final event in stopped.agentEvents.values.toList()) {
          if (event.call != null && event.result == null) addCall(stopped, event.call!);
        }
        turns[stopped.id] = stopped;
        explicitlyStopped.add(stopped.id);
      }
      final input = record['input']! as String;
      final source =
          record['turn'] is Map ? Map<String, Object?>.from(record['turn']! as Map) : null;
      final turnId = (source?['id'] ?? record['turn_id'])! as String;
      if (turnId.isEmpty) throw const FormatException('Missing turn ID');
      final turn = turns.putIfAbsent(turnId, () {
        if (source == null) throw const FormatException('Missing original request');
        // Early development records used the export shape; keep them readable.
        return source['kind'] == 'conversation_turn'
            ? genAiTurnFromArchive(source)
            : GenAiConversationTurn.fromRemoteInput(source, input);
      });
      turn.parentId = aliases[turn.parentId] ?? turn.parentId;
      // A later request can carry an explicit stop before the upstream finishes
      // persisting the aborted POST. That late answer must not revive the turn
      // or move the active path back from its already-saved follow-up.
      if (explicitlyStopped.contains(turnId)) continue;
      if (record['approvalBudget'] is Map) {
        final budget = Map<String, int>.from(record['approvalBudget']! as Map);
        for (final entry in budget.entries) {
          if (entry.value > (turn.approvalBudget[entry.key] ?? 0)) {
            turn.approvalBudget[entry.key] = entry.value;
          }
        }
      }
      // A turn can contain multiple model requests. Its latest server step
      // owns the estimate; do not retain an older step's value when absent.
      turn.contextUsage = GenAiContextUsage.fromRecord(record['contextUsage']);
      turn.contextCompacted = turn.contextCompacted || (turn.contextUsage?.compacted ?? false);
      leaf = turnId;
      settings = {
        ...record,
        if (record['aiType'] == null && row.aiType.isNotEmpty) 'aiType': row.aiType,
      };
      if (row.createdAt != null && row.createdAt!.isAfter(lastMessage)) {
        lastMessage = row.createdAt!;
      }
      final result = source == null ? decodeGenAiAgentRecord(input)?.result : null;
      if (result != null && result['call_id'] != null) {
        final previous = turn.agentEvents[result['call_id']];
        if (previous?.call?.name != result['name']) {
          turn.agentStatus = '工具结果缺少对应请求。';
        } else {
          final event = GenAiAgentEvent(
            kind: GenAiAgentEventKind.toolFinished,
            turn: previous!.turn,
            call: previous.call,
            result: result,
          );
          if (previous.call!.name == 'generate_image' &&
              (result['error'] as Map?)?['code'] == 'approval_denied') {
            turn.approvalBudget['generate_image:denied'] = 1;
          }
          turn.agentEvents[result['call_id']! as String] = event;
          turn.recordAgentActivity(event);
          // Version 2 references this already-stored receipt by its execution
          // identities instead of repeating the result in a second ledger.
          final keys = (record['effectKeys'] as List? ?? const []).cast<String>();
          if (keys.any((key) => !key.startsWith('${previous.call!.name}:'))) {
            throw const FormatException('Invalid mutation identity');
          }
          effects = {
            'version': 1,
            'effects': {...?effects['effects'] as Map?, for (final key in keys) key: result},
          };
        }
      }
      if (row.reasoning.isNotEmpty) {
        turn.reasoning += row.reasoning;
        turn.recordAgentActivity(
          GenAiAgentEvent(
            kind: GenAiAgentEventKind.reasoningDelta,
            turn: turn.agentEvents.length + 1,
            text: row.reasoning,
          ),
        );
      }
      final call = decodeGenAiAgentRecord(row.answer)?.call;
      if (turn.isAgent && call != null) {
        addCall(turn, call);
        turn.phase = GenAiChatPhase.interrupted;
      } else {
        final answer = turn.isAgent ? decodeGenAiAgentFinal(row.answer) : row.answer;
        if (answer == null || answer.isEmpty) {
          turn.phase = GenAiChatPhase.interrupted;
        } else {
          turn.answer = answer;
          turn.phase = GenAiChatPhase.completed;
        }
      }
    } catch (_) {
      // A damaged record is visible and breaks context continuity; do not
      // silently supply a seemingly complete history to the model.
      final gap =
          GenAiConversationTurn('', id: 'gap-${turns.length}', parentId: leaf, isHistoryGap: true)
            ..phase = GenAiChatPhase.interrupted;
      turns[gap.id] = gap;
      leaf = gap.id;
    }
  }
  flushLegacy();
  final ledger = Map<String, Object?>.from(effects['effects'] as Map? ?? const {});
  for (final turn in turns.values) {
    for (final event in turn.agentEvents.values) {
      final call = event.call;
      if (call != null &&
          event.result != null &&
          event.result!['reused'] != true &&
          (call.name == 'generate_image' ||
              call.name == 'reserve_court' && call.arguments['action'] == 'book')) {
        ledger[genAiMutationReceiptKey(call, turnId: turn.actionScopeId ?? turn.id)] = event.result;
      }
    }
  }
  effects = {'version': 1, 'effects': ledger};
  final path = <GenAiConversationTurn>[];
  final visited = <String>{};
  while (leaf != null && visited.add(leaf!)) {
    final turn = turns[leaf];
    if (turn == null) {
      path.add(GenAiConversationTurn('', isHistoryGap: true));
      break;
    }
    path.add(turn);
    leaf = turn.parentId;
  }
  final ordered = path.reversed.toList();
  return GenAiRemoteHistory(
    GenAiConversationArchive(
      id: id,
      title: title ?? ordered.firstOrNull?.prompt ?? '新的对话',
      updatedAt: lastMessage,
      lastMessageAt: lastMessage,
      turns: ordered,
      agentEnabled: settings['agent'] as bool? ?? ordered.lastOrNull?.isAgent ?? false,
      thinkingEnabled: settings['thinking'] == true,
      netSearchEnabled: settings['search'] == true,
      modelAiType: settings['aiType'] as String? ?? rows.lastOrNull?.aiType,
      modelRootAiType: settings['rootAiType'] as String?,
      mutations: effects.isEmpty ? const {'version': 1, 'effects': <String, Object?>{}} : effects,
      contextMemory: memory,
    ),
  );
}

/// Reproduce only the old upload-wrapper fallback's IDs. Never infer ancestry
/// from proximity: a mapped row must contain a valid canonical exchange.
Map<String, String> _uploadFallbackAliases(List<GenAiSavedTurn> rows) {
  if (!rows.any((row) => row.prompt.trimLeft().startsWith('【上传文件'))) return const {};
  final aliases = <String, String>{};
  final oldIds = <String>{};
  final pending = <GenAiSavedTurn>[];
  void flush() {
    for (final turn in importGenAiLegacyConversation(pending)) {
      final oldId = 'legacy-${oldIds.length}';
      oldIds.add(oldId);
      final record = decodeGenAiRemoteRecord(turn.prompt);
      final source = record?['turn'];
      final id = source is Map ? source['id'] : record?['turn_id'];
      if (id is String && id.isNotEmpty) aliases[oldId] = id;
    }
    pending.clear();
  }

  for (final row in rows) {
    if (isGenAiContextExtraction(row.prompt)) continue;
    final record = row.prompt.trimLeft().startsWith('<techpie-record')
        ? decodeGenAiRemoteRecord(row.prompt)
        : null;
    if (record == null) {
      pending.add(row);
      continue;
    }
    flush();
    final interrupted = record['interrupted'];
    if (interrupted is List) {
      for (final item in interrupted) {
        if (item is Map && item['id'] is String) oldIds.add(item['id'] as String);
      }
    }
    final source = record['turn'];
    final id = source is Map ? source['id'] : record['turn_id'];
    if (id is String) oldIds.add(id);
  }
  flush();
  return aliases;
}
