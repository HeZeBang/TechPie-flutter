import '../domain/genai_agent_contract.dart';
import '../domain/genai_agent_protocol.dart';
import '../domain/genai_context_record.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_chat_service.dart';
import 'genai_conversation_turn.dart';

/// Recovers display-only tasks from the server's append-only model-step log.
/// Imported text never restores approvals,
/// mutation receipts, or executable agent history.
List<GenAiConversationTurn> importGenAiLegacyConversation(
  List<GenAiSavedTurn> rows,
) {
  rows = rows.where((row) => !isGenAiContextExtraction(row.prompt)).toList();
  final turns = <GenAiConversationTurn>[];
  GenAiConversationTurn? active;
  GenAiAgentToolCall? pending;
  var step = 0;

  void appendEvent(GenAiAgentToolCall call, Map<String, Object?> result) {
    final turn = active!;
    if (call.name == 'reserve_court' &&
        (call.arguments['action'] == 'book' || call.arguments.isEmpty)) {
      // Recovered receipts never grant a second proposal when retrying this turn.
      turn.approvalBudget[call.name] = 1;
    }
    if (call.name == 'generate_image' && (result['error'] as Map?)?['code'] == 'approval_denied') {
      turn.approvalBudget['generate_image:denied'] = 1;
    }
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

  void consumeAnswer(GenAiSavedTurn row, {bool repairFollows = false}) {
    final turn = active!;
    if (row.reasoning.isNotEmpty) {
      turn.reasoning = [turn.reasoning, row.reasoning].where((part) => part.isNotEmpty).join('\n');
    }
    if (repairFollows) {
      pending = null;
      return;
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
    turn.answer = decodeGenAiAgentFinal(row.answer) ?? row.answer;
    turn.phase = turn.agentStatus.isEmpty ? GenAiChatPhase.completed : GenAiChatPhase.interrupted;
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
    final nextResult = index + 1 < rows.length ? _result(rows[index + 1].prompt) : null;
    final repairFollows = nextResult != null &&
        nextResult['call_id'] == null &&
        nextResult['name'] == null &&
        nextResult['ok'] == false;
    if (active != null &&
        pending == null &&
        response != null &&
        response['call_id'] == null &&
        response['ok'] == false) {
      consumeAnswer(row, repairFollows: repairFollows);
      continue;
    }
    if (active != null && pending != null) {
      if (_matches(pending!, response)) {
        appendEvent(pending!, response!);
        pending = null;
        consumeAnswer(row, repairFollows: repairFollows);
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
    if (repairFollows) {
      active = _savedTurn(row, isAgent: true)..answer = '';
      turns.add(active!);
      pending = null;
      step = 0;
      continue;
    }
    // A standalone code example is still ordinary text. Only a matching,
    // adjacent call/result pair establishes an old tool-assisted trajectory.
    if (call != null &&
        (_matches(call, nextResult) ||
            row.answer.trim().startsWith('<techpie-agent-call version='))) {
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
      ..answer = decodeGenAiAgentFinal(saved.answer) ?? saved.answer
      ..reasoning = saved.reasoning
      ..attachedImageUrl = saved.imageUrls.firstOrNull
      ..attachedImageUrls = saved.imageUrls
      ..phase = saved.answer.isEmpty ? GenAiChatPhase.interrupted : GenAiChatPhase.completed;

GenAiAgentToolCall? _call(String value) => decodeGenAiAgentRecord(value, allowLegacy: true)?.call;

Map<String, Object?>? _result(String value) =>
    decodeGenAiAgentRecord(value, allowLegacy: true)?.result;

bool _matches(GenAiAgentToolCall call, Map<String, Object?>? result) =>
    result != null && result['call_id'] == call.id && result['name'] == call.name;

bool _protocolEnvelope(String value) {
  final text = value.trim();
  return text.startsWith('<techpie-agent-') ||
      text.startsWith('```tool_call') ||
      text.startsWith('```tool_response');
}
