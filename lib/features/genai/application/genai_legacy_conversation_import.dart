import '../domain/genai_agent_contract.dart';
import '../domain/genai_agent_protocol.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_chat_service.dart';
import 'genai_conversation_turn.dart';

/// Recovers display-only tasks from the server's append-only model-step log.
/// Local typed archives take precedence. Imported text never restores approvals,
/// mutation receipts, or executable agent history.
List<GenAiConversationTurn> importGenAiLegacyConversation(
  List<GenAiSavedTurn> rows,
) {
  final turns = <GenAiConversationTurn>[];
  GenAiConversationTurn? active;
  GenAiAgentToolCall? pending;
  var step = 0;

  void appendEvent(GenAiAgentToolCall call, Map<String, Object?> result) {
    final turn = active!;
    var key = call.id;
    var duplicate = 1;
    while (turn.agentEvents.containsKey(key)) {
      key = '${call.id}-${duplicate++}';
    }
    turn.agentEvents[key] = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: ++step,
      call: call,
      result: result,
    );
  }

  void finishInterrupted() {
    final turn = active;
    if (turn == null) return;
    if (pending case final call?) {
      appendEvent(
        call,
        genAiAgentJsonMap({
          'call_id': call.id,
          'name': call.name,
          'ok': false,
          'error': {
            'code': 'outcome_unknown',
            'message': '保存的记录缺少工具结果，无法确认是否执行。请先查看相关记录。',
          },
        }),
      );
    }
    turn.phase = GenAiChatPhase.interrupted;
    turn.agentStatus = '历史记录不完整，无法确认最后一步的结果。请先核实，勿重复执行。';
    active = null;
    pending = null;
  }

  void consumeAnswer(GenAiSavedTurn row) {
    final turn = active!;
    if (row.reasoning.isNotEmpty) {
      turn.reasoning = [turn.reasoning, row.reasoning]
          .where((part) => part.isNotEmpty)
          .join('\n');
    }
    final answerCall = _call(row.answer);
    if (answerCall != null) {
      pending = answerCall;
      return;
    }
    if (row.answer.trim().isEmpty || _protocolEnvelope(row.answer)) {
      pending = null;
      finishInterrupted();
      return;
    }
    turn.answer = row.answer;
    turn.phase = turn.agentStatus.isEmpty
        ? GenAiChatPhase.completed
        : GenAiChatPhase.interrupted;
    active = null;
    pending = null;
  }

  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    if (row.isHistoryGap) {
      finishInterrupted();
      turns.add(
        GenAiConversationTurn('', isHistoryGap: true)
          ..phase = GenAiChatPhase.interrupted
          ..agentStatus = '服务器返回的一条历史记录无法读取，部分上下文可能缺失。',
      );
      continue;
    }
    final response = _result(row.prompt);
    if (active != null && pending != null) {
      if (_matches(pending!, response)) {
        appendEvent(pending!, response!);
        pending = null;
        consumeAnswer(row);
        continue;
      }
      finishInterrupted();
    }

    // An exact receipt with a missing preceding call is an incomplete recovery,
    // never a user prompt or authority to execute the tool again.
    if (response != null) {
      active = GenAiConversationTurn('恢复的工具记录', isAgent: true)
        ..agentStatus = '记录缺少对应请求，仅显示已保存结果；不会恢复或执行操作。';
      turns.add(active!);
      step = 0;
      final id = response['call_id'];
      final name = response['name'];
      if (id is String && name is String) {
        appendEvent(
          GenAiAgentToolCall(id: id, name: name, arguments: const {}),
          response,
        );
      }
      consumeAnswer(row);
      continue;
    }

    final call = _call(row.answer);
    final nextResult =
        index + 1 < rows.length ? _result(rows[index + 1].prompt) : null;
    // A standalone code example is still ordinary text. Only a matching,
    // adjacent call/result pair establishes an old tool-assisted trajectory.
    if (call != null &&
        (_matches(call, nextResult) ||
            row.answer.trim().startsWith('<techpie-agent-call version="2"'))) {
      active = _savedTurn(row, isAgent: true)
        ..answer = ''
        ..phase = GenAiChatPhase.interrupted;
      turns.add(active!);
      pending = call;
      step = 0;
    } else {
      turns.add(_savedTurn(row));
    }
  }
  finishInterrupted();
  return List.unmodifiable(turns);
}

GenAiConversationTurn _savedTurn(
  GenAiSavedTurn saved, {
  bool isAgent = false,
}) =>
    GenAiConversationTurn(saved.prompt, isAgent: isAgent)
      ..answer = saved.answer
      ..reasoning = saved.reasoning
      ..attachedImageUrl = saved.imageUrls.firstOrNull
      ..attachedImageUrls = saved.imageUrls
      ..phase = saved.answer.isEmpty
          ? GenAiChatPhase.interrupted
          : GenAiChatPhase.completed;

GenAiAgentToolCall? _call(String value) =>
    decodeGenAiAgentRecord(value, allowLegacy: true)?.call;

Map<String, Object?>? _result(String value) =>
    decodeGenAiAgentRecord(value, allowLegacy: true)?.result;

bool _matches(GenAiAgentToolCall call, Map<String, Object?>? result) =>
    result != null &&
    result['call_id'] == call.id &&
    result['name'] == call.name;

bool _protocolEnvelope(String value) {
  final text = value.trim();
  return text.startsWith('<techpie-agent-') ||
      text.startsWith('```tool_call') ||
      text.startsWith('```tool_response');
}
